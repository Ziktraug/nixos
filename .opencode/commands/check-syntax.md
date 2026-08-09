---
description: Check syntax of a specific Nix file
agent: build
---

# Check Nix File Syntax

Quickly validate syntax of a single Nix file without full flake evaluation.

## Arguments

- `$1` - Path to .nix file (required)

## Command

```bash
nix-instantiate --parse $1
```

## Output

- Success: No output (file is syntactically valid)
- Failure: Error message with line/column information

## Usage Examples

```
/check-syntax modules/ui/waybar/default.nix
/check-syntax flake.nix
```

## Notes

- This only checks syntax, not semantic correctness
- For full validation, use `/validate` or `./script/check.sh`
