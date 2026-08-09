{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.devtools.tui.codex-monitor;

  codexMonitor = pkgs.writeShellScriptBin "codex-monitor" ''
    exec ${pkgs.bun}/bin/bun ${./codex-monitor.ts} "$@"
  '';
in
{
  options.applications.devtools.tui.codex-monitor = {
    enable = mkEnableOption "Codex Monitor - CLI tool for local Codex usage sessions";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ codexMonitor ];
  };
}
