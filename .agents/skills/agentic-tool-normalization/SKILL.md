---
name: agentic-tool-normalization
description: Reduce large tool outputs into structured summaries.
---

# Tool Output Normalization

## Purpose

Prevent context explosion from large command outputs.

## Strategy

1. Identify useful signals.
2. Extract fields only.
3. Remove repetition.
4. Convert into structured format.

## Transformations

- logs → counts/events
- listings → tables
- snapshots → aggregates

## Output

Short explanation + structured summary + minimal evidence.
