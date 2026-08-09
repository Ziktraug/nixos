{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.games.heroic;
in
{
  options.applications.games.heroic = {
    enable = mkEnableOption "Heroic Games Launcher for Epic Games Store, GOG, and Amazon Prime Games";

    withGamescope = mkEnableOption "Include Gamescope for enhanced gaming experience";
    withProtonUp = mkEnableOption "Include ProtonUp-Qt for Proton version management";
  };

  config = mkIf cfg.enable {
    # Enable Gamescope if requested
    programs.gamescope.enable = cfg.withGamescope;

    # Override Heroic to include optional dependencies and add additional packages
    environment.systemPackages = [
      (pkgs.heroic.override {
        extraPkgs =
          pkgs:
          lib.optionals cfg.withGamescope [ pkgs.gamescope ]
          ++ lib.optionals cfg.withProtonUp [ pkgs.protonup-qt ];
      })
    ]
    ++ lib.optionals cfg.withProtonUp (
      with pkgs;
      [
        protonup-qt
      ]
    );

    # Ensure 32-bit graphics support for Wine/Proton compatibility
    hardware.graphics.enable32Bit = true;

    # Enable 32-bit audio support
    services.pipewire.alsa.support32Bit = true;
  };
}
