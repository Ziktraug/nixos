{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.devtools.package-version-server;
in
{
  options.applications.devtools.package-version-server = {
    enable = mkEnableOption "Package Version Server language server";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      package-version-server
    ];
  };
}
