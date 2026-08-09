{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.games.waydroid;
in
{
  options.applications.games.waydroid = {
    enable = mkEnableOption "Waydroid Android container for mobile games (TFT, etc.)";
  };

  config = mkIf cfg.enable {
    virtualisation.waydroid.enable = true;

    environment.systemPackages = with pkgs; [
      wl-clipboard # Clipboard sharing with Android
      lzip # Required for waydroid_script
    ];
  };
}
