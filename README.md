# Modular NixOS configuration

A self-contained Nix flake that exports reusable NixOS modules and a fictitious
`example` configuration. The repository combines package installation with
configuration-file management through explicit mappings and symlinks.

## Philosophy

- **Collocated** package installation and configuration in the same module
- **Explicit mappings** instead of directory mirroring
- **Native file formats** (no conversion)
- **Writable configs** via symlinks so applications can update their own files
- **Flat structure** avoiding deep nested directories

## Directory Structure

```
nixos/
├── flake.nix                      # Public inputs, outputs, checks, and formatter
├── flake.lock                     # Locked public dependencies
├── hosts/
│   └── example/
│       ├── configuration.nix      # Fictitious, buildable host
│       └── modules.nix            # Representative module selection
├── modules/                       # Reusable modules (no private host data)
│   ├── dotfiles-manager.nix       # Core dotfiles system
│   ├── unfree-packages.nix        # Per-module unfree package management
│   ├── validation.nix             # System validation checks
│   ├── applications.nix           # Module index
│   ├── browsers/                  # Web browsers
│   │   ├── brave/
│   │   ├── firefox/
│   │   └── zen-browser/
│   ├── devtools/                  # Development tools
│   │   ├── git/
│   │   ├── nix-dev/
│   │   ├── ide/                   # IDEs and editors
│   │   │   ├── cursor/
│   │   │   └── zed/
│   │   ├── shells/                # Shell environments
│   │   │   ├── fish/
│   │   │   └── direnv/
│   │   └── terminals/             # Terminal emulators
│   │       └── ghostty/
│   ├── games/                     # Gaming applications
│   │   ├── gamemode/
│   │   ├── heroic/
│   │   ├── mangohud/
│   │   └── steam/
│   ├── hardware/                  # Hardware-specific tools
│   │   └── solaar/
│   ├── media/                     # Media applications
│   │   ├── guitar/
│   │   └── vlc/
│   ├── services/                  # System services
│   │   └── networking/
│   │       ├── adguardhome/
│   │       └── unbound/
│   └── ui/                        # User interface components
│       ├── hyprland/
│       ├── rofi-wayland/
│       └── waybar/
├── script/
│   └── check.sh                   # Canonical public/private validation entrypoint
└── tests/                         # Evaluation, source, and operational checks
```

The example deliberately has no disk layout, hardware identifiers, personal
identity, or machine-specific monitor configuration. It is an evaluation and
build fixture, not an install image.

## Flake outputs

The root flake provides:

- `nixosModules.default`, which imports the shared unfree-package, validation,
  primary-user, dotfiles-manager, and application modules;
- `nixosConfigurations.example`, a representative `x86_64-linux` system;
- `checks.x86_64-linux`, the repository validation suite;
- `packages.x86_64-linux.gitleaks`, the scanner used by publication gates;
- `formatter.x86_64-linux`, the pinned Nix formatter.

Downstream flakes can import the shared module without copying the repository:

```nix
{
  inputs.nixos-config.url = "github:OWNER/nixos";

  outputs = { nixpkgs, nixos-config, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixos-config.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
```

## How It Works

### Application Module Structure

Each application module contains:
- `default.nix` - Package installation and file mappings
- Configuration files in their native formats

### Inline Mappings

Mappings are explicitly defined in the module:

```nix
sourceDir = "modules/<category>/<app>";
mappings = {
  settings = {
    source = "settings.json";                   # File under sourceDir
    target = "$HOME/.config/app/settings.json"; # Final symlink destination
  };
};
```

### Symlink System

The dotfiles manager creates symlinks from files in this repo checkout to target locations under the configured user's home. A systemd user service performs all home-directory writes as that user. Applications write to symlinks normally, so changes appear in git immediately and do not require a rebuild.

```text
~/.config/zed/settings.json -> /srv/alice/nixos/modules/devtools/ide/zed/settings.json
```

Rebuilds validate the mappings and refresh the user service that repairs symlinks. If the checkout is unavailable, the user service fails visibly without making system activation write into the home directory. It never copies user dotfiles through `~/dotfiles`.

Mappings can still use `copyTo` for explicit privileged copies, such as copying a monitor layout to `/etc/xdg/monitors.xml` during activation. Those copies use the immutable source captured in the Nix store, not the mutable checkout.

