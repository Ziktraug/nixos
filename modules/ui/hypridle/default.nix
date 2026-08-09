{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.ui.hypridle;
in
{
  options.applications.ui.hypridle = {
    enable = mkEnableOption "Hypridle idle management daemon for Hyprland";

    dotfiles = {
      enable = mkOption {
        type = types.bool;
        default = cfg.enable;
        description = "Manage Hypridle configuration files";
      };
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.hypridle ];

    dotfiles = mkIf cfg.dotfiles.enable {
      enable = true;
      modules.hypridle = {
        enable = true;
        sourceDir = "modules/ui/hypridle";
        mappings = {
          config = {
            source = "hypridle.conf";
            target = "$HOME/.config/hypr/hypridle.conf";
          };
        };
      };
    };
  };
}
