# Archived Dotfiles Architecture Plan

> Implemented before and during the remediation worktree based on `2c0926c`, then reconciled on
> 2026-07-13. This is a design record, not an active checklist. Skill and
> agent-rule lifecycle work remains owned by the adjacent tooling project.

## Goal

Make dotfiles directly editable from the repo checkout without rebuilding after every config edit.

Target model:

```text
modules/<area>/<app>/<file> -> final target under $HOME
```

Example:

```text
~/.config/zed/settings.json -> /srv/alice/nixos/modules/devtools/ide/zed/settings.json
```

## Decisions

- Repo checkout is the source of truth for managed dotfiles.
- `~/dotfiles` should no longer be part of the main dotfiles flow.
- Dotfile mappings stay colocated with their owning NixOS Module.
- `sourceDir` is a repo-relative Module directory, not `toString ./.`.
- Rebuild/activation should set up and repair symlinks, not copy user dotfiles.
- System destinations such as `/etc/xdg/monitors.xml` remain explicit copies, not user dotfile symlinks.
- This repo targets one Primary User per host, not full multi-user support.
- KDE and Hyprland remain dormant Active UI Session Adapters for possible future reswitch.
- Pinned release metadata stays colocated in each Module; repeated update implementation is shared.

## Implementation Checklist

### Stable Step 1: Direct Repo Symlinks

- [x] Change dotfiles activation from `repo -> ~/dotfiles -> target` to `repo -> target`.
- [x] Interpret `dotfiles.modules.<name>.sourceDir` as repo-relative.
- [x] Replace all `modulePath = toString ./.;` usages with repo-relative `sourceDir` paths.
- [x] Keep backup handling for existing non-symlink targets.
- [x] Remove symlink replacement when the target already points to the expected repo source.
- [x] Keep `copyTo` as an explicit privileged copy from an immutable store source.
- [x] Run `./script/check.sh`.

Stable checkpoint result:

- `modules/dotfiles-manager.nix` now links targets directly to files under `${dotfiles.repoPath}`.
- `~/dotfiles` is no longer created or chowned by the dotfiles activation script.
- Existing non-symlink targets are still backed up before replacement.
- `copyTo` remains an explicit immutable-source copy for system destinations such as
  `/etc/xdg/monitors.xml`.
- `modules/lib/types.nix` now exposes `sourceDir` as a repo-relative path.
- Validation passed with `./script/check.sh`.

Commit note:

- Repo rules forbid the agent from running `git add`/`git commit` automatically, even though this is a stable checkpoint.
- Suggested commit after review: `git add ARCHITECTURE_DOTFILES_PLAN.md modules && git commit -m "Deepen dotfiles manager with direct repo symlinks"`.

### Stable Step 2: Stronger Validation

- [x] Tighten target validation so a similarly prefixed username cannot match the configured home.
- [x] Assert every enabled mapping source exists in the flake source.
- [x] Detect duplicate final targets across enabled mappings.
- [x] Make executable intent explicit in mappings and validate it during activation.
- [x] Run `./script/check.sh`.

Stable checkpoint result:

- Target validation now requires exact `$HOME` or `$HOME/` prefix after expansion.
- Source existence is checked against the flake source because `dotfiles.repoPath` points at the mutable checkout and is not reliable for pure eval.
- Runtime symlinks still point at `${dotfiles.repoPath}` so files remain editable from the IDE.
- Duplicate final targets fail evaluation before activation.
- Executable mappings declare `executable = true`; the user activation verifies the checkout bit.
- Validation passed with `./script/check.sh`.

### Stable Step 3: Documentation Cleanup

- [x] Update `README.md` dotfiles flow.
- [x] Update agent-facing dotfiles docs/skills if needed.
- [x] Update the project task log to close or rewrite obsolete dotfiles items.
- [x] Document migration notes for existing `~/dotfiles` files.

Migration notes:

- Existing files under `~/dotfiles` are no longer used by activation.
- Do not delete `~/dotfiles` until after the first successful rebuild and manual review for uncommitted edits.
- If a file in `~/dotfiles/<module>/<source>` contains changes that are not in `modules/...`, copy those changes into the matching repo file before rebuilding.
- After rebuild, verify important targets with `readlink -f <target>` and confirm they point under `${dotfiles.repoPath}`.
- Zen Browser setup and rebuild recap now read managed sources from the repo checkout instead of `~/dotfiles`.

### Stable Step 4: Follow-Up Architecture

- [x] Centralize Primary User facts for mono-user host usage in `modules/primary-user.nix`.
- [x] Expand evaluation coverage with cross-module fixtures and assertions in `tests/checks.nix`.
- [x] Keep KDE/Hyprland as dormant Active UI Session Adapters.
- [x] Factor pinned release update implementation while keeping pins colocated.

A separate `CONTEXT.md` was deliberately not introduced: the current domain vocabulary is already
small and documented in this record and `README.md`; another active document would duplicate it.

## Validation Commands

Run after every Nix edit:

```bash
./script/check.sh
```

Optional deeper read-only checks:

```bash
nix build --no-link .#nixosConfigurations.example.config.system.build.toplevel --no-update-lock-file --no-write-lock-file
nixos-rebuild dry-run --flake .#example
```

Actual system switch remains user-controlled:

```bash
sudo nixos-rebuild switch --flake .#<host>
```

## Commit Notes

Repository rules forbid agents from running `git add`, `git commit`, or `git push` automatically.

At each stable point, review and commit manually with commands like:

```bash
git status
git diff
git add ARCHITECTURE_DOTFILES_PLAN.md modules/dotfiles-manager.nix modules/lib/types.nix modules
git commit -m "Deepen dotfiles manager with direct repo symlinks"
```
