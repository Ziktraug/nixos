{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.games.mangohud;
in
{
  options.applications.games.mangohud = {
    enable = mkEnableOption "MangoHud performance overlay with gamemode integration";

    dotfiles = {
      enable = mkOption {
        type = types.bool;
        default = cfg.enable;
        description = "Manage MangoHud dotfiles";
      };
    };
  };

  config = mkIf cfg.enable {
    # Install the package
    environment.systemPackages = with pkgs; [
      mangohud
    ];

    # Automatically enable gamemode when mangohud is enabled
    applications.games.gamemode.enable = true;

    # Configure dotfiles with inline mappings
    dotfiles = mkIf cfg.dotfiles.enable {
      enable = true;
      modules.mangohud = {
        enable = true;
        sourceDir = "modules/games/mangohud";
        mappings = {
          config = {
            source = "MangoHud.conf";
            target = "$HOME/.config/MangoHud/MangoHud.conf";
          };
        };
      };
    };
  };
}
