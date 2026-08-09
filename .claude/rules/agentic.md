# Agentic Execution Rules

## Core Principle

Primary agent reasons.
Subagents collect and transform data.

## Delegation Triggers

Spawn a subagent when tasks include:

- repeated measurements
- monitoring or profiling
- large command output
- multi-file enumeration
- batch transformations

## Tool Discipline

Prefer filtered commands.

BAD:
ps aux

GOOD:
ps -o pid,ppid,etimes,rss,comm

Avoid repeating full outputs.

## Compression Rule

After multiple observations:

- aggregate findings
- replace raw logs with summarized facts.

Subagents must return structured summaries, not raw dumps.
