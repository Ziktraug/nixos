{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  solaarCfg = config.applications.hardware.solaar;
  headsetCfg = config.applications.hardware.logitechHeadsetBattery;

  pollerScript = pkgs.writeText "logitech-headset-battery-poller.py" ''
    import argparse
    import os
    import random
    import select
    import struct
    import sys
    import time

    HIDPP_SHORT_MESSAGE_ID = 0x10
    HIDPP_LONG_MESSAGE_ID = 0x11
    HIDPP_DEVICE_DIRECT = 0xFF
    ADC_MEASUREMENT_FEATURE = 0x1F20

    BATTERY_VOLTAGE_TO_PERCENT = [
        (4186, 100),
        (4067, 90),
        (3989, 80),
        (3922, 70),
        (3859, 60),
        (3811, 50),
        (3778, 40),
        (3751, 30),
        (3717, 20),
        (3671, 10),
        (3646, 5),
        (3579, 2),
        (3500, 0),
    ]


    def estimate_percent_from_mv(mv):
        if mv >= BATTERY_VOLTAGE_TO_PERCENT[0][0]:
            return BATTERY_VOLTAGE_TO_PERCENT[0][1]
        if mv <= BATTERY_VOLTAGE_TO_PERCENT[-1][0]:
            return BATTERY_VOLTAGE_TO_PERCENT[-1][1]

        for i in range(len(BATTERY_VOLTAGE_TO_PERCENT) - 1):
            v_high, p_high = BATTERY_VOLTAGE_TO_PERCENT[i]
            v_low, p_low = BATTERY_VOLTAGE_TO_PERCENT[i + 1]
            if v_low <= mv <= v_high:
                percent = p_low + (p_high - p_low) * (mv - v_low) / (v_high - v_low)
                return round(percent)

        return 0


    def resolve_hidraw_path(device_path):
        path = os.path.realpath(device_path)
        if not path.startswith("/dev/hidraw"):
            raise RuntimeError("resolved device path is not a hidraw node")
        if not os.path.exists(path):
            raise RuntimeError("hidraw node does not exist")
        return path


    def drain_input(fd):
        while True:
            try:
                data = os.read(fd, 64)
                if not data:
                    return
            except BlockingIOError:
                return


    def send_hidpp_request(fd, request_id, params, timeout_s):
        sw_id = random.randint(0x02, 0x0F)
        request_id_with_sw = (request_id & 0xFFF0) | sw_id
        request_header = struct.pack("!H", request_id_with_sw)
        request_data = request_header + params

        packet = struct.pack("!BB18s", HIDPP_LONG_MESSAGE_ID, HIDPP_DEVICE_DIRECT, request_data)
        os.write(fd, packet)

        deadline = time.monotonic() + timeout_s
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("hidpp request timed out")

            readable, _, _ = select.select([fd], [], [], remaining)
            if not readable:
                continue

            data = os.read(fd, 64)
            if len(data) < 4:
                continue

            report_id = data[0]
            devnumber = data[1]
            payload = data[2:]

            if report_id not in (HIDPP_SHORT_MESSAGE_ID, HIDPP_LONG_MESSAGE_ID):
                continue
            if devnumber not in (HIDPP_DEVICE_DIRECT, 0x00):
                continue

            if report_id == HIDPP_SHORT_MESSAGE_ID and payload[:1] == b"\x8f" and payload[1:3] == request_header:
                raise RuntimeError("hidpp short error response")
            if payload[:1] == b"\xff" and payload[1:3] == request_header:
                raise RuntimeError("hidpp feature error response")
            if payload[:2] == request_header:
                return payload[2:]


    def read_headset_percent(hidraw_path, timeout_s):
        fd = os.open(hidraw_path, os.O_RDWR | os.O_CLOEXEC)
        try:
            os.set_blocking(fd, False)
            drain_input(fd)

            feature_reply = send_hidpp_request(
                fd,
                request_id=0x0000,
                params=struct.pack("!H", ADC_MEASUREMENT_FEATURE),
                timeout_s=timeout_s,
            )
            if not feature_reply:
                raise RuntimeError("missing feature lookup reply")

            feature_index = feature_reply[0]
            if feature_index == 0:
                raise RuntimeError("adc measurement feature not available")

            adc_reply = send_hidpp_request(
                fd,
                request_id=(feature_index << 8),
                params=b"",
                timeout_s=timeout_s,
            )
            if len(adc_reply) < 3:
                raise RuntimeError("adc reply too short")

            voltage_mv, flags = struct.unpack("!HB", adc_reply[:3])
            if (flags & 0x01) == 0:
                raise RuntimeError("headset inactive")

            return estimate_percent_from_mv(voltage_mv)
        finally:
            os.close(fd)


    def main():
        parser = argparse.ArgumentParser(description="Poll Logitech headset battery percentage")
        parser.add_argument("--device", required=True, help="Path to headset hidraw by-id symlink")
        parser.add_argument("--timeout", type=float, default=2.0, help="Request timeout in seconds")
        args = parser.parse_args()

        try:
            hidraw_path = resolve_hidraw_path(args.device)
            percent = read_headset_percent(hidraw_path, args.timeout)
            print(percent)
            return 0
        except Exception:
            return 1


    if __name__ == "__main__":
        sys.exit(main())
  '';

  updateScript = pkgs.writeShellScript "logitech-headset-battery-update" ''
    set -eu

    runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$UID}"
    cache_dir="$runtime_dir/logitech-headset-battery"
    cache_file="$cache_dir/percent"
    lock_file="$cache_dir/update.lock"

    mkdir -p "$cache_dir"

    exec 9>"$lock_file"
    if ! ${pkgs.util-linux}/bin/flock -n 9; then
      exit 0
    fi

    value="$(${pkgs.coreutils}/bin/timeout ${toString headsetCfg.timeoutSeconds} \
      ${pkgs.python3}/bin/python3 "${pollerScript}" --device "${headsetCfg.devicePath}" --timeout ${toString headsetCfg.requestTimeoutSeconds} 2>/dev/null || true)"

    if printf "%s" "$value" | ${pkgs.gnugrep}/bin/grep -Eq '^[0-9]+$'; then
      if [ "$value" -ge 0 ] && [ "$value" -le 100 ]; then
        tmp_file="$cache_file.tmp"
        printf "%s\n" "$value" > "$tmp_file"
        ${pkgs.coreutils}/bin/mv "$tmp_file" "$cache_file"
        exit 0
      fi
    fi

    # Never keep displaying a value after polling proves the headset is
    # unavailable or returns an invalid response.
    ${pkgs.coreutils}/bin/rm -f "$cache_file"
  '';
