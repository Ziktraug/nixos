# Git Configuration Module
#
# This module manages Git installation and configuration files with per-directory
# SSH key and email settings using includeIf directives.
#
# IMPORTANT: SSH keys are NOT managed by this module and must be set up manually.
# See: docs/git-ssh-configuration.md for SSH key setup instructions.
#
# Identity files and SSH keys are supplied by the private host layer.

{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.devtools.git;
in
{
  options.applications.devtools.git = {
    enable = mkEnableOption "Git version control";

    dotfiles = {
      enable = mkOption {
        type = types.bool;
        default = cfg.enable;
        description = "Manage Git dotfiles";
      };
    };
  };

  config = mkIf cfg.enable {
    # Install the package
    environment.systemPackages = with pkgs; [
      git
    ];

    # Configure dotfiles with inline mappings
    dotfiles = mkIf cfg.dotfiles.enable {
      enable = true;
      modules.git = {
        enable = true;
        sourceDir = "modules/devtools/git";
        mappings = {
          config = {
            source = "gitconfig";
            target = "$HOME/.gitconfig";
          };
          ignore = {
            source = "gitignore_global";
            target = "$HOME/.gitignore_global";
          };
        };
      };
    };
  };
}
