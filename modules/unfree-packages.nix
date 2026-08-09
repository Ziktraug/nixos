{ config, lib, ... }:

with lib;

{
  options.unfreePackages = mkOption {
    type = types.listOf types.str;
    default = [ ];
    description = "List of unfree package names allowed by modules";
  };

  config = {
    nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) config.unfreePackages;
  };
}
