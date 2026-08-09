{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.devtools.ide.cursor;
in
{
  options.applications.devtools.ide.cursor = {
    enable = mkEnableOption "Cursor editor";

    dotfiles = {
      enable = mkOption {
        type = types.bool;
        default = cfg.enable;
        description = "Manage Cursor dotfiles";
      };
    };
  };

  config = mkIf cfg.enable {
    unfreePackages = [
      "cursor"
      "code-cursor-fhs"
    ];

    # Install Cursor (FHS version to fix cursor-agent Node.js compatibility after flake upgrade)
    # Chrome and environment variables are provided by browser-automation module
    environment.systemPackages = with pkgs; [
      code-cursor-fhs
    ];

    # Configure dotfiles with inline mappings
    dotfiles = mkIf cfg.dotfiles.enable {
      enable = true;
      modules.cursor = {
        enable = true;
        sourceDir = "modules/devtools/ide/cursor";
        mappings = {
          settings = {
            source = "settings.json";
            target = "$HOME/.config/Cursor/User/settings.json";
          };
          keybindings = {
            source = "keybindings.json";
            target = "$HOME/.config/Cursor/User/keybindings.json";
          };
        };
      };
    };
  };
}
