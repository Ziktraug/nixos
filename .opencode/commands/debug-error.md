---
description: Debug a NixOS build or configuration error
agent: build
---

# Debug NixOS Error

Analyze and debug NixOS configuration errors.

## Process

1. If error message provided in `$ARGUMENTS`, parse it
2. Otherwise, run `./script/check.sh 2>&1` to capture current errors
3. Identify error type (syntax, type, undefined, collision)
4. Locate the source file and line number
5. Read the relevant file section
6. Explain the error and suggest a fix

## Debug Commands

```bash
# Capture error with trace
./script/check.sh 2>&1

# Verbose build with trace
nix build --no-link .#nixosConfigurations.example.config.system.build.toplevel --no-update-lock-file --no-write-lock-file --show-trace 2>&1

# Check specific file syntax
nix-instantiate --parse <file>
```

## Error Categories

| Type      | Indicator                     | Common Fix                   |
| --------- | ----------------------------- | ---------------------------- |
| Syntax    | "unexpected", "expected"      | Check brackets, semicolons   |
| Undefined | "undefined variable"          | Check imports, let bindings  |
| Type      | "value is a X but Y expected" | Fix option types             |
| Collision | "collision between"           | Remove duplicate definitions |

## Output Format

```
Error Type: <type>
Location: <file>:<line>
Issue: <explanation>
Fix: <specific change>
```
