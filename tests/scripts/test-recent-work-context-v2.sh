#!/usr/bin/env bash
set -euo pipefail

repo_root=${REPO_ROOT:?REPO_ROOT must be set}
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

project="$fixture/project"
data_home="$fixture/data"
database="$data_home/opencode/opencode-next.db"
mkdir -p "$project/src" "$(dirname "$database")"

git -C "$project" init -q
git -C "$project" config user.email fixture@example.com
git -C "$project" config user.name Test
touch "$project/src/example.ts"
git -C "$project" add src/example.ts
git -C "$project" commit -qm fixture

sqlite3 "$database" <<SQL
CREATE TABLE session_v2 (
  id TEXT PRIMARY KEY,
  directory TEXT NOT NULL,
  time_updated INTEGER NOT NULL
);
CREATE TABLE session_message (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  type TEXT NOT NULL,
  seq INTEGER NOT NULL,
  time_created INTEGER NOT NULL,
  data TEXT NOT NULL
);
INSERT INTO session_v2 VALUES ('session-v2', '$project', 2000);
INSERT INTO session_message VALUES (
  'message-user', 'session-v2', 'user', 1, 1000,
  '{"text":"Please inspect src/example.ts","files":[]}'
);
INSERT INTO session_message VALUES (
  'message-assistant', 'session-v2', 'assistant', 2, 2000,
  '{"content":[{"type":"text","text":"I inspected src/example.ts"},{"type":"tool","name":"shell","state":{"status":"completed","input":{"command":"git status"},"content":"clean"}}]}'
);
SQL

output="$fixture/output.json"
XDG_DATA_HOME="$data_home" \
  bun "$repo_root/modules/devtools/ai/global-skills/recent-work-context/scripts/recent-work-context.ts" \
    --repo "$project" \
    --source opencode \
    --limit 10 \
    --per-session-limit 10 \
    --json > "$output"

jq -e '.counts.bySource.opencode == 3' "$output" >/dev/null
jq -e '.records | any(.role == "user" and .text == "Please inspect src/example.ts")' "$output" >/dev/null
jq -e '.records | any(.role == "assistant" and .text == "I inspected src/example.ts")' "$output" >/dev/null
jq -e '.records | any(.role == "tool" and .tool == "shell" and .kind == "tool-result")' "$output" >/dev/null
jq -e '.records | all(.sessionId == "session-v2")' "$output" >/dev/null

echo "recent-work-context OpenCode V2 tests passed"
