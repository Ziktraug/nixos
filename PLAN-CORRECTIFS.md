# Archived remediation plan

> Initial audit baseline: commit `21abe0b` (2026-07-09).
> Reconciled against commit `2c0926c` and the uncommitted remediation worktree on 2026-07-13.

This file is an archive, not an active roadmap. Current reusable work belongs in
the public issue tracker. The repository now exposes one root flake and keeps
`hosts/example/` as its portable validation fixture.

## Reconciliation

| ID | Status | Result |
|---|---|---|
| D01 | Done | Dotfile backups are collision-safe and covered by isolated activation tests. |
| B01 | Done | The Windows EFI copy uses a private mount point, owns its cleanup, and has stubbed tests. |
| O01 | Done | Maintenance separates read-only diagnostics from explicit state-changing cleanup. |
| O02 | Done | Disk diagnostics resolve mounted devices and no longer infer NTFS state from `force`. |
| R02 | Done | Playwright CLI is pinned and its wrapper is checked for runtime `npm`/`@latest`. |
| T01 | Done | Dotfile user/system activation has a Nix-backed fixture suite. |
| D02 | Done | Home mutations run in the user phase; privileged `copyTo` uses immutable store sources. |
| F01 | Superseded | The publication migration replaced per-host flakes with the root public flake and `nixosConfigurations.example`. |
| V01 | Done | Cross-module evaluation, operational script, service, updater, and source-quality checks are exposed by the root flake. |
| A01 | Done | Every optional dotfile interface now uses `dotfiles.enable`; former boolean and nested styles are covered by enabled/disabled evaluation fixtures. The deleted pass-through type helper remains deleted because it added no interface leverage. |
| A02 | Done | `primaryUser.name` is the shared source for dotfiles, Fish, and GameMode; an alternate-user fixture prevents regressions. |
| R01 | External | Skill/rule lifecycle work is owned by the separate `../ai-usage` project and is deliberately out of scope here. |
| F02 | Decided | `claude-code` follows the root `nixpkgs`: its package and the host derivation stayed identical while one lock node disappeared. Zen Browser keeps its autonomous pin: following the root built successfully, but replaced the cached package with 25 local derivations. `input-topology` preserves that intentional split. |
| C01 | Done | The obsolete `wifi-reconnect` module was removed. |
| C02 | Done | The unused Amp integration was removed. |
| T02 | Done | Reproducible Bash, ShellCheck, Nix formatting, strict checking for Update TUI and Agent Memory, TypeScript compilation for Codex Monitor, and Bun bundling are part of the flake checks. Runtime declaration packages are versioned and hash-pinned. |
| AM01 | Separate | Agent Memory harvest retention, redaction, locking, and private-storage hardening are specified independently in [`docs/agent-memory-harvest-hardening.md`](./docs/agent-memory-harvest-hardening.md); they are not part of T02. |
| H01 | Done | `node_modules/` is ignored. |

## Validation contract

Run the same canonical entrypoint locally and in CI from the repository root:

```bash
./script/check.sh
```

The entrypoint uses a path flake so dirty worktrees include new, untracked files. To perform the
optional activation dry-run separately, without privileges:

```bash
nixos-rebuild dry-run --flake .#example
```

No audit or automation task should run `switch`, update the lockfile, stage, commit, or push unless
the user explicitly asks for that state change.
