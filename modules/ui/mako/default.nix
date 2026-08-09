{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.ui.mako;
in
{
  options.applications.ui.mako = {
    enable = mkEnableOption "Mako notification daemon for Wayland";

    dotfiles = {
      enable = mkOption {
        type = types.bool;
        default = cfg.enable;
        description = "Manage Mako configuration files";
      };
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.mako ];

    dotfiles = mkIf cfg.dotfiles.enable {
      enable = true;
      modules.mako = {
        enable = true;
        sourceDir = "modules/ui/mako";
        mappings = {
          config = {
            source = "config";
            target = "$HOME/.config/mako/config";
          };
        };
      };
    };
  };
}
