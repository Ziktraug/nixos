# Desktop Environment Modules

This directory contains UI/desktop environment modules for NixOS.

## Available Modules

### Currently Implemented

- **GNOME** (`gnome/`) - GNOME desktop with GDM, portal integration, dconf settings, and monitor layout sync
- **Hyprland** (`hyprland/`) - Wayland compositor with NVIDIA optimizations
- **Waybar** (`waybar/`) - Status bar for Wayland compositors
- **Rofi-Wayland** (`rofi-wayland/`) - Application launcher for Wayland
- **Mako** (`mako/`) - Notification daemon for Wayland
- **Hyprpaper** (`hyprpaper/`) - Wallpaper manager for Hyprland
- **Hypridle** (`hypridle/`) - Idle management daemon for Hyprland
- **Hyprlock** (`hyprlock/`) - Screen locker for Hyprland

### Usage

Enable a desktop and any matching companion components in your host's `modules.nix`.
Do not enable GNOME and Hyprland at the same time.

```nix
applications.ui = {
  gnome.enable = true;
  hyprland.enable = false;
  waybar.enable = false;
  "rofi-wayland".enable = false;
  mako.enable = false;
  hyprpaper.enable = false;
  hypridle.enable = false;
  hyprlock.enable = false;
};
```

## GNOME Module

The GNOME module provides a complete desktop option with:

- GDM display manager
- GNOME Wayland session
- GNOME portal integration
- declarative dconf settings

### Configuration

- Module: `modules/ui/gnome/default.nix`
- Machine-specific monitor layouts are intentionally outside the public module.

## Hyprland Module

The Hyprland module provides a Wayland compositor with:

- NVIDIA environment variable optimizations
- XWayland support
- greetd display manager integration (with auto-login support)
- XDG autostart support via dex
- Additional utilities: grim, slurp, wl-clipboard, pavucontrol, brightnessctl, bibata-cursors

### Configuration

Hyprland configuration is managed via the dotfiles system:

- Source: `modules/ui/hyprland/hyprland.conf`
- Target: `~/.config/hypr/hyprland.conf`

The configuration file is writable after activation, allowing for live customization.

## Waybar Module

Installs Waybar status bar with Catppuccin Mocha theme.

### Configuration

- Config: `modules/ui/waybar/config.json` -> `~/.config/waybar/config.json`
- Style: `modules/ui/waybar/style.css` -> `~/.config/waybar/style.css`

## Rofi-Wayland Module

Provides Rofi application launcher with Wayland support and default configuration.

### Configuration

- Source: `modules/ui/rofi-wayland/config.rasi`
- Target: `~/.config/rofi/config.rasi`

## Note on Desktop Environment

The public `example` host enables **GNOME**. KDE Plasma 6 and the Hyprland stack remain in-tree but are disabled in `hosts/example/modules.nix`.
