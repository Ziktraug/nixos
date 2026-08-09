{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.devtools.tui.update-tui;

  updateTui = pkgs.writeShellScriptBin "update" ''
    export PATH="${
      lib.makeBinPath [
        pkgs.bun
        pkgs.git
        pkgs.gum
        pkgs.jq
        pkgs.nix
      ]
    }:$PATH"

    exec ${pkgs.bun}/bin/bun ${./update-tui.ts} "$@"
  '';
in
{
  options.applications.devtools.tui.update-tui = {
    enable = mkEnableOption "compact TUI wrapper for NixOS flake updates";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.gum
      updateTui
    ];
  };
}
