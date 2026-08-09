# Project Structure Reference

## Directory Layout

```
nixos/
├── flake.nix                    # Public inputs, outputs, checks, formatter
├── flake.lock                   # Locked public dependencies
├── hosts/
│   └── example/                 # Fictitious public build fixture
│       ├── configuration.nix    # Generic user and host configuration
│       └── modules.nix          # Representative module selection
└── modules/
    ├── applications.nix         # Module registry (all imports)
    ├── dotfiles-manager.nix     # Dotfiles infrastructure
    ├── browsers/                # Browser applications
    │   ├── default.nix          # Category index
    │   ├── brave/
    │   ├── firefox/
    │   └── zen/
    ├── devtools/                # Development tools
    │   ├── default.nix
    │   ├── git/
    │   ├── ide/                 # IDEs (cursor, zed)
    │   ├── shells/              # Shells (fish, nushell)
    │   └── terminals/           # Terminal emulators
    ├── games/                   # Gaming applications
    │   ├── default.nix
    │   ├── steam/
    │   ├── heroic/
    │   └── gamemode/
    ├── hardware/                # Hardware-specific tools
    │   ├── default.nix
    │   └── solaar/
    ├── media/                   # Media applications
    │   ├── default.nix
    │   ├── vlc/
    │   └── guitar/
    ├── services/                # System services
    │   ├── default.nix
    │   └── networking/          # Network services
    └── ui/                      # Desktop environment
        ├── default.nix
        ├── hyprland/
        ├── waybar/
        ├── rofi/
        └── mako/
```

## Key Files

| File | Purpose |
|------|---------|
| `flake.nix` | Root inputs/outputs, `nixosModules.default`, example, checks |
| `hosts/example/configuration.nix` | Fictitious public host configuration |
| `hosts/example/modules.nix` | Representative public module selection |
| `modules/applications.nix` | Import all module categories |
| `modules/dotfiles-manager.nix` | Dotfiles infrastructure |

## Module Registration Flow

1. Create module: `modules/<category>/<app>/default.nix`
2. Add to category: `modules/<category>/default.nix`
3. Category in registry: `modules/applications.nix`
4. Enable in the public fixture when relevant: `hosts/example/modules.nix`
