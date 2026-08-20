---
name: public-repository-publication
description: Detect whether the current NixOS checkout is the canonical private repository or the public snapshot, classify private versus exportable changes, and offer publication only from the verified private checkout. Use after meaningful changes, when discussing public versus private repository state, or when the user asks whether a change is publicly accessible.
---

# Public Repository Publication

## Repository role gate

Determine the current checkout's role before classifying changes or offering publication:

1. Resolve the Git root and inspect its `origin` URL.
2. Inspect whether `private/` exists and whether `reference/public` resolves to a separate Git checkout.
3. Treat the checkout as the **canonical private candidate** only when `private/` exists and `reference/public` is a valid separate checkout. Verify the private/public GitHub visibility before any publication mutation.
4. Treat a checkout without `private/` and without a valid `reference/public` as the **public snapshot**. In that role, do not run the export workflow and do not offer to publish back to itself. Explain that reusable changes must first be applied to the canonical private repository.
5. Stop and report an ambiguous topology instead of guessing when neither role matches.

## Repository model

- The canonical private repository is the source of truth and must track the private origin.
- Reusable files live outside `private/`.
- Machine identity, hardware, personal dotfiles, publication denylists, and local notes live under `private/`.
- `reference/public` resolves to a separate checkout of the public origin and is never part of the canonical Git tree.
- The public repository is a sanitized snapshot, not a Git mirror. Changes flow from private to public only through `script/export-public.sh`.

Verify these facts from the current checkout before relying on them. Do not infer public state from the private commit history.

## Classify changes

After meaningful repository changes, inspect the affected paths and classify them:

1. **Private-only**: every affected path has `export-ignore` set, especially `private/**`.
2. **Exportable**: at least one affected path is included by `git archive`.
3. **Mixed**: the change contains both private-only and exportable paths.

Use `git check-attr export-ignore -- <paths>` when the boundary is unclear. A file being exportable means it is eligible for publication; it does not mean it is already public.

Also distinguish Git state precisely:

- Uncommitted changes exist only in the local canonical checkout.
- Committed but unpushed changes are not on either GitHub repository.
- A normal push from the canonical checkout updates only the private origin.
- A change is public only after the exported change is committed and pushed from `reference/public`, and the public remote tip is verified.

## Required user reminder

When working from the verified canonical private candidate, if a completed change is exportable or mixed and is not confirmed in the public remote, end the handoff with this offer in the user's language:

> Ces changements sont publiables, mais ils ne sont pas encore publics. Veux-tu que je les exporte et les pousse vers le dépôt public ?

Adapt the wording when needed, but preserve the distinction between *exportable* and *already public*. Do not repeat the offer when the user has declined it for the current change set or when the public remote is already verified at the exported state.

Do not run the publication workflow merely because the reminder is required. Exporting, committing, pushing, opening a PR, or changing repository visibility requires explicit user authorization.

## Publication workflow

Run this workflow only from the verified canonical private candidate and after explicit authorization:

1. Resolve the canonical root with `git rev-parse --show-toplevel` and the public checkout with `realpath reference/public`.
2. Verify through GitHub metadata that the canonical origin is private and the `reference/public` origin is public. They must be different repositories.
3. Require a clean canonical worktree and a committed revision. Ask the user how to handle unrelated or uncommitted work instead of hiding it.
4. Verify the private commit is pushed before publishing its snapshot.
5. Require a clean public checkout, fetch it, and fast-forward its default branch. Never overwrite public-only work.
6. Run `./script/check.sh` and `./script/export-public.sh --check-only` from the canonical root.
7. Run `./script/export-public.sh --target "$PUBLIC_CHECKOUT" --revision HEAD`.
8. Inspect the public diff. Confirm that `private/`, local state, identities, hardware identifiers, and secrets are absent.
9. Run the public validation and safety checks, including Gitleaks, before committing.
10. Summarize the exact public diff and ask for any new authority that was not already granted.
11. Commit in the public checkout with neutral Git metadata, push normally, then verify the public remote tip.

Never use force-push, `git push --mirror`, or a two-way merge between the unrelated private and public histories. Public contributions must first be applied to the canonical private tree, then re-exported.

## Missing reference checkout

If `reference/public` is absent or broken, stop before publication. Explain that it should point to a separate clean clone of the public repository; do not repoint it or create a replacement clone unless the user authorizes that setup.

## Handoff format

Keep the result short and state:

- classification: private-only, exportable, or mixed;
- local/private/public availability;
- validation performed;
- whether publication was offered, authorized, completed, or declined.