When an existing target differs, it is moved to `~/.dotfiles-backups/` under a unique path containing the module, mapping, and home-relative target. The activation output prints the exact source, target, backup, and a shell-safe diff command. Identical files are relinked without creating unnecessary backups, and symlinked parent directories are rejected.

## Usage

From a public checkout, run the canonical validation entrypoint:

```bash
./script/check.sh
```

When no private host flake exists, the script checks the root flake and builds
`nixosConfigurations.example`. It passes both lock-protection flags, so routine
validation never updates or writes a lockfile.

For an explicit root-flake check, use:

```bash
NIXOS_HOST_KEY=example NIXOS_CHECK_FLAKE_REF="git+file:$PWD" ./script/check.sh
```

### Adding an Application

1. Create `modules/<category>/<app>/default.nix`:

```nix
{ config, pkgs, lib, ... }:
with lib;
let cfg = config.applications.<app>;
in {
  options.applications.<app> = {
    enable = mkEnableOption "<app>";
    dotfiles.enable = mkOption {
      type = types.bool;
      default = cfg.enable;
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ <app> ];

    dotfiles = mkIf cfg.dotfiles.enable {
      enable = true;
      modules.<app> = {
        enable = true;
        sourceDir = "modules/<category>/<app>";
        mappings = {
          config = {
            source = "config.conf";
            target = "$HOME/.config/<app>/config.conf";
          };
        };
      };
    };
  };
}
```

2. Add config files in native formats
3. Register in `modules/<category>/default.nix`
4. Enable it in `hosts/example/modules.nix` while developing the public fixture:

```nix
applications.<app>.enable = true;
```

## Adapting the example

Fork the repository before turning the example into a real host:

1. Copy `hosts/example/` to a new host directory.
2. Add the generated hardware configuration and host-specific settings only in
   that fork.
3. Add the new configuration to `nixosConfigurations` in the root `flake.nix`;
   do not create a separate per-host flake.
4. Keep `hosts/example` fictitious so public checks continue to exercise a
   portable fixture.
5. Run `NIXOS_HOST_KEY=<host> ./script/check.sh` before any user-controlled
   activation with `sudo nixos-rebuild switch --flake .#<host>`.

## Canonical and public repositories

The maintained system configuration lives in a canonical private repository.
Machine- and identity-specific material stays below its excluded `private/`
boundary. A deterministic export of a committed canonical revision produces
this public snapshot; the snapshot never imports from that boundary and remains
independently evaluable.

Contributions should target reusable modules, the fictitious example, tests, or
public documentation. Private host operation and publication credentials are
documented only in the canonical repository's excluded subtree.

Every committed canonical revision can be checked without copying files:

```bash
./script/export-public.sh --check-only
```

Publication into an existing, clean Git checkout is explicit. The exporter
validates both repositories, builds an exact `git archive`, runs the privacy and
Gitleaks checks before and after copying, and preserves the target `.git`
metadata:

```bash
./script/export-public.sh --target "$PUBLIC_CHECKOUT" --revision HEAD
```

The target must be the canonical root of a clean Git worktree. The exporter
refuses unresolved, symlinked, overlapping, non-Git, or filesystem-root targets.

## Future: Host-Specific Config Overlays

No host-overlay API exists yet. Add one only after a real second host needs to
override a shared dotfile; until then, keep host-specific values in that host's
`configuration.nix` or `modules.nix`.

If that API is introduced, the dotfiles manager should continue linking
directly to one editable repository file. Host-specific selection must resolve
to a concrete source before symlink creation rather than copying mutable user
dotfiles through an intermediate directory.

This avoids introducing home-manager (which takes ownership of dotfiles) while still supporting per-host customization when needed.

## Documentation

Additional documentation can be found in the `docs/` directory:
- [Git SSH Configuration](docs/git-ssh-configuration.md) - SSH key setup for per-directory Git configs
- [Troubleshooting Guide](docs/troubleshooting.md) - Common issues and solutions

## Related Documentation

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Nix Flakes](https://nixos.wiki/wiki/Flakes)
- [Nixos options](https://search.nixos.org/options)
- [Nixos packages](https://search.nixos.org/packages?)

## License

This repository is available under the [MIT License](LICENSE).
