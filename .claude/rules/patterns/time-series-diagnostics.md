# Pattern: Time-Series Diagnostics

Applies when behaviour must be observed over time.

Examples:

- monitoring processes
- performance investigation
- concurrency analysis
- lifecycle tracking

## Required Behaviour

1. Delegate sampling to a subagent.
2. Define observation window and cadence.
3. Aggregate measurements.
4. Return compressed results.

Primary agent performs interpretation only.
