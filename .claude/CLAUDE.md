# NixOS Modular Configuration

Flake-based NixOS configuration with modular dotfiles management.

## Neutral Git Metadata

- Do not add `Co-authored-by`, `Generated-by`, or any other AI/agent attribution.
- Do not add harness/tool markers to branch names or PR titles (for example `agent/`, `codex/`, or `[codex]`).
- Use only the naming requested by the user or repository; otherwise use a plain, descriptive name.

## Agent Execution Model (Project Policy)

This repository uses modular rules and on-demand skills.

### Core Principle

Always create or update a short plan before performing multi-step work.
The primary agent performs reasoning and planning.
Subagents perform bounded execution such as observation, enumeration, normalization, or aggregation.

Prefer:

- delegation
- structured summaries
- minimal outputs

Avoid long inline diagnostic or enumeration workflows.

### Plan mode

Be extremely concise. Sacrifice grammar for brevity. Bullet points over paragraphs.

### When Delegation Is Preferred

Load a relevant skill and delegate when tasks involve:

- repeated measurements or monitoring
- large command outputs
- filesystem or process enumeration
- batch inspection
- structured data transformation

See `.claude/rules/` and `.claude/skills/` for behavior details.

## Project Structure

nixos/
├── flake.nix
├── flake.lock
├── hosts/example/
│   ├── configuration.nix
│   └── modules.nix
├── modules/
│   ├── dotfiles-manager.nix
│   ├── applications.nix
│   └── <category>/<app>/
└── script/

## Critical Rules

### Never Execute

- sudo commands
- git add, git commit, git push
- nix flake update, nix flake lock
- Privileged commands or live system activation

### Always Delegate to User

Provide exact commands for user to run:

sudo nixos-rebuild switch --flake .#<host>

The public `example` output is a build fixture without a hardware
configuration. Never suggest activating it unchanged.

### Validation (Run This Yourself)

- `./script/check.sh`
- For another root-flake output: `NIXOS_HOST_KEY=<host> ./script/check.sh`

The canonical entrypoint uses the Git worktree as flake source and refuses lockfile mutations.

### Minimal Configuration Policy

- NEVER add configuration unless explicitly requested
- ONLY add minimal package installation initially
- ASK before adding dotfiles management
- NO helpful defaults, themes, or opinionated settings

## Module Patterns

### Basic Module Template

{ config, pkgs, lib, ... }:

with lib;

let cfg = config.applications.<app>;
in {
options.applications.<app> = {
enable = mkEnableOption "<App description>";
};

config = mkIf cfg.enable {
environment.systemPackages = with pkgs; [ <app> ];
};
}

### With Dotfiles (Only When Requested)

config = mkIf cfg.enable {
environment.systemPackages = with pkgs; [ <app> ];

dotfiles = mkIf cfg.dotfiles.enable {
enable = true;
modules.<app> = {
enable = true;
sourceDir = "modules/<category>/<app>";
mappings = {
config = {
source = "settings.json";
target = "$HOME/.config/<app>/settings.json";
};
};
};
};
};

## Adding a New Application

When user requests to add an application:

1. Create modules/<category>/<app>/default.nix
2. Add to modules/<category>/default.nix imports
3. Immediately enable in `hosts/example/modules.nix` when the public fixture
   should cover it:

applications.<category>.<app>.enable = true;

4. Handle unfree packages if required.
5. Validate with:

./script/check.sh

6. Ask user to rebuild:

sudo nixos-rebuild switch --flake .#<host>

## Dotfiles System

1. Config files stored in this repo under modules/<category>/<app>/
2. Dotfiles manager validates mappings during evaluation/activation
3. Final targets symlink directly to the repo checkout
4. Applications modify symlinks, so changes appear in git immediately

## Nix Conventions

- cfg = config.applications.<app>;
- Use mkIf, mkEnableOption, mkOption
- Use $HOME paths
- Keep native config formats

## Common Commands

./script/check.sh
NIXOS_HOST_KEY=<host> ./script/check.sh

# User-run activation after validation
sudo nixos-rebuild switch --flake .#<host>

## File Management

- Use git mv for moving tracked files
- Keep configs in native formats
- Explicit file mappings

## Key Files

- flake.nix
- hosts/example/configuration.nix
- hosts/example/modules.nix
- modules/applications.nix
- modules/dotfiles-manager.nix

## Supporting Resources

### Templates

See `.claude/templates/` for module scaffolds:

- `module-basic.nix` - Minimal module
- `module-with-dotfiles.nix` - With dotfiles management
- `module-service.nix` - System service
- `module-desktop.nix` - Desktop component

### Workflows

See `.claude/workflows/` for step-by-step guides:

- `add-application.md` - Adding new applications
- `add-dotfiles.md` - Adding dotfiles management
- `debug-build-failure.md` - Debugging build errors

### Context

See `.claude/context/` for reference documentation:

- `project-structure.md` - Full project layout
- `example-module.md` - Complete module example

## External Resources

<https://nixos.org/manual/nixos/stable/>
<https://search.nixos.org/options>
<https://search.nixos.org/packages/>
<https://nixos.wiki/wiki/Flakes>

<!-- agent-memory:start -->
## Agent Memory Protocol

Global memory repo: $AGENT_MEMORY_GLOBAL_REPO
Repo memory: .agent-memory/

At task start, use recent-work-context or agent-memory recall when prior session context may matter.
For multi-step work, append durable decisions, patterns, pitfalls, and handoffs with agent-memory append.
At meaningful checkpoints, skip trivial edits, prefer append for one clear reusable insight, and use the memory-distiller subagent in proposal-only mode when recent harvest output or multiple inbox signals need compression.
At the end of meaningful sessions, run agent-memory harvest --repo "$PWD" --since 24h when allowed.
Do not run distill on a timer; run it when checkpoint value justifies the cost.
Do not store secrets. Verify memory against files before acting.
<!-- agent-memory:end -->
