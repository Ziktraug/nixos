# Agent Memory harvest hardening

## Status

Implemented as an independent reliability change. This work is not part of remediation item T02;
T02 only adds reproducible TypeScript checking and bundling.

## Problem

Periodic harvest previously appended repeated recent-work payloads indefinitely and relied on
cooperative writers. Repo memory may contain private operational context, so duplicate growth,
concurrent writes, permissive modes, or partially written state are unacceptable.

## Required behavior

- Harvest only observations not already recorded for the repository.
- Persist a versioned watermark/fingerprint state and recover it from retained events if needed.
- Serialize inbox writers and recover locks only when their owner can be proven dead.
- Write state and event files atomically with private file and directory modes.
- Redact values whose keys or contents look credential-bearing before persistence.
- Compact raw harvest events by configurable age and count while retaining non-harvest events.
- Keep `--dry-run` free of inbox, state, permission, and compaction mutations.

## Configuration

`applications.devtools.ai.agent-memory.autoCapture` owns:

- `retentionDays`: maximum raw harvest-event age;
- `maxEvents`: maximum retained raw harvest-event count;
- the existing `since` and `onCalendar` scheduling inputs.

## Non-goals

- Distilling raw events automatically.
- Synchronizing or publishing the memory repository.
- Replacing `recent-work-context` as the session-source adapter.

## Acceptance

`tests/scripts/test-agent-memory-harvest.sh` must cover incremental harvesting, compaction,
redaction, private modes, dry-run behavior, concurrent writers, stale-lock recovery, and refusal to
steal a live or unverifiable lock. `./script/check.sh` must typecheck and bundle the runtime and run
the harvest suite.
