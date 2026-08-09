{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.applications.ui.waybar;
in
{
  options.applications.ui.waybar = {
    enable = mkEnableOption "Waybar status bar";

    autostart = mkOption {
      type = types.bool;
      default = true;
      description = "Start Waybar automatically in graphical sessions";
    };

    dotfiles = {
      enable = mkOption {
        type = types.bool;
        default = cfg.enable;
        description = "Manage Waybar configuration files";
      };
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      waybar
      bash
      jq
      pavucontrol
      lm_sensors # For temperature monitoring in Waybar
    ];

    systemd.user.services.waybar = mkIf cfg.autostart {
      description = "Waybar status bar";
      wantedBy = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      path = with pkgs; [
        bash
        coreutils
        gawk
        gnugrep
        gnused
        jq
        lm_sensors
      ];
      serviceConfig = {
        ExecStart = "${pkgs.waybar}/bin/waybar -c %h/.config/waybar/config.json -s %h/.config/waybar/style.css";
        Restart = "on-failure";
        RestartSec = 2;
      };
    };

    dotfiles = mkIf cfg.dotfiles.enable {
      enable = true;
      modules.waybar = {
        enable = true;
        sourceDir = "modules/ui/waybar";
        mappings = {
          config = {
            source = "config.json";
            target = "$HOME/.config/waybar/config.json";
          };
          style = {
            source = "style.css";
            target = "$HOME/.config/waybar/style.css";
          };
          gpu-script = {
            source = "scripts/gpu-info.sh";
            target = "$HOME/.config/waybar/scripts/gpu-info.sh";
          };
          cpu-script = {
            source = "scripts/cpu-info.sh";
            target = "$HOME/.config/waybar/scripts/cpu-info.sh";
          };
          temp-script = {
            source = "scripts/temp-info.sh";
            target = "$HOME/.config/waybar/scripts/temp-info.sh";
          };
          solaar-mouse = {
            source = "scripts/solaar-mouse.sh";
            target = "$HOME/.config/waybar/scripts/solaar-mouse.sh";
          };
          solaar-headset = {
            source = "scripts/solaar-headset.sh";
            target = "$HOME/.config/waybar/scripts/solaar-headset.sh";
          };
          ai-usage = {
            source = "scripts/ai-usage.sh";
            target = "$HOME/.config/waybar/scripts/ai-usage.sh";
          };
        };
      };
    };
  };
}
