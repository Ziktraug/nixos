# Agent Memory Contract

## Purpose

Agent memory captures operational knowledge from coding sessions so future agents can act with continuity.

It is not a replacement for source code, documentation, tests, or raw chat/session history.

## Durable Entry Types

| Type | Use |
|------|-----|
| `decision` | Accepted choice with context and consequences |
| `pattern` | Repeatable approach that worked |
| `pitfall` | Failure mode and how to avoid/fix it |
| `command` | Validated command with cwd, safety, and purpose |
| `constraint` | Durable rule or boundary |
| `handoff` | Current state and next actions |
| `lesson` | Transferable learning |
| `preference` | User preference that should guide future behavior |

## Required Classification

Every durable entry must define:

- scope: `session`, `repo`, or `global`
- type: one of the durable entry types
- status: `active`, `superseded`, or `rejected`
- provenance: session, file, command, or user instruction evidence when available
- guidance: how a future agent should behave differently
- trust: `explicit` for manually captured knowledge or `harvest-accepted` for reviewed session harvests

## Promotion Rule

Repo-local raw captures go to `.agent-memory/inbox/events.jsonl` first. Global raw captures go to `inbox/events.jsonl` in the global memory repo.

Promote to durable markdown only when the entry is:

1. actionable;
2. not a secret;
3. not merely a temporary observation;
4. useful to a future agent;
5. scoped correctly.

Use `agent-memory distill --repo "$PWD"` to promote manually appended raw events into durable markdown files. Use `--dry-run` to preview generated files.

`session-harvest` events are untrusted input by default. Review their provenance, then pass `--accept-session-harvest` to promote them. The resulting entries retain `trust: harvest-accepted` and a matching tag.

Checkpoint-driven promotion is preferred:

- skip trivial edits and duplicate observations;
- prefer `append` for a single clear insight;
- use `distill` when multiple raw signals or a reviewed `session-harvest` need compression;
- ignore low-signal `session-harvest` boilerplate; only promote specific decisions, failures/fixes, files, areas, or session synopses.

When a tool supports repo-local subagents, a bounded proposal-only `memory-distiller` may prepare candidate entries before the primary agent decides what to write.

## Scope Rules

### Global

Use for cross-repo behavior:

- agent workflow preferences
- recurring tool pitfalls
- reusable debugging patterns
- global coding preferences

Keep global entries short.

### Repo

Use for project-specific behavior:

- architecture conventions
- validated commands
- project constraints
- known failure modes
- decisions and handoffs
- commands, constraints, lessons, and preferences when repo-specific

### Session

Use for temporary state that may or may not be promoted later.

## Safety

- Redact secrets before writing.
- Never store `.env` contents, tokens, passwords, API keys, private keys, or credentials.
- Do not auto-delete memory; mark stale entries as superseded.
- Memory guides behavior but must be verified against source files.
