---
description: Validate NixOS configuration with flake check
allowed-tools: Bash(nix:*)
---

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

- If successful: "Configuration valid. Adapt the example before activating a real host."
- If failed: Parse error, show location and suggested fix

## Critical Rules

- NEVER run `sudo` commands
- NEVER run `nixos-rebuild switch`
- ONLY run read-only validation commands
