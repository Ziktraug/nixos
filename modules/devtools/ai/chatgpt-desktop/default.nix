{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.devtools.ai."chatgpt-desktop";
  chatgptDesktop = pkgs.callPackage ./package.nix { };
in
{
  options.applications.devtools.ai."chatgpt-desktop" = {
    enable = mkEnableOption "official ChatGPT desktop application";
  };

  config = mkIf cfg.enable {
    unfreePackages = [ "chatgpt-desktop" ];
    environment.systemPackages = [ chatgptDesktop ];
  };
}
