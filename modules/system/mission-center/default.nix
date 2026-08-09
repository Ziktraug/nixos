{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.system.mission-center;
in
{
  options.applications.system.mission-center = {
    enable = mkEnableOption "Mission Center system monitor";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      mission-center
    ];
  };
}
