# Workflow: Add Dotfiles to Module

## Overview

Steps to add dotfiles management to an existing module.

## Prerequisites

- Existing module at `modules/<category>/<app>/default.nix`
- Config file(s) to manage
- Target path(s) for the config file(s)

## Step 1: Add Config Files to Module

Place configuration files in the module directory:

```
modules/<category>/<app>/
├── default.nix
├── config.json       # Your config file
└── other-config.toml # Additional configs
```

## Step 2: Add Dotfiles Option

In `default.nix`, add to options:

```nix
options.applications.<app> = {
  enable = mkEnableOption "<App description>";

  dotfiles = {
    enable = mkOption {
      type = types.bool;
      default = cfg.enable;
      description = "Manage <app> dotfiles";
    };
  };
};
```

## Step 3: Add Dotfiles Configuration

In `default.nix`, add to config:

```nix
config = mkIf cfg.enable {
  # Existing package installation
  environment.systemPackages = with pkgs; [ <app> ];

  # Dotfiles management
  dotfiles = mkIf cfg.dotfiles.enable {
    enable = true;
    modules.<app> = {
      enable = true;
      sourceDir = "modules/<category>/<app>";
      mappings = {
        config = {
          source = "config.json";
          target = "$HOME/.config/<app>/config.json";
        };
        # Add more mappings as needed
      };
    };
  };
};
```

## Step 4: Validate

```bash
./script/check.sh
```

## Step 5: Rebuild (User Action)

```bash
sudo nixos-rebuild switch --flake .#<host>
```

## Result

After rebuild:
1. Source validated: `modules/<category>/<app>/config.json`
2. Symlink created: `~/.config/<app>/config.json` -> `<repo>/modules/<category>/<app>/config.json`
3. Application can modify config through symlink, and changes appear in git immediately

## Common Target Paths

| Type | Path Pattern |
|------|--------------|
| XDG Config | `$HOME/.config/<app>/` |
| XDG Data | `$HOME/.local/share/<app>/` |
| Legacy Dotfile | `$HOME/.<app>rc` |
