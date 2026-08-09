{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.ui.hyprlock;
in
{
  options.applications.ui.hyprlock = {
    enable = mkEnableOption "Hyprlock screen locker for Hyprland";

    dotfiles = {
      enable = mkOption {
        type = types.bool;
        default = cfg.enable;
        description = "Manage Hyprlock configuration files";
      };
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.hyprlock ];

    # Enable PAM for hyprlock authentication
    security.pam.services.hyprlock = { };

    dotfiles = mkIf cfg.dotfiles.enable {
      enable = true;
      modules.hyprlock = {
        enable = true;
        sourceDir = "modules/ui/hyprlock";
        mappings = {
          config = {
            source = "hyprlock.conf";
            target = "$HOME/.config/hypr/hyprlock.conf";
          };
        };
      };
    };
  };
}
