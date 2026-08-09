{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.ui."rofi-wayland";
in
{
  options.applications.ui."rofi-wayland" = {
    enable = mkEnableOption "Rofi (Wayland fork) application launcher";

    dotfiles = {
      enable = mkOption {
        type = types.bool;
        default = cfg.enable;
        description = "Manage Rofi configuration files";
      };
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.rofi ];

    # Provide a default config and manage it via the dotfiles system
    dotfiles = mkIf cfg.dotfiles.enable {
      enable = true;
      modules."rofi-wayland" = {
        enable = true;
        sourceDir = "modules/ui/rofi-wayland";
        mappings = {
          config = {
            source = "config.rasi";
            target = "$HOME/.config/rofi/config.rasi";
          };
          theme = {
            source = "catppuccin-mocha.rasi";
            target = "$HOME/.config/rofi/catppuccin-mocha.rasi";
          };
        };
      };
    };
  };
}
