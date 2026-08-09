---
name: nix-modules
description: Create, modify, and manage NixOS modules. Use when working with .nix files, adding applications, or configuring system modules.
allowed-tools: Read, Edit, Write, Glob, Grep, Bash(nix:*)
---

# NixOS Module Development Skill

## Quick Reference

### Standard Module Template
```nix
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
```

### Key Patterns
- Always use `with lib;` at module start
- Define `cfg = config.applications.<app>;` in let binding
- Wrap config in `mkIf cfg.enable`
- Use `mkEnableOption` for boolean toggles
- Use `mkOption` with proper types for other options

### Module Registration
1. Create: `modules/<category>/<app>/default.nix`
2. Import in: `modules/applications.nix`
3. Enable in the public fixture when relevant: `hosts/example/modules.nix`

### Validation
```bash
./script/check.sh  # Required after every change
```

## Common Types

| Type | Usage |
|------|-------|
| `types.bool` | Boolean values |
| `types.str` | Strings |
| `types.int` | Integers |
| `types.port` | Port numbers (1-65535) |
| `types.listOf types.str` | List of strings |
| `types.attrs` | Attribute sets |

## Option Patterns

```nix
# Simple enable
enable = mkEnableOption "Application name";

# String with default
theme = mkOption {
  type = types.str;
  default = "dark";
  description = "Color theme";
};

# Port number
port = mkOption {
  type = types.port;
  default = 8080;
  description = "Service port";
};

# Nested options
dotfiles.enable = mkOption {
  type = types.bool;
  default = cfg.enable;
  description = "Manage dotfiles";
};
```

## Progressive Disclosure

For detailed patterns, see:
- [Module Patterns](.cursor/rules/module-patterns.mdc)
- [Nix Conventions](.cursor/rules/nix-conventions.mdc)

## Post-Edit Validation

CRITICAL: After editing ANY `.nix` file, you MUST:

1. Immediately run `./script/check.sh` to validate
2. Report any errors found
3. Only proceed after validation passes

This replaces Claude Code's hook-based validation for cross-tool compatibility.

## Critical Rules

1. **NEVER** add config unless requested
2. **ONLY** add minimal package installation initially
3. **ALWAYS** run `./script/check.sh` after changes
4. **DELEGATE** rebuild commands to user
