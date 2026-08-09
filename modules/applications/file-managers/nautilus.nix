{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.file-managers.nautilus;
in
{
  options.applications.file-managers.nautilus = {
    enable = mkEnableOption "Nautilus (GNOME Files) file manager";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      nautilus
      sushi # File previewer (space bar preview)
    ];

    # Enable GNOME services needed by Nautilus
    services.gvfs.enable = true; # Virtual file systems (trash, network, etc.)
  };
}
