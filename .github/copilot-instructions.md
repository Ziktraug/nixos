# Copilot Instructions

## Neutral Git Metadata

- Do not add `Co-authored-by`, `Generated-by`, or any other AI/agent attribution.
- Do not add harness/tool markers to branch names or PR titles (for example `agent/`, `codex/`, or `[codex]`).
- Use only the naming requested by the user or repository; otherwise use a plain, descriptive name.

<!-- agent-memory:start -->
## Agent Memory

Use the local memory directory .agent-memory/ and the global memory repo declared in $AGENT_MEMORY_GLOBAL_REPO for durable operational context.

When starting multi-step work, inspect .agent-memory/index.md and search prior context with agent-memory recall when terminal access is available.
When discovering reusable decisions, patterns, pitfalls, or commands, append a concise event with agent-memory append.
At meaningful checkpoints, skip trivial edits, prefer append for one clear insight, and only distill when multiple pending signals justify consolidation.
When the current tool supports repo-local subagents, use a bounded memory-distiller in proposal-only mode for dense checkpoint compression before writing durable memory.
Never store secrets. Treat memory as guidance only; verify against source files.
<!-- agent-memory:end -->
