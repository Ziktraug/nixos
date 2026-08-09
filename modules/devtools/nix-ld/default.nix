{
  config,
  lib,
  ...
}:

with lib;

{
  options.applications.devtools.nix-ld = {
    enable = mkEnableOption "nix-ld support for unpatched dynamic binaries";
  };

  config = mkIf config.applications.devtools.nix-ld.enable {
    programs.nix-ld.enable = true;
  };
}
