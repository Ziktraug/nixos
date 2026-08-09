---
name: agentic-diagnostic-probe
description: Collect repeated observations and return aggregated diagnostics.
---

# Diagnostic Probe

## Purpose

Perform structured observation without polluting main context.

## When To Use

- monitoring
- repeated scans
- profiling
- time-dependent behaviour

## Execution

1. Define sampling window.
2. Sample periodically.
3. Collect minimal metrics.
4. Aggregate results.

## Aggregation

Compute:

- concurrency peaks
- median (p50)
- high percentile (p95)
- lifecycle duration

## Output

Return:

### Summary

≤10 factual lines.

### Structured Data

JSON metrics.

### Evidence

≤10 representative samples.

## Non-Goals

Do not propose fixes or interpretations.
