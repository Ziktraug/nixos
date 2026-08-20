---
name: agent-memory
description: "Use when: recalling prior coding-session context, capturing durable decisions/patterns/pitfalls, syncing repo memory adapters, or maintaining cross-agent operational memory for Claude, Copilot, OpenCode, and Cursor."
version: 0.1.0
compatibility: Requires the declarative agent-memory Nix module and a configured global second-brain repository.
argument-hint: recall|append|harvest|distill|lint|doctor
allowed-tools: Bash(agent-memory *) Bash(recent-work-context *)
---

# Agent Memory

Maintain durable operational memory from agentic coding sessions.

Use this for knowledge that would otherwise disappear after a session:

- decisions
- patterns that worked
- pitfalls and fixes
- validated commands
- repo constraints
- handoffs
- transferable lessons
- user preferences

## Core Rule

Only persist knowledge that should change the behavior of a future agent.

Do not store raw chat dumps as durable memory. Repo-local raw captures belong in `.agent-memory/inbox/events.jsonl` until distilled; global raw captures belong in the global memory repo's `inbox/events.jsonl`.

## Scopes

- `session` - temporary capture for the current session.
- `repo` - project-specific memory stored in `.agent-memory/` inside the repository.
- `global` - cross-repo memory stored in the configured second-brain repo.

## Workflows

### Recall Before Work

Run from the target repository:

```bash
agent-memory recall --repo "$PWD"
```

Add `--query "<task>"` only when task-specific ranking is worth an interactive
shell approval.

Read local memory if present:

- `.agent-memory/index.md`
- `.agent-memory/handoffs/`
- `.agent-memory/decisions/`
- `.agent-memory/patterns/`
- `.agent-memory/pitfalls/`

### Capture During Work

When a durable lesson appears:

```bash
agent-memory append --scope repo --type decision --title "Short title" --body "Context, decision, guidance."
```

Use `--scope global` only for transferable knowledge.

### Harvest Recent Sessions

At the end of meaningful work:

```bash
agent-memory harvest --repo "$PWD" --since 24h
```

This appends recent Claude/OpenCode context into `.agent-memory/inbox/events.jsonl` for later distillation.

### Distill Inbox Events

After harvest or manual append, promote actionable raw events into durable markdown:

```bash
agent-memory distill --repo "$PWD" --accept-session-harvest
```

Use preview mode before writing if desired:

```bash
agent-memory distill --repo "$PWD" --dry-run
```

Distillation is deterministic and idempotent. It creates entries under `.agent-memory/decisions/`, `patterns/`, `pitfalls/`, `handoffs/`, `commands/`, `constraints/`, `lessons/`, or `preferences/` depending on the input event type.

Manually appended durable candidates can be distilled directly and are marked `trust: explicit`. A `session-harvest` is skipped unless `--accept-session-harvest` is supplied after reviewing its provenance; promoted entries are marked `trust: harvest-accepted`.

For accepted `session-harvest` events, distill promotes only non-generic signals. Boilerplate overview lines are ignored, and handoffs are created from specific signals such as decisions, failures/fixes, changed areas, relevant files, or session synopses.

### Checkpoint-Driven Policy

Do not run distill on a timer by default.

At meaningful checkpoints:

- skip trivial edits and duplicate insights;
- prefer `agent-memory append` for one clear reusable insight;
- use `agent-memory distill` only when multiple pending signals or a rich `session-harvest` need consolidation.

When the current tool supports repo-local subagents, use `memory-distiller` in proposal-only mode to compress dense checkpoint context before writing durable memory.

Recommended checkpoints:

- validated root cause found;
- fix tested successfully;
- durable pattern or pitfall identified;
- task handoff or direction change;
- recent harvest produced actionable material.

### Sync Adapters

```bash
agent-memory sync-adapters
```

Creates or updates non-destructive managed blocks for:

- `AGENTS.md`
- `.github/copilot-instructions.md`
- `.cursor/rules/agent-memory.mdc`
- `.claude/CLAUDE.md`

### Health Check

```bash
agent-memory doctor
agent-memory lint --global --repos
```

## Safety Rules

- Never store secrets, tokens, passwords, or credentials.
- Treat memory as guidance, not source of truth.
- Verify against repository files before acting.
- Prefer append-only writes.
- Distill inbox events before relying on them as durable guidance.
- Supersede stale entries instead of deleting.
- Keep global memory short and behavioral.
- Repo memory may be more detailed but must remain actionable.
- Use checkpoint-driven distillation to control agent cost.

## References

- [Memory contract](references/memory-contract.md)
