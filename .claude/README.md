# Claude Code & OpenCode Configuration

This directory contains configuration for Claude Code and OpenCode for the NixOS modular configuration project.

## Structure

### Claude Code (`.claude/`)

```
.claude/
├── CLAUDE.md              # Project documentation and instructions
├── settings.json          # Project-wide settings (hooks, permissions)
├── settings.local.json    # Personal settings (gitignored)
├── agent-registry.json    # Custom agent definitions
├── agents/                # Agent prompt files
│   ├── nixos-module-architect.md
│   ├── config-validator.md
│   ├── dotfiles-expert.md
│   ├── nixos-debugger.md
│   ├── service-integrator.md
│   └── hyprland-configurator.md
├── commands/              # Custom slash commands
│   ├── review.md
│   ├── validate.md
│   ├── add-module.md
│   ├── check-syntax.md
│   └── debug-error.md
├── skills/                # Agent skills (shared with OpenCode)
│   ├── nix-modules/
│   ├── dotfiles-management/
│   ├── agentic-delegation-strategy/
│   ├── agentic-tool-normalization/
│   └── agentic-diagnostic-probe/
├── templates/             # Module templates
├── context/               # Reference documentation
├── workflows/             # Step-by-step guides
├── hooks/                 # Event hooks (Claude Code only)
└── schemas/               # JSON schemas
```

### OpenCode (`.opencode/`)

```
.opencode/
├── commands/              # Custom slash commands
│   ├── validate.md
│   ├── add-module.md
│   ├── check-syntax.md
│   ├── debug-error.md
│   └── review.md
└── agents/                # Subagent definitions
    ├── nixos-debugger.md
    ├── nixos-module-architect.md
    ├── config-validator.md
    ├── dotfiles-expert.md
    ├── service-integrator.md
    └── hyprland-configurator.md
```

### Root Config

```
opencode.json              # OpenCode configuration (permissions, theme)
```

## Feature Compatibility Matrix

| Feature               | Claude Code          | OpenCode        | Notes                                  |
| --------------------- | -------------------- | --------------- | -------------------------------------- |
| `CLAUDE.md`           | Primary              | Fallback        | Works for both                         |
| `.claude/skills/`     | Yes                  | Yes             | Shared - no changes needed             |
| `.opencode/commands/` | No                   | Yes             | OpenCode-specific                      |
| `.opencode/agents/`   | No                   | Yes             | Converted format with `mode: subagent` |
| `.cursor/rules/`      | No                   | Yes             | Via `instructions` in opencode.json    |
| Hooks                 | `settings.json`      | N/A             | Embedded in skills for OpenCode        |
| Permissions           | `settings.json`      | `opencode.json` | Different config format                |
| Templates             | `.claude/templates/` | N/A             | Referenced from rules                  |
| Workflows             | `.claude/workflows/` | N/A             | Referenced from rules                  |

## Quick Reference

### Commands

| Command                        | Description                               |
| ------------------------------ | ----------------------------------------- |
| `/review`                      | Review staged NixOS configuration changes |
| `/validate`                    | Run `./script/check.sh` validation          |
| `/add-module <app> [category]` | Create new application module             |
| `/check-syntax <file>`         | Check Nix file syntax                     |
| `/debug-error [message]`       | Debug build errors                        |

### Agents/Subagents

| Agent                    | Purpose                    |
| ------------------------ | -------------------------- |
| `nixos-module-architect` | Create NixOS modules       |
| `config-validator`       | Validate configurations    |
| `dotfiles-expert`        | Manage dotfiles mappings   |
| `nixos-debugger`         | Debug build failures       |
| `service-integrator`     | Configure systemd services |
| `hyprland-configurator`  | Desktop environment setup  |
| `memory-distiller`       | Propose durable memory candidates at checkpoints |

### Skills

| Skill                         | Purpose                           |
| ----------------------------- | --------------------------------- |
| `nix-modules`                 | NixOS module development          |
| `dotfiles-management`         | Dotfiles system management        |
| `agentic-delegation-strategy` | When/how to delegate to subagents |
| `agentic-tool-normalization`  | Reduce large tool outputs         |
| `agentic-diagnostic-probe`    | Collect repeated observations     |

### Global vs Project Skills

- `.claude/skills/` contains repo-local skills that should only exist inside this repository.
- `modules/devtools/ai/global-skills/` contains globally installed skills tracked by this repo.
- The `global-skills` Nix module installs tracked global skills into `~/.claude/skills/`, `~/.agents/skills/`, and `~/.config/opencode/skills/` for Agent Skills runtimes.
- Matt Pocock skills are materialized at the immutable revision declared by `modules/devtools/ai/global-skills/update-flake-pre.sh` in the gitignored cache `modules/devtools/ai/global-skills/.cache/matt-pocock-skills/` during `script/update.sh`.
- Matt Pocock skills are symlinked from the cache for Claude Code/OpenCode and projected into Cursor rules under `~/.cursor/rules/` plus Copilot instructions under `~/.github/instructions/`.
- Only Matt's promoted `engineering`, `productivity`, and `misc` buckets are globally installed; `personal` and `deprecated` are ignored.
- The same module can also install small convenience wrappers like `recent-work-context` for direct shell usage.

### Critical Rules

1. **NEVER** execute `sudo`, `git add/commit/push`, or `nix flake update`
2. **ALWAYS** run `./script/check.sh` after .nix file changes
3. **ONLY** add minimal package installation initially
4. **ASK** before adding dotfiles management
5. **DELEGATE** system rebuilds to user

### Validation Commands

```bash
# Run these yourself (read-only)
./script/check.sh
nixos-rebuild dry-run --flake .#example
nix build --no-link .#nixosConfigurations.example.config.system.build.toplevel --no-update-lock-file --no-write-lock-file

# Delegate to user (requires privileges)
sudo nixos-rebuild switch --flake .#<host>
```

## Files

### Shared (Git-tracked)

- `CLAUDE.md` - Project instructions (read by both tools)
- `settings.json` - Claude Code permissions and hooks
- `agent-registry.json` - Claude Code agent definitions
- `opencode.json` - OpenCode permissions and config
- Skills in `.claude/skills/` - Shared by both tools

### Personal (Gitignored)

- `settings.local.json` - Personal permission overrides
- `CLAUDE.local.md` - Personal notes

## Related

- [.cursor/rules/](../.cursor/rules/) - Cursor IDE rules (also used by OpenCode)
- [CLAUDE.md](CLAUDE.md) - Main project documentation
