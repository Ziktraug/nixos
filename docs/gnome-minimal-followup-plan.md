# GNOME TODO

## Current State

- GNOME is now the active desktop on this host
- GDM is the active display manager
- GNOME Wayland session is the target path
- `gnome-keyring` is enabled for secrets integration
- GNOME portal is the active portal stack
- KDE and Hyprland are disabled in host toggles but kept in-tree for now

This document is no longer a migration plan for first login.
The migration is considered stable enough to move into cleanup and next-step work.

## Immediate Follow-Up

- [ ] Rebuild and confirm GDM picks up monitor layout from `/etc/xdg/monitors.xml`
- [ ] Confirm greeter monitor order, rotation, refresh rate, and primary display are correct
- [ ] Confirm the cursor fix still works in both GDM and the logged-in GNOME session
- [ ] If the greeter still shows the wrong cursor, add dedicated GDM-side dconf cursor settings instead of relying only on the user profile

## GNOME Module Cleanup

- [x] Move GNOME into `modules/ui/gnome/default.nix`
- [x] Keep `modules/ui/default.nix` as the UI aggregator/import file only
- [x] Remove stale active-path assumptions about KDE and the first-login migration

## Settings Cleanup

- [ ] Review the GNOME dconf block and separate required settings from preference settings
- [ ] Keep the cursor settings that prevent the broken box cursor
- [ ] Reassess whether these should remain enforced system-wide:
  - `gtk-theme`
  - `icon-theme`
  - `color-scheme`
  - dconf locks on those keys
- [ ] Decide whether appindicator extension enablement belongs in the GNOME module or should move closer to the ProtonVPN module

## Desktop Stack Cleanup

- [x] Remove stale KDE-oriented docs/comments in active paths
- [ ] Decide whether KDE remains as a dormant fallback or should be removed later
- [ ] Decide whether Hyprland modules remain in-tree or move to a later cleanup pass
- [x] Remove the obsolete KDE-coupled `wifi-reconnect` module

## Validation Checklist

After each Nix edit, run from the repository root:

```bash
./script/check.sh
nix build --no-link .#nixosConfigurations.example.config.system.build.toplevel --no-update-lock-file --no-write-lock-file
nixos-rebuild dry-run --flake .#example
```

After the actual rebuild, verify:

- [ ] GDM starts reliably
- [ ] GNOME logs in successfully
- [ ] `echo $XDG_SESSION_TYPE` returns `wayland`
- [ ] the greeter uses the intended monitor layout
- [ ] the cursor is correct in GDM and inside the session
- [ ] no Waybar appears
- [ ] Nautilus mounts, trash, and network-backed locations work
- [ ] browsers can access saved secrets through `libsecret`
- [ ] `systemctl --user status xdg-desktop-portal xdg-desktop-portal-gnome` is healthy
- [ ] browser screen sharing works
- [ ] printing still works
- [ ] PipeWire audio works
- [ ] suspend, resume, lock, and unlock all work
- [ ] common X11 apps still run correctly through Xwayland

## Suggested Order

1. Confirm the `monitors.xml` fix after rebuild
2. Verify cursor behavior in GDM and the GNOME session
3. Trim or relocate non-essential GNOME settings only after the above is confirmed
4. Review which GNOME preferences should remain system-enforced
5. Do broader KDE/Hyprland cleanup only after the active GNOME path is tidy
