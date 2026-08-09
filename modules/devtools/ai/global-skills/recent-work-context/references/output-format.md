# Output Format

The script supports two output modes.

## Human Mode

Default mode prints:

- target repo info
- selected profile
- selected lens and query
- selected source filter
- excerpt counts and result-session counts
- ranked excerpts with timestamps and citations
- related files when available

Use this mode for normal skill invocation.

When `--profile agent` is active, human-readable output is grouped by session and includes:

- derived summary sections for decisions, preferences, relevant files, and failures/fixes
- changed-area inference from the most relevant repo files
- focused-session selection so the summary stays centered on the highest-signal matches
- one synopsis line per session
- aggregated file hints
- curated excerpts under each session

## JSON Mode

`--json` prints a single JSON object with:

- `repo`
- `query`
- `lens`
- `agentContext`
- `summary`
- `counts`
- `records`

`counts.total` is the number of returned excerpts after ranking and limiting, not the number of scanned sessions.

Additional count fields:

- `counts.matchedTotal` - ranked excerpts before the final excerpt limit
- `counts.matchedSessions` - sessions represented in the ranked pool
- `counts.focusedSessions` - sessions used by the derived summary

By default the script also caps how many excerpts come from a single session so one long conversation does not crowd out older relevant sessions.

## Profiles

- `human` keeps shell output reasonably compact
- `agent` returns a denser result set and scans more sessions by default

The skill uses `--profile agent`. The standalone `recent-work-context` CLI defaults to `human` unless you override it.

## Agent JSON

When `--profile agent --json` is used, `agentContext` provides a machine-first subset of the response with:

- `overview`
- `decisions`
- `preferences`
- `relevantFiles`
- `changedAreas`
- `failuresAndFixes`
- `sessions`
- `topCitations`

Each record includes:

- `source`
- `sessionId`
- `timestamp`
- `role`
- `kind`
- `text`
- `files`
- `tool`
- `branch`
- `citation`
- `score`

Use JSON mode when another tool or script needs structured results.
