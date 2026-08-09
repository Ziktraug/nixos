---
name: dotfiles-management
description: Manage dotfiles, file mappings, and symlink configurations. Use when handling config files, creating mappings, or troubleshooting symlinks.
allowed-tools: Read, Edit, Write, Glob, Grep, Bash(ls:*), Bash(tree:*)
---

# Dotfiles Management Skill

## Quick Reference

### System Flow
1. Config files live in this repo under `modules/<category>/<app>/`
2. Activation validates mappings and creates target parent directories
3. Final targets symlink directly to the repo checkout
4. Applications modify symlinks -> changes appear in git immediately

### Basic Mapping
```nix
dotfiles = mkIf cfg.dotfiles.enable {
  enable = true;
  modules.<app> = {
    enable = true;
    sourceDir = "modules/<category>/<app>";
    mappings = {
      config = {
        source = "settings.json";
        target = "$HOME/.config/<app>/settings.json";
      };
    };
  };
};
```

### Target Path Patterns

| Type | Pattern |
|------|---------|
| XDG Config | `$HOME/.config/<app>/` |
| XDG Data | `$HOME/.local/share/<app>/` |
| Legacy | `$HOME/.<file>` |
| Project | `$HOME/Projects/<ctx>/.gitconfig` |

## Multiple File Mappings

```nix
mappings = {
  config = {
    source = "config.json";
    target = "$HOME/.config/app/config.json";
  };
  theme = {
    source = "theme.css";
    target = "$HOME/.config/app/theme.css";
  };
  keybinds = {
    source = "keybindings.json";
    target = "$HOME/.config/app/keybindings.json";
  };
};
```

## Diagnostic Commands

```bash
# Check symlinks
ls -la ~/.config/<app>/

# Find broken symlinks
find ~/.config -xtype l

# Check symlink destination
readlink -f ~/.config/<app>/<file>
```

## Troubleshooting

| Issue | Check |
|-------|-------|
| Symlink not created | Is `dotfiles.enable = true`? |
| Wrong content | Verify source path |
| Permission denied | Check target directory exists |
| File not updating | Check target points to repo checkout, not Nix store |

## Critical Rules

1. **ONLY** add dotfiles when explicitly requested
2. Use **native formats** (JSON, TOML, conf)
3. Always use **`$HOME`**, not a user-specific absolute home path
4. **Validate** with `./script/check.sh`
