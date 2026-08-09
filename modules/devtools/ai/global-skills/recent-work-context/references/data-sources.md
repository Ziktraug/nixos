# Data Sources

`recent-work-context` currently reads from these local stores:

- `~/.claude/projects/*/sessions-index.json`
- `~/.claude/projects/*/*.jsonl`
- `~/.local/share/opencode/opencode-stable.db`

Version 1 intentionally limits retrieval to Claude Code and OpenCode.

## Repo Matching

The script identifies the target repository from the current working directory by default.

It matches history using:

- canonical git root path
- repository basename
- `origin` remote URL when available

This supports cases where the repository moved on disk but kept the same name or remote.

## Privacy Guardrails

The script only reads conversation/session stores. It does not query auth blobs or unrelated global secrets.

OpenCode auth files and Cursor stores are intentionally excluded from v1.
