{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.devtools.cli.github;
in
{
  options.applications.devtools.cli.github = {
    enable = mkEnableOption "GitHub CLI (gh)";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      gh
    ];
  };
}
