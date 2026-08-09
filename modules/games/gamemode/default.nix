{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.games.gamemode;
in
{
  options.applications.games.gamemode = {
    enable = mkEnableOption "GameMode performance optimization for games";

    user = mkOption {
      type = types.str;
      description = "User to add to gamemode group";
    };
  };

  config = mkIf cfg.enable {
    programs.gamemode = {
      enable = true;
      settings = {
        custom = {
          start = "${pkgs.libnotify}/bin/notify-send 'GameMode started'";
          end = "${pkgs.libnotify}/bin/notify-send 'GameMode ended'";
        };
      };
    };

    environment.systemPackages = with pkgs; [
      gamemode
      libnotify
    ];

    # Ensure user is in gamemode group
    users.groups.gamemode = { };
    users.users.${cfg.user}.extraGroups = [ "gamemode" ];
  };
}
