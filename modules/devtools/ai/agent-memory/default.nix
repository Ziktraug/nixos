{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.devtools.ai.agent-memory;
  configJson = pkgs.writeText "agent-memory-config.json" (
    builtins.toJSON {
      globalRepoPath = cfg.globalRepoPath;
      managedRepos = cfg.managedRepos;
      autoCapture = {
        enable = cfg.autoCapture.enable;
        since = cfg.autoCapture.since;
        onCalendar = cfg.autoCapture.onCalendar;
        retentionDays = cfg.autoCapture.retentionDays;
        maxEvents = cfg.autoCapture.maxEvents;
      };
      adapters = cfg.adapters;
    }
  );
  agentMemoryBin = pkgs.writeShellScriptBin "agent-memory" ''
    export AGENT_MEMORY_CONFIG="${configJson}"
    export AGENT_MEMORY_GLOBAL_REPO="${cfg.globalRepoPath}"
    export AGENT_MEMORY_FLOCK_BIN="${pkgs.util-linux}/bin/flock"
    exec ${pkgs.bun}/bin/bun "${./scripts/agent-memory.ts}" "$@"
  '';
in
{
  options.applications.devtools.ai.agent-memory = {
    enable = mkEnableOption "declarative cross-agent operational memory";

    globalRepoPath = mkOption {
      type = types.str;
      description = "Absolute path to the global second-brain repository.";
      example = "/path/to/second-brain";
    };

    managedRepos = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Repositories where repo-local agent memory adapters should be managed.";
      example = [ "/path/to/repository" ];
    };

    autoCapture = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable a user timer that periodically harvests recent agent context into repo inboxes.";
      };

      since = mkOption {
        type = types.str;
        default = "24h";
        description = "Window passed to agent-memory harvest.";
      };

      onCalendar = mkOption {
        type = types.str;
        default = "hourly";
        description = "systemd OnCalendar expression for automatic harvest.";
      };

      retentionDays = mkOption {
        type = types.ints.positive;
        default = 30;
        description = "Maximum age in days for raw automatic harvest events before compaction.";
      };

      maxEvents = mkOption {
        type = types.ints.positive;
        default = 128;
        description = "Maximum number of raw automatic harvest events retained per repository.";
      };
    };

    adapters = mkOption {
      type = types.submodule {
        options = {
          claude = mkOption {
            type = types.bool;
            default = true;
            description = "Generate Claude Code repo adapter blocks.";
          };
          copilot = mkOption {
            type = types.bool;
            default = true;
            description = "Generate GitHub Copilot repo instructions.";
          };
          opencode = mkOption {
            type = types.bool;
            default = true;
            description = "Expose agent-memory to OpenCode instructions and permissions.";
          };
          cursor = mkOption {
            type = types.bool;
            default = true;
            description = "Generate Cursor repo rule adapter.";
          };
          generic = mkOption {
            type = types.bool;
            default = true;
            description = "Generate AGENTS.md-compatible adapter blocks.";
          };
        };
      };
      default = { };
      description = "Cross-agent adapter toggles.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.globalRepoPath != "";
        message = "applications.devtools.ai.agent-memory.globalRepoPath must be set.";
      }
    ];

    environment.systemPackages = with pkgs; [
      bun
      agentMemoryBin
    ];

    environment.sessionVariables = {
      AGENT_MEMORY_GLOBAL_REPO = cfg.globalRepoPath;
    };

    systemd.user.services.agent-memory-harvest = mkIf cfg.autoCapture.enable {
      description = "Harvest recent agent work into repo memory inboxes";
      serviceConfig = {
        Type = "oneshot";
        UMask = "0077";
        ExecStart = "${agentMemoryBin}/bin/agent-memory harvest --since ${cfg.autoCapture.since}";
      };
    };

    systemd.user.timers.agent-memory-harvest = mkIf cfg.autoCapture.enable {
      description = "Periodic agent-memory harvest";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.autoCapture.onCalendar;
        Persistent = true;
      };
    };

    dotfiles.modules.agent-memory-skill = {
      enable = true;
      sourceDir = "modules/devtools/ai/agent-memory";
      mappings = {
        skill = {
          source = "SKILL.md";
          target = "$HOME/.claude/skills/agent-memory/SKILL.md";
        };
        agents-skill = {
          source = "SKILL.md";
          target = "$HOME/.agents/skills/agent-memory/SKILL.md";
        };
        contract = {
          source = "references/memory-contract.md";
          target = "$HOME/.claude/skills/agent-memory/references/memory-contract.md";
        };
        agents-contract = {
          source = "references/memory-contract.md";
          target = "$HOME/.agents/skills/agent-memory/references/memory-contract.md";
        };
      };
    };
  };
}
