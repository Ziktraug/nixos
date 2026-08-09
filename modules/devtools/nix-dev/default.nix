{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

{
  options.applications.devtools.nix-dev = {
    enable = mkEnableOption "Nix development tools (nixd LSP and nixfmt formatter)";
  };

  config = mkIf config.applications.devtools.nix-dev.enable {
    environment.systemPackages = with pkgs; [
      jq # Required by script/rebuild.sh recap generation
      nixd # Nix language server
      nixfmt # Official Nix formatter
      nil # Alternative Nix language server
    ];
  };
}
