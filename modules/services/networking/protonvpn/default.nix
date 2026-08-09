{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.services.networking.protonvpn;
  autostartWaitScript = pkgs.writeShellScript "protonvpn-autostart-wait" ''
    set -eu

    remaining=${toString cfg.autostartDelay}

    while true; do
      if ${pkgs.networkmanager}/bin/nm-online -q --timeout=1 \
        && ${pkgs.coreutils}/bin/timeout 1 ${pkgs.systemd}/bin/busctl --user call \
          org.freedesktop.secrets \
          /org/freedesktop/secrets \
          org.freedesktop.DBus.Properties \
          Get ss \
          org.freedesktop.Secret.Service \
          Collections >/dev/null 2>&1; then
        exit 0
      fi

      if [ "$remaining" -le 0 ]; then
        exit 1
      fi

      remaining=$((remaining - 1))
      ${pkgs.coreutils}/bin/sleep 1
    done
  '';
in
{
  options.applications.services.networking.protonvpn = {
    enable = mkEnableOption "ProtonVPN client";
    autostart = mkEnableOption "auto-launch ProtonVPN on login";
    autostartDelay = mkOption {
      type = types.int;
      default = 10;
      description = "Maximum wait in seconds for NetworkManager and GNOME Secret Service before starting ProtonVPN";
    };
    dotfiles.enable = mkEnableOption "ProtonVPN dotfiles management";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      pkgs."proton-vpn"
    ];

    # Start ProtonVPN only in the real GNOME session, then wait until
    # NetworkManager and the Secret Service are both available.
    systemd.user.services.protonvpn-autostart = mkIf cfg.autostart {
      description = "ProtonVPN autostart";
      wantedBy = [ "gnome-session@gnome.target" ];
      after = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStartPre = autostartWaitScript;
        ExecStart = "${pkgs."proton-vpn"}/bin/protonvpn-app --start-minimized";
        Restart = "on-failure";
        RestartSec = "15s";
      };
    };

    dotfiles = mkIf cfg.dotfiles.enable {
      enable = true;
      modules.protonvpn = {
        enable = true;
        sourceDir = "modules/services/networking/protonvpn";
        mappings = {
          appConfig = {
            source = "app-config.json";
            target = "$HOME/.config/Proton/VPN/app-config.json";
          };
          settings = {
            source = "settings.json";
            target = "$HOME/.config/Proton/VPN/settings.json";
          };
        };
      };
    };
  };
}
