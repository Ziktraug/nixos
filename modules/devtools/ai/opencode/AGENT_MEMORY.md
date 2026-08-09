# Agent Memory

Use the shared operational memory setup when prior session context may affect the current task.

## Recall

From a repository:

```sh
agent-memory recall --repo "$PWD" --query "<task>"
```

## Capture

When a durable decision, pattern, pitfall, command, constraint, handoff, or lesson appears:

```sh
agent-memory append --scope repo --type pattern --title "Short title" --body "Actionable guidance."
```

Use `--scope global` only for cross-repo knowledge.

At meaningful checkpoints:

- skip trivial edits and duplicate insights;
- prefer `agent-memory append` for one clear reusable insight;
- use the repo-local `memory-distiller` subagent in proposal-only mode when multiple pending signals or a rich harvest need compression.
- run `agent-memory distill` only after review.

## End of meaningful work

```sh
agent-memory harvest --repo "$PWD" --since 24h
```

## Rules

- Never store secrets.
- Treat memory as guidance, not source of truth.
- Verify memory against repository files.
- Prefer concise, actionable entries.
- Keep distillation checkpoint-driven so it follows the current cost budget.
