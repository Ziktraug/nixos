{
  config,
  pkgs,
  lib,
  claude-code,
  ...
}:

with lib;

let
  cfg = config.applications.devtools.ai.claude-code;
in
{
  options.applications.devtools.ai.claude-code = {
    enable = mkEnableOption "Claude Code AI coding agent";

    dotfiles = {
      enable = mkOption {
        type = types.bool;
        default = cfg.enable;
        description = "Manage Claude Code dotfiles";
      };
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      claude-code.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];

    dotfiles = mkIf cfg.dotfiles.enable {
      enable = true;
      modules.claude-code = {
        enable = true;
        sourceDir = "modules/devtools/ai/claude-code";
        mappings = {
          settings = {
            source = "settings.json";
            target = "$HOME/.claude/settings.json";
          };
          settings-local = {
            source = "settings-local-example.json";
            target = "$HOME/.claude/settings.local.json";
          };
        };
      };
    };
  };
}
