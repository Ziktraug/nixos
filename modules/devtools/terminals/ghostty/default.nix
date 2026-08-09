{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.devtools.terminals.ghostty;
in
{
  options.applications.devtools.terminals.ghostty = {
    enable = mkEnableOption "Ghostty terminal emulator";

    dotfiles = {
      enable = mkOption {
        type = types.bool;
        default = cfg.enable;
        description = "Manage Ghostty configuration files";
      };
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      ghostty
    ];

    # Manage config via the dotfiles system
    dotfiles = mkIf cfg.dotfiles.enable {
      enable = true;
      modules.ghostty = {
        enable = true;
        sourceDir = "modules/devtools/terminals/ghostty";
        mappings = {
          config = {
            source = "config";
            target = "$HOME/.config/ghostty/config";
          };
        };
      };
    };
  };
}
