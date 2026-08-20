# OpenCode 2 Global Instructions

Use RTK for high-output read and diagnostic commands to reduce context bloat.
The `openrtk` plugin rewrites supported shell commands automatically; state-changing
commands remain governed by OpenCode permissions.

Use the shared operational memory setup when prior session context may affect the
current task:

```sh
agent-memory recall --repo "$PWD"
```

Capture only durable decisions, patterns, pitfalls, commands, constraints, handoffs,
or lessons. Never store secrets, and always verify recalled memory against repository
files. After meaningful work, harvest the current repository with:

```sh
agent-memory harvest --repo "$PWD" --since 24h
```
