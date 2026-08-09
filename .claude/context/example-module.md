# Example Module Reference

This document provides real examples from this NixOS configuration for reference.

## Fish Shell Module (Simple Application)

Location: `modules/devtools/shells/fish/default.nix`

```nix
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.applications.fish;
in
{
  options.applications.fish = {
    enable = mkEnableOption "Fish shell";

    dotfiles = {
      enable = mkOption {
        type = types.bool;
        default = cfg.enable;
        description = "Manage fish dotfiles";
      };
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ fish ];

    programs.fish.enable = true;
    users.users.alice.shell = pkgs.fish;

    dotfiles = mkIf cfg.dotfiles.enable {
      enable = true;
      modules.fish = {
        enable = true;
        sourceDir = "modules/devtools/shells/fish";
        mappings = {
          config = {
            source = "config.fish";
            target = "$HOME/.config/fish/config.fish";
          };
        };
      };
    };
  };
}
```

## Key Patterns Demonstrated

1. **Module header**: `{ config, pkgs, lib, ... }:`
2. **Library import**: `with lib;`
3. **Config reference**: `let cfg = config.applications.fish;`
4. **Enable option**: `mkEnableOption "Fish shell"`
5. **Nested options**: `dotfiles.enable`
6. **Conditional config**: `mkIf cfg.enable`
7. **Package installation**: `environment.systemPackages`
8. **System integration**: `programs.fish.enable`, `users.users.alice.shell`
9. **Dotfiles mapping**: Explicit source/target pairs
