{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.devtools.shells.aliases;
in
{
  options.applications.devtools.shells.aliases = {
    enable = mkEnableOption "shared shell aliases";

    dotfiles = {
      enable = mkOption {
        type = types.bool;
        default = cfg.enable;
        description = "Manage aliases dotfiles";
      };
    };
  };

  config = mkIf cfg.enable {
    # Install the package
    environment.systemPackages = with pkgs; [
      # No additional packages needed for aliases
    ];

    # Configure dotfiles with inline mappings
    dotfiles = mkIf cfg.dotfiles.enable {
      enable = true;
      modules.aliases = {
        enable = true;
        sourceDir = "modules/devtools/shells/aliases";
        mappings = {
          aliases = {
            source = "aliases";
            target = "$HOME/.aliases";
          };
        };
      };
    };
  };
}
