# Workflow: Debug Build Failure

## Overview

Steps to diagnose and fix NixOS build failures.

## Step 1: Capture Error

```bash
./script/check.sh 2>&1
```

Or for more detail:

```bash
nix build --no-link .#nixosConfigurations.example.config.system.build.toplevel --no-update-lock-file --no-write-lock-file --show-trace 2>&1
```

## Step 2: Identify Error Type

### Syntax Errors

**Indicators**: "unexpected", "expected", "syntax error"

**Example**:
```
error: syntax error, unexpected ';', expecting '}'
       at /path/to/file.nix:42:10
```

**Fix**: Check brackets, semicolons, string quotes at indicated line.

### Undefined Variable

**Indicators**: "undefined variable"

**Example**:
```
error: undefined variable 'cfg'
       at /path/to/file.nix:15:5
```

**Fix**: Add `let cfg = config.applications.<app>;` before usage.

### Type Errors

**Indicators**: "value is a X but a Y was expected"

**Example**:
```
error: value is a string but a integer was expected
```

**Fix**: Check option type definitions match provided values.

### Module Collision

**Indicators**: "collision between"

**Example**:
```
error: collision between paths
```

**Fix**: Remove duplicate definitions or use `mkForce`.

## Step 3: Locate Source

From error message:
- File: `/path/to/file.nix`
- Line: `42`
- Column: `10`

Read the file around that location.

## Step 4: Apply Fix

Make minimal change to fix the specific error.

## Step 5: Validate Fix

```bash
./script/check.sh
```

Repeat until no errors.

## Step 6: Inform User

Once validation passes:
```
Configuration valid. To apply:
sudo nixos-rebuild switch --flake .#<host>
```
