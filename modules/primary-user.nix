{ config, lib, ... }:

with lib;

let
  cfg = config.primaryUser;
in
{
  options.primaryUser.name = mkOption {
    type = types.strMatching ".+";
    description = "Primary interactive user for user-scoped application modules";
    example = "alice";
  };

  config = {
    assertions = [
      {
        assertion = config.users.users ? ${cfg.name};
        message = "Primary user '${cfg.name}' must exist in users.users";
      }
    ];

    dotfiles.user = mkDefault cfg.name;
    applications.devtools.shells.fish.user = mkDefault cfg.name;
    applications.games.gamemode.user = mkDefault cfg.name;
  };
}
