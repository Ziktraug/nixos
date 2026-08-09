{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.system.btop;
in
{
  options.applications.system.btop = {
    enable = mkEnableOption "btop system monitor";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      btop
    ];
  };
}
