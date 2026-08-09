{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

{
  options.applications.design.figma = {
    enable = mkEnableOption "Figma design tool";
  };

  config = mkIf config.applications.design.figma.enable {
    environment.systemPackages = with pkgs; [
      figma-linux
    ];
  };
}
