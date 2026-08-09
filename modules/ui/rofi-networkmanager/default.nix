{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.ui.rofi-networkmanager;
in
{
  options.applications.ui.rofi-networkmanager = {
    enable = mkEnableOption "Rofi NetworkManager - network management UI";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      networkmanager_dmenu
    ];
  };
}
