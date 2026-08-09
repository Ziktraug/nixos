{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.ui.hyprpaper;
in
{
  options.applications.ui.hyprpaper = {
    enable = mkEnableOption "Hyprpaper wallpaper manager for Hyprland";

    dotfiles = {
      enable = mkOption {
        type = types.bool;
        default = cfg.enable;
        description = "Manage Hyprpaper configuration files";
      };
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.hyprpaper ];

    dotfiles = mkIf cfg.dotfiles.enable {
      enable = true;
      modules.hyprpaper = {
        enable = true;
        sourceDir = "modules/ui/hyprpaper";
        mappings = {
          config = {
            source = "hyprpaper.conf";
            target = "$HOME/.config/hypr/hyprpaper.conf";
          };
        };
      };
    };
  };
}
