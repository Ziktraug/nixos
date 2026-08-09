# codex-monitor

Local CLI for inspecting Codex usage from files written by the Codex VS Code extension and Codex CLI.

The tool is installed by the NixOS module `applications.devtools.tui.codex-monitor` and runs the TypeScript source directly with Bun. It does not call any remote API.

## Usage

```bash
codex-monitor sessions
```

Show workflows active during a recent window:

```bash
codex-monitor sessions --since 7d
```

Filter by project directory name:

```bash
codex-monitor sessions --project Exalibur
```

Limit output and avoid expanding sub-agents:

```bash
codex-monitor sessions --limit 20 --no-expand
```

Emit JSON for scripting:

```bash
codex-monitor sessions --json
```

Use non-default Codex paths:

```bash
codex-monitor sessions \
  --path ~/.codex/sessions \
  --index ~/.codex/session_index.jsonl
```

## Data Sources

- `~/.codex/sessions/**/*.jsonl` for session metadata, task counts, token counters, quota state, model, origin, and sub-agent parentage.
- `~/.codex/session_index.jsonl` for the generated session name shown in the `Session` column.

## Privacy

The parser is metadata-oriented. It intentionally reads only session metadata, turn context, task starts, token counters, rate limits, and session index titles. It does not display user prompts, assistant responses, tool arguments, or tool outputs from the JSONL files.

## Notes

- `Observed Tokens` is the sum of each rendered session's maximum observed `total_token_usage.total_tokens`. Codex counters can be cumulative and should not be treated as billing cost.
- `Fresh` / `Observed Fresh Tokens` subtract cached input tokens from the observed total. It is still an estimate from local counters, not a billing source of truth.
- `Latest Quota` comes from the newest local `token_count.rate_limits` event and is usually more useful than token totals for subscription monitoring.
- Sub-agent rows are grouped under their parent session when Codex records `parent_thread_id`.