in
{
  options.applications.hardware = {
    solaar = {
      enable = mkEnableOption "Solaar Logitech device manager";
      dotfiles.enable = mkEnableOption "Solaar dotfiles management";
    };

    logitechHeadsetBattery = {
      enable = mkEnableOption "Logitech headset battery poller";

      intervalSeconds = mkOption {
        type = types.int;
        default = 120;
        description = "Polling interval in seconds";
      };

      timeoutSeconds = mkOption {
        type = types.int;
        default = 5;
        description = "Polling wrapper timeout in seconds";
      };

      requestTimeoutSeconds = mkOption {
        type = types.int;
        default = 2;
        description = "Single HID++ request timeout in seconds";
      };

      devicePath = mkOption {
        type = types.str;
        default = "/dev/input/by-id/usb-Logitech_PRO_X_Wireless_Gaming_Headset-if03-hidraw";
        description = "Stable by-id path to the headset hidraw device";
      };
    };
  };

  config = mkMerge [
    (mkIf solaarCfg.enable {
      environment.systemPackages = with pkgs; [
        solaar
      ];

      hardware.logitech.wireless.enable = true;

      dotfiles = mkIf solaarCfg.dotfiles.enable {
        enable = true;
        modules.solaar = {
          enable = true;
          sourceDir = "modules/hardware/solaar";
        };
      };
    })

    (mkIf headsetCfg.enable {
      # Keep Logitech wireless udev permissions without installing Solaar.
      hardware.logitech.wireless.enable = true;

      systemd.user.services.logitech-headset-battery-poll = {
        description = "Poll Logitech headset battery percentage";
        after = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = updateScript;
        };
      };

      systemd.user.timers.logitech-headset-battery-poll = {
        description = "Periodic Logitech headset battery polling";
        wantedBy = [
          "timers.target"
          "graphical-session.target"
        ];
        after = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        timerConfig = {
          # Schedule the initial poll relative to timer activation. OnBootSec
          # may already be in the past when the graphical session starts,
          # leaving the timer active but with no next trigger.
          OnActiveSec = "30s";
          OnUnitInactiveSec = "${toString headsetCfg.intervalSeconds}s";
          Unit = "logitech-headset-battery-poll.service";
        };
      };
    })
  ];
}
