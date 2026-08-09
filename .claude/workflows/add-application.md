# Workflow: Add New Application

## Overview

Steps to add a new application to the NixOS configuration.

## Prerequisites

- Application name (e.g., `kitty`, `btop`)
- Category (browsers, devtools, games, hardware, media, services, ui)
- Package name in nixpkgs (search: `nix search nixpkgs <app>`)

## Steps

### 1. Search for Package

```bash
nix search nixpkgs <app-name>
```

Verify the package exists and note the exact attribute name.

### 2. Create Module Directory

```bash
mkdir -p modules/<category>/<app>
```

### 3. Create Module File

Create `modules/<category>/<app>/default.nix`:

```nix
{ config, pkgs, lib, ... }:

with lib;

let cfg = config.applications.<app>;
in {
  options.applications.<app> = {
    enable = mkEnableOption "<App description>";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ <package> ];
  };
}
```

### 4. Register Module

Add to `modules/<category>/default.nix`:

```nix
imports = [
  # ... existing imports
  ./<app>
];
```

Or if category doesn't have aggregator, add to `modules/applications.nix`.

### 5. Validate

```bash
./script/check.sh
```

### 6. Enable Module

Add to `hosts/example/modules.nix` when the public fixture should cover it:

```nix
applications.<app>.enable = true;
```

### 7. Rebuild (User Action)

```bash
sudo nixos-rebuild switch --flake .#<host>
```

## Notes

- Start with minimal config (package only)
- Add dotfiles only when requested
- Run validation after every change
