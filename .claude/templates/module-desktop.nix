# Desktop/UI Module Template
# Replace exampleApp with application name
# Replace example-app with package/source directory name
# Replace <App description> with description

{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.exampleApp;
in
{
  options.applications.exampleApp = {
    enable = mkEnableOption "<App description>";

    dotfiles = {
      enable = mkOption {
        type = types.bool;
        default = cfg.enable;
        description = "Manage example-app dotfiles";
      };
    };
  };

  config = mkIf cfg.enable {
    # Main program/package
    environment.systemPackages = [
      pkgs.example-app
      # Related utilities
    ];

    # Program-specific enablement (if applicable)
    # programs.exampleApp.enable = true;

    # Environment variables for Wayland/X11
    # environment.sessionVariables = {
    #   VARIABLE_NAME = "value";
    # };

    # XDG Portal configuration (for Wayland)
    # xdg.portal = {
    #   enable = true;
    #   extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    # };

    # Dotfiles management
    dotfiles = mkIf cfg.dotfiles.enable {
      enable = true;
      modules.exampleApp = {
        enable = true;
        sourceDir = "modules/<category>/example-app";
        mappings = {
          config = {
            source = "config";
            target = "$HOME/.config/example-app/config";
          };
          style = {
            source = "style.css";
            target = "$HOME/.config/example-app/style.css";
          };
        };
      };
    };
  };
}
