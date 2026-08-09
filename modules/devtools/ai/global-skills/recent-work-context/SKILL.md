---
name: recent-work-context
description: Search repo-specific prior work from Claude Code and OpenCode histories. Use when you need earlier decisions, file changes, tool outputs, errors, or user preferences for the current repository.
compatibility: Requires Bun, access to ~/.claude/projects and ~/.local/share/opencode/opencode-stable.db, and works best from inside a git repository.
argument-hint: [--query "topic" --lens recent --source all --limit 32]
disable-model-invocation: true
allowed-tools: Bash(bun scripts/recent-work-context.ts *) Bash(recent-work-context *)
---

# Recent Work Context

Use this skill when the current task would benefit from prior repo-specific discussion, tool output, or implementation history.

## Workflow

1. Run the bundled script from the current repository:

```bash
bun scripts/recent-work-context.ts --profile agent $ARGUMENTS
```

2. If the user wants a different repository than the current working directory, rerun with `--repo /absolute/path`.
3. Read the returned citations before answering.
4. Answer with the most relevant prior decisions, touched files, failures, or preferences.

For manual shell usage outside the skill, this repo also installs a global wrapper command:

```bash
recent-work-context $ARGUMENTS
```

## Useful Lenses

- `recent` - newest relevant excerpts
- `user` - only prior user prompts
- `assistant` - only prior assistant responses
- `tools` - tool calls and tool results
- `errors` - failures and error output
- `files` - excerpts with file/path evidence
- `plans` - plans, todos, and execution outlines
- `prefs` - user preferences and constraints
- `decisions` - prior recommended choices and settled direction

## Output Expectations

- Prefer the script's default human-readable output for quick recall.
- The skill uses `--profile agent` so the agent gets a denser cross-session context set than the human CLI default.
- Agent profile output is grouped by session with a synopsis, top files, and curated excerpts to make synthesis easier.
- Agent profile output also derives higher-level sections for decisions, preferences, relevant files, and failures/fixes before the raw evidence groups.
- Agent profile intentionally focuses the summary on the highest-signal sessions instead of flattening every match into the context window.
- Use `--json` with `--profile agent` when another agent/tool should consume the derived `agentContext` programmatically.
- `--limit` controls returned excerpts, not total sessions scanned.
- Use `--session-limit` if you want to scan more candidate sessions before ranking.
- Use `--per-session-limit` if one conversation is dominating the output and you want more session diversity.
- Use `--source claude-code` or `--source opencode` when you want to inspect one history store in isolation.
- Use `--json` only when you need to post-process results.
- Cite the returned session/part references in your answer instead of paraphrasing without evidence.

## References

- [Data sources](references/data-sources.md)
- [Output format](references/output-format.md)
