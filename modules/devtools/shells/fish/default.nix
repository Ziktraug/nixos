{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.devtools.shells.fish;
in
{
  options.applications.devtools.shells.fish = {
    enable = mkEnableOption "Fish shell";

    user = mkOption {
      type = types.str;
      description = "User to set fish as default shell for";
    };
  };

  config = mkIf cfg.enable {
    # Install the package
    environment.systemPackages = with pkgs; [
      fish
    ];

    # Enable fish shell
    programs.fish.enable = true;

    # Set fish as default shell for the user
    users.users.${cfg.user}.shell = pkgs.fish;

    # Enable dotfiles management
    dotfiles.enable = true;

    # Dotfiles management for fish configuration
    dotfiles.modules.fish = {
      enable = true;
      sourceDir = "modules/devtools/shells/fish";
      mappings = {
        "config" = {
          source = "config.fish";
          target = "$HOME/.config/fish/config.fish";
        };
      };
    };
  };
}
