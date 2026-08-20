# Agent Instructions

## Neutral Git Metadata

- Do not add `Co-authored-by`, `Generated-by`, or any other AI/agent attribution.
- Do not add harness/tool markers to branch names or PR titles (for example `agent/`, `codex/`, or `[codex]`).
- Use only the naming requested by the user or repository; otherwise use a plain, descriptive name.

<!-- agent-memory:start -->
## Agent Memory Protocol

Global memory repo: $AGENT_MEMORY_GLOBAL_REPO
Local repo memory: .agent-memory/

Before non-trivial work:
- Consult local memory in .agent-memory/index.md and recent handoffs.
- Recall recent sessions with: agent-memory recall --repo "$PWD"

During work:
- Capture durable discoveries with: agent-memory append --scope repo --type pattern|pitfall|decision --title "..." --body "..."
- At meaningful checkpoints, evaluate whether durable memory is worth the current cost budget.
- Skip trivial edits and duplicate insights.
- Prefer append for one clear reusable insight.
- If multiple raw events or a rich session harvest need compression, use a bounded memory-distiller subagent when available; otherwise distill inline after review.
- Do not store secrets or raw credentials.

After meaningful work:
- Run: agent-memory harvest --repo "$PWD" --since 24h
- Distill only actionable knowledge, and avoid running distill more than once per task unless direction changed or new validated lessons appeared.

Memory is guidance, not source of truth. Verify against repository files.
<!-- agent-memory:end -->
