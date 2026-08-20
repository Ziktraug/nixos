---
name: setup-agent-memory
description: Bootstrap agent-memory second-brain support in a repository. Use when setting up agent-memory, repo-local .agent-memory, global memory, AGENTS.md memory protocol, or cross-agent memory adapters.
---

# Setup Agent Memory

Set up durable agent memory for the current repository without turning memory into a raw chat dump.

## Principles

- Persist only knowledge that should change future agent behavior.
- Use repo memory for project-specific decisions, patterns, pitfalls, commands, constraints, lessons, preferences, and handoffs.
- Use global memory only for cross-repo preferences or reusable practices.
- Never store secrets, credentials, tokens, private customer data, or raw logs containing sensitive data.
- Treat memory as guidance; verify against repository files before acting.

## Workflow

1. Check the CLI is available:

```bash
agent-memory doctor
```

2. Inspect existing memory state:

```bash
agent-memory recall --repo "$PWD"
```

3. Install or update repository adapters:

```bash
agent-memory sync-adapters
```

4. Confirm repo-local memory exists:

```bash
ls .agent-memory
```

5. If `.agent-memory/index.md` is missing, create a minimal index with repo name, global repo note, and directories for durable memory.

6. Run a health check:

```bash
agent-memory doctor
agent-memory lint --global --repos
```

7. Add an initial durable memory only when there is clear actionable guidance. Prefer repo scope for project conventions.

```bash
agent-memory append --scope repo --type decision --title "Short decision" --body "Context, decision, future guidance."
```

## Daily Use

- Before non-trivial work, recall recent memory with `agent-memory recall --repo "$PWD"`.
- During work, append one clear durable insight when it appears.
- After meaningful work, run `agent-memory harvest --repo "$PWD" --since 24h`.
- Distill only at checkpoints where multiple raw signals justify promotion.

## Output

When setup completes, report:

- adapters touched
- memory directories present
- health-check status
- any durable memories added
- any remaining manual follow-up
