---
description: Review staged NixOS configuration changes
agent: build
---

# NixOS Configuration Review

Comprehensive review for staged NixOS configuration changes.

## Instructions

You are reviewing staged changes for a NixOS modular configuration system. Focus on **staged changes** (`git diff --cached`) and ensure they align with project conventions, best practices, and validation requirements.

## Review Process

### 1. Examine Staged Changes

Run these commands to see what's being reviewed:

```bash
git diff --cached --stat
git diff --cached
```

### 2. Architecture & Pattern Compliance

Check that changes follow established patterns:

**Module Structure**

- New modules follow standard template (see `.cursor/rules/module-patterns.mdc`)
- Proper `{ config, pkgs, lib, ... }:` header
- `with lib;` and `let cfg = config.applications.<app>;` pattern
- Options defined with proper types and defaults
- Config wrapped in `mkIf cfg.enable`

**Naming Conventions** (see `.cursor/rules/nix-conventions.mdc`)

- Consistent variable names (`cfg`, descriptive names)
- Proper module paths (`applications.<app>`)
- File names follow conventions (`default.nix`, `*.json`, `*.conf`)

**Module Registration**

- New modules added to `modules/applications.nix` imports
- Enabled in appropriate `configuration.nix` or host config
- Categorized correctly (applications/services/ui/games/etc.)

**Dotfiles Management** (see `.cursor/rules/file-management.mdc`)

- Config files in native formats (no conversion)
- Mappings use proper source/target structure
- Targets use `$HOME` for user directory references
- Dotfiles only added when explicitly requested
- Follow XDG Base Directory specification where applicable

### 3. Code Quality

**Nix Language Conventions** (see `.cursor/rules/nix-conventions.mdc`)

- Consistent indentation and formatting
- Proper use of `mkIf`, `mkOption`, `mkEnableOption`
- String interpolation uses correct syntax (`${...}`)
- Lists formatted consistently
- Comments added for complex logic

**Best Practices**

- Minimal configuration approach (start small)
- No unnecessary environment variables
- No "helpful" defaults or themes unless requested
- Proper separation of concerns
- Documentation updated if needed

### 4. Project-Specific Concerns

**Configuration Policy** (see `.cursor/rules/project-overview.mdc`)

- NEVER add configuration unless explicitly requested
- ONLY add minimal package installation initially
- ASK before adding dotfiles management
- Use native config formats

**File Operations** (see `.cursor/rules/git-mv.mdc`)

- File moves use `git mv` to preserve history
- No raw `mv` commands for tracked files

### 5. Validation Requirements

**Command Delegation** (see `.cursor/rules/nixos-commands.mdc`)

- No `sudo` commands attempted
- No system-altering commands (switch, boot, update)
- Read-only validation commands only

**Required Checks**
After reviewing, run these validation commands:

```bash
# Mandatory syntax and build check
./script/check.sh

# Optional: Build system without switching
nix build --no-link .#nixosConfigurations.example.config.system.build.toplevel --no-update-lock-file --no-write-lock-file

# Optional: Dry run (read-only)
nixos-rebuild dry-run --flake .#example
```

If `./script/check.sh` passes, inform the user the changes are ready to apply.

### 6. Security & Safety

**Security Considerations**

- No sensitive data in config files
- Appropriate file permissions
- Service ports don't conflict
- Network services properly configured

**Breaking Changes**

- Document any breaking changes
- Check for dependency issues
- Verify existing modules still work

### 7. Testing Recommendations

Suggest the user test:

- Packages install correctly
- Services start without errors
- Symlinks point to correct locations
- Applications function as expected
- Configuration files are writable (if using dotfiles)

## Review Output Format

Structure your review as follows:

### Summary

Brief overview of what changed (applications, services, configs, etc.)

### Architecture Review

- Module structure compliance
- Pattern adherence
- Registration and organization

### Code Quality

- Nix conventions
- Formatting and style
- Documentation

### Issues Found

List any problems with severity (Critical/Warning/Minor):

- **Critical**: Breaks build or violates core rules
- **Warning**: Non-compliant patterns or potential issues
- **Minor**: Style inconsistencies or suggestions

### Validation Results

Output from `./script/check.sh` and any other validation commands

### Recommendations

- Required changes before merge
- Optional improvements
- Testing suggestions

### Next Steps

Clear instructions for the user, including:

- Any required fixes
- Validation commands they should run
- Final rebuild command (if checks pass)

## Critical Rules Enforcement

Throughout the review, enforce these CRITICAL rules:

1. **Never Run System Commands** - Only read-only validation
2. **Never Auto-stage Files** - All git operations delegated to user
3. **Minimal Configuration** - No config unless explicitly requested
4. **Mandatory Validation** - Always run `./script/check.sh`
5. **User Control** - User approves all system-altering commands

## Reference Documentation

For detailed guidance, refer to:

- `.cursor/rules/nixos-commands.mdc` - Command delegation policy
- `.cursor/rules/nix-conventions.mdc` - Nix language standards
- `.cursor/rules/project-overview.mdc` - Project architecture
- `.cursor/rules/module-patterns.mdc` - Module templates
- `.cursor/rules/architecture-patterns.mdc` - Development workflow
- `.cursor/rules/file-management.mdc` - Config file handling
- `.cursor/rules/git-mv.mdc` - File operation rules
- `.cursor/rules/no-git-add.mdc` - Git operation policy
