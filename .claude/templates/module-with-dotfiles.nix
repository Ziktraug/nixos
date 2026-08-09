# Application Module with Dotfiles Template
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
    environment.systemPackages = [
      pkgs.example-app
    ];

    dotfiles = mkIf cfg.dotfiles.enable {
      enable = true;
      modules.exampleApp = {
        enable = true;
        sourceDir = "modules/<category>/example-app";
        mappings = {
          config = {
            source = "config.json";
            target = "$HOME/.config/example-app/config.json";
          };
        };
      };
    };
  };
}
