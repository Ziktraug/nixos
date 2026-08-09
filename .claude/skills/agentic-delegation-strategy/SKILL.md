---
name: agentic-delegation-strategy
description: Decide when and how to delegate work to subagents.
---

# Delegation Strategy

## Heuristic

Delegate when:

- work is repetitive
- data volume grows
- tasks are parallelizable
- reasoning depends on aggregation

## Pattern

Primary agent:

- defines goal
- defines output schema

Subagent:

- executes bounded task
- returns compressed result

Primary agent:

- interprets outcome
