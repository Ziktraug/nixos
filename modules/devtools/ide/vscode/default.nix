{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.devtools.ide.vscode;
in
{
  options.applications.devtools.ide.vscode = {
    enable = mkEnableOption "VS Code editor";

    dotfiles = {
      enable = mkOption {
        type = types.bool;
        default = cfg.enable;
        description = "Manage VS Code dotfiles";
      };
    };
  };

  config = mkIf cfg.enable {
    unfreePackages = [ "vscode" ];

    environment.systemPackages = [ pkgs.vscode ];

    dotfiles = mkIf cfg.dotfiles.enable {
      enable = true;
      modules.vscode = {
        enable = true;
        sourceDir = "modules/devtools/ide/vscode";
        mappings = {
          settings = {
            source = "settings.json";
            target = "$HOME/.config/Code/User/settings.json";
          };
          keybindings = {
            source = "keybindings.json";
            target = "$HOME/.config/Code/User/keybindings.json";
          };
        };
      };
    };
  };
}
