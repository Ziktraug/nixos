# Scripts

This directory contains maintenance and utility scripts for the NixOS system.

## Environment Variable

All aliases use the `$NIXOS_REPO` environment variable, which is automatically set by the dotfiles-manager based on your host configuration. This makes the scripts portable across different installations.

## Available Scripts

### `check.sh`

**Canonical local and CI validation**

Runs every host flake check and builds the complete system closure without creating a `result`
symlink. It uses a path flake so new worktree files are included before staging.

```bash
./script/check.sh
```

---

### `maintenance.sh`

**Explicit diagnostic and maintenance modes with safety guardrails**

The maintenance script provides an interactive menu with two categories of operations:

#### Read-only diagnostics (no sudo, no state changes)

- Run health checks
- Check root and EFI partition usage

#### State-changing modes (require an explicit mode and confirmation)

- `--cleanup`: remove announced user build/cache paths and optimize the Nix store
- `--system-cleanup`: garbage collect old generations and journal logs with `sudo`
- `--update`: update the active host flake inputs

**Usage:**

```bash
# Interactive menu
maintenance

# Genuinely read-only, non-interactive diagnostics
maintenance --diagnose

# Explicit state-changing operation, with confirmation
maintenance --cleanup

# The same explicit operation with its confirmation answered automatically
maintenance --cleanup --yes
```

**Menu Options:**

1. Read-only diagnostics
2. User cleanup
3. Privileged system cleanup
4. Flake update

---

### `disk-health-check.sh`

**Quick disk health monitoring**

Checks:

- SMART health status for all disks (HDD + NVMe SSDs)
- Critical SMART attributes (reallocated sectors, pending sectors, etc.)
- Mounted filesystems and their UUID-backed device resolution
- SMART status for the physical disks backing those mount points
- A reminder that NTFS dirty-state inspection/repair must happen while unmounted

**Usage:**

```bash
disk-health
```

**Exit codes:**

- `0` - All checks passed
- `1` - Issues detected (check output for details)

---

### `verify-git-ssh.sh`

**Verify Git SSH configuration**

Checks:

- SSH key files exist with correct permissions (600 for private, 644 for public)
- SSH connection to GitHub works with the configured keys
- Git configuration is correctly applied in work directories
- Per-directory email and SSH key settings

**Usage:**

```bash
$NIXOS_REPO/script/verify-git-ssh.sh
```

**See also:** [Git SSH Configuration Guide](../docs/git-ssh-configuration.md)

---

### `rebase-on-default.sh`

**Rebase current branch on remote default branch**

Git workflow helper that:

- Stashes uncommitted changes
- Fetches latest from origin
- Rebases current branch on `origin/<default-branch>` (for example `origin/main`)
- Restores stashed changes

**Usage:**

```bash
rebase
```

---

### `rebuild.sh`

**Install safely, preview live activation, and recap changes**

The default two-stage workflow:

1. Runs `nixos-rebuild boot`, so the generation is fully built and installed without
   restarting the current desktop or network stack.
2. Previews live activation with that exact generation. If GNOME, D-Bus, login, display,
   or NetworkManager services are affected, it prints a high-risk warning and defaults to
   deferring activation until reboot. Otherwise, live activation defaults to yes.

No second build is performed when live activation is accepted. The script then prints:

- Package changes with before/after closure diff
- Managed dotfile targets created or repaired during activation, detected from their real
  file/symlink state and an internal content/link fingerprint
- Whether the generation is installed, active now, or waiting for reboot

**Usage:**

```bash
rebuild
rebuild --activation-policy boot
rebuild --activation-policy switch
```

`--no-prompts` leaves the installed generation for reboot unless `switch` is explicitly selected.

---

## Shell Aliases

These scripts are available via shell aliases defined in `modules/devtools/shells/aliases/aliases`.

All aliases use the `$NIXOS_REPO` environment variable for portability.

| Alias | Description |
|-------|-------------|
| `disk-health` | Check disk health (quick) |
| `maintenance` | Interactive system maintenance |
| `rebase` | Rebase current branch on remote default branch |
| `rebuild` | Rebuild NixOS + recap (packages/dotfiles) |
| `update` | Run pre-update hooks, then update flake inputs |

## Recommended Schedule

- **Daily**: Automatic monitoring via `smartd` (no action needed)
- **Weekly**: Run `disk-health` to check system health
- **Monthly**: Run `maintenance` (option 2) for full cleanup
- **After unexpected shutdown**: Run `disk-health` to check for issues

## Safety Notes

- The `maintenance` script asks for confirmation before any state-changing operation
- `--yes` only confirms an explicitly selected mode; it never selects extra work
- Garbage collection keeps recent generations for rollback capability
- `update` runs module pre-update hooks before host flake update (`hosts/<hostname>/flake.nix`)
- `update` then proposes next actions (default yes): manual stage command for `hosts/<hostname>/flake.lock` + updated `modules/**/release.json`, then runs `rebuild`
- Flake updates modify host `flake.lock`; remember to rebuild and test afterward

## Related Documentation

- [Disk Health Monitoring Guide](../docs/disk-health-monitoring.md)
- [Troubleshooting Guide](../docs/troubleshooting.md)

## Playwright browser management

The `playwright-cli` wrapper packages a fixed `@playwright/cli` release and its exact Playwright
dependencies with Nix fetch hashes, and uses the system Google Chrome. It performs no package
download at runtime.
If a project needs Playwright-managed browser binaries instead, install them explicitly for that
project; that separate download is not performed by the system wrapper.
