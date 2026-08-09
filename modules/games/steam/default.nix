{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.games.steam;
in
{
  options.applications.games.steam = {
    enable = mkEnableOption "Steam gaming platform";
  };

  config = mkIf cfg.enable {
    unfreePackages = [
      "steam"
      "steam-original"
      "steam-run"
      "steam-unwrapped"
      "steamcmd"
    ];

    programs.steam = {
      enable = true;
      package = pkgs.steam.override {
        extraPkgs = pkgs': with pkgs'; [ gamemode ];
      };
      # Firewall settings (disabled by default for security)
      # Enable these only if you need the features
      remotePlay.openFirewall = false; # Remote Play - opens ports 27031-27036/UDP
      dedicatedServer.openFirewall = false; # Dedicated Server - opens ports 27015/TCP+UDP
    };

    environment.systemPackages = with pkgs; [
      steamcmd # Command-line Steam client
    ];

    hardware.graphics.enable32Bit = true;

    # Steam-specific environment variables for GPU acceleration
    environment.sessionVariables = {
      # Enable hardware acceleration for Steam client
      "STEAM_DISABLE_GPU" = "0";
      "STEAM_USE_GPU" = "1";
    };
  };
}
