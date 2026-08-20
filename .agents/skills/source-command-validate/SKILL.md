---
name: "source-command-validate"
description: "Validate NixOS configuration with flake check"
---

# source-command-validate

Use this skill when the user asks to run the migrated source command `validate`.

## Command Template

# Validate NixOS Configuration

Run comprehensive validation on the NixOS configuration.

## Validation Steps

1. Run `./script/check.sh` to validate the entire flake
2. Report any errors found with file locations
3. If successful, confirm the configuration is ready

## Commands to Execute

```bash
./script/check.sh
```

## Expected Output

- If successful: "Configuration valid. To apply: sudo nixos-rebuild switch --flake ./hosts/nixos#nixos"
- If failed: Parse error, show location and suggested fix

## Critical Rules

- NEVER run `sudo` commands
- NEVER run `nixos-rebuild switch`
- ONLY run read-only validation commands
