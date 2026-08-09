---
description: Create a new NixOS application module
agent: build
---

# Add New Application Module

Create a new NixOS application module following project conventions.

## Arguments

- `$1` - Application name (required)
- `$2` - Category: browsers, devtools, games, hardware, media, services, ui (optional, default: devtools)

## Process

1. Check if module already exists at `modules/$2/$1/default.nix`
2. Create module directory: `modules/$2/$1/`
3. Create `default.nix` using basic template
4. Add import to category's `default.nix` or `applications.nix`
5. Run `./script/check.sh` to validate
6. Inform user to enable in their host config

## Template Location

Use template from `.claude/templates/module-basic.nix`

## Module Structure

```
modules/<category>/<app>/
└── default.nix
```

## Critical Rules

- Start with MINIMAL package installation only
- Do NOT add dotfiles unless explicitly requested
- Do NOT add "helpful" defaults or themes
- ALWAYS run `./script/check.sh` after creation
- DELEGATE rebuild to user
