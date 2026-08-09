#!/usr/bin/env bash

set -euo pipefail

repo_root="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
agent_memory="$repo_root/modules/devtools/ai/agent-memory/scripts/agent-memory.ts"
recent_work_context="$repo_root/modules/devtools/ai/global-skills/recent-work-context/scripts/recent-work-context.ts"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

home="$fixture/home"
bin="$fixture/bin"
memory_repo="$fixture/repo"
raw_repo="$fixture/raw-repo"
mkdir -p "$home" "$bin" "$memory_repo/.agent-memory/inbox" "$memory_repo/.agent-memory/decisions" "$raw_repo"
mkdir -p "$memory_repo/.agent-memory/.git/hooks"
printf '#!/bin/sh\nexit 0\n' > "$memory_repo/.agent-memory/.git/hooks/fixture-hook"
chmod 755 "$memory_repo/.agent-memory/.git/hooks/fixture-hook"

cat > "$bin/recent-work-context" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat "$RECENT_WORK_CONTEXT_FIXTURE"
EOF
cat > "$bin/which" <<'EOF'
#!/usr/bin/env bash
echo "agent-memory must resolve PATH without which" >&2
exit 97
EOF
sed -i "1c#!${BASH}" "$bin/recent-work-context" "$bin/which"
chmod +x "$bin/recent-work-context" "$bin/which"

cat > "$fixture/config.json" <<EOF
{
  "globalRepoPath": "$fixture/global-memory",
  "managedRepos": ["$memory_repo"],
  "autoCapture": {
    "enable": true,
    "since": "24h",
    "onCalendar": "hourly",
    "retentionDays": 30,
    "maxEvents": 2
  },
  "adapters": {
    "claude": false,
    "copilot": false,
    "opencode": false,
    "cursor": false,
    "generic": false
  }
}
EOF

fixture_password_key=password

cat > "$memory_repo/.agent-memory/inbox/events.jsonl" <<EOF
{"version":"0.1.0","timestamp":"2000-01-01T00:00:00.000Z","scope":"repo","type":"session-harvest","title":"expired","body":"expired","repo":"/tmp/repo","source":"recent-work-context","sensitivity":"private","payload":{"records":[{"source":"opencode","sessionId":"expired","timestamp":1,"role":"tool","kind":"tool","text":"${fixture_password_key}=old-secret","files":[],"tool":"read","branch":"main","citation":"expired/1","repoPath":"/tmp/repo","score":1}]}}
EOF
chmod 755 "$memory_repo/.agent-memory" "$memory_repo/.agent-memory/inbox"
chmod 644 "$memory_repo/.agent-memory/inbox/events.jsonl"
printf '# Fixture index\n' > "$memory_repo/.agent-memory/index.md"
chmod 755 "$memory_repo/.agent-memory/decisions"
chmod 644 "$memory_repo/.agent-memory/index.md"

write_payload() {
    local target=$1
    local records=$2
    local decisions=$3
    local sessions=$4
    local top_citations=$5
    cat > "$target" <<EOF
{
  "repo": {"root": "$memory_repo", "name": "fixture", "branch": "main", "remoteUrl": null},
  "profile": "agent",
  "query": null,
  "lens": "recent",
  "source": "all",
  "summary": {
    "overview": ["raw output ${fixture_password_key}=summary-secret"],
    "decisions": $decisions,
    "preferences": [],
    "relevantFiles": [],
    "changedAreas": [],
    "failuresAndFixes": [],
    "sessions": $sessions
  },
  "agentContext": {
    "repoRoot": "$memory_repo",
    "query": null,
    "source": "all",
    "lens": "recent",
    "overview": ["raw output ${fixture_password_key}=summary-secret"],
    "decisions": ["Keep token=decision-secret"],
    "preferences": [],
    "relevantFiles": [],
    "changedAreas": [],
    "failuresAndFixes": [],
    "sessions": $sessions,
    "topCitations": $top_citations
  },
  "counts": {"total": 1, "matchedTotal": 1, "matchedSessions": 1, "focusedSessions": 1, "bySource": {"claude-code": 0, "opencode": 1}, "sessionsBySource": {"claude-code": 0, "opencode": 1}},
  "records": $records,
  "metadata": {
    "password": "hunter2",
    "nested": {"apiKey": "opaque-api-value"},
    "githubToken": "nested-token-value",
    "toolOutput": "Authorization: Bearer header.payload.signature"
  }
}
EOF
}

new_record='{"source":"opencode","sessionId":"newer","timestamp":2000000000000,"role":"tool","kind":"tool","text":"'"${fixture_password_key}"'=record-secret\n-----BEGIN PRIVATE\u0020KEY-----\nprivate-material\n-----END PRIVATE\u0020KEY-----","files":["safe.txt"],"tool":"read","branch":"main","citation":"newer/part-1","repoPath":"/tmp/repo","score":10}'
third_record='{"source":"claude-code","sessionId":"third","timestamp":2100000000000,"role":"assistant","kind":"message","text":"A third event","files":[],"tool":null,"branch":"main","citation":"third/part-1","repoPath":"/tmp/repo","score":8}'

new_decision='[{"text":"Keep token=decision-secret","citations":["newer/part-1"]}]'
new_session='[{"source":"opencode","sessionId":"newer","latestTimestamp":2000000000000,"synopsis":"'"${fixture_password_key}"'=session-secret","files":["safe.txt"],"citations":["newer/part-1"]}]'
late_decision='[{"text":"Late observation","citations":["late/part-1"]}]'
late_session='[{"source":"opencode","sessionId":"late","latestTimestamp":1000000000000,"synopsis":"late observation","files":["late.txt"],"citations":["late/part-1"]}]'
third_decision='[{"text":"Third observation","citations":["third/part-1"]}]'
third_session='[{"source":"claude-code","sessionId":"third","latestTimestamp":2100000000000,"synopsis":"third observation","files":[],"citations":["third/part-1"]}]'

write_payload "$fixture/new.json" "[$new_record]" "$new_decision" "$new_session" '["newer/part-1"]'
write_payload "$fixture/new-and-late.json" "[$new_record]" "[$(printf '%s' "$new_decision" | sed 's/^\[//;s/\]$//'),$(printf '%s' "$late_decision" | sed 's/^\[//;s/\]$//')]" "[$(printf '%s' "$new_session" | sed 's/^\[//;s/\]$//'),$(printf '%s' "$late_session" | sed 's/^\[//;s/\]$//')]" '["newer/part-1","late/part-1"]'
write_payload "$fixture/third.json" "[$third_record]" "$third_decision" "$third_session" '["third/part-1"]'

run_harvest() {
    local repo=$1
    local payload=$2
    shift 2
    HOME="$home" \
        PATH="$bin:$PATH" \
        AGENT_MEMORY_CONFIG="$fixture/config.json" \
        RECENT_WORK_CONTEXT_FIXTURE="$payload" \
        bun "$agent_memory" harvest --repo "$repo" --since 24h "$@"
}

wait_for_path() {
    local target=$1
    local attempts=${2:-500}
    local attempt

    for ((attempt = 0; attempt < attempts; attempt += 1)); do
        if [[ -e "$target" ]]; then
            return 0
        fi
        sleep 0.01
    done

    echo "timed out waiting for $target" >&2
    return 1
}

# Positive-integer options must reject any value that is not a complete decimal
# integer. In particular, parseInt-style prefixes must never control retention.
for invalid_integer in 12junk 1e3 1.5; do
    if run_harvest "$raw_repo" "$fixture/new.json" \
        --max-events "$invalid_integer" > "$fixture/invalid-integer-$invalid_integer.out" 2>&1; then
        echo "invalid positive integer unexpectedly accepted: $invalid_integer" >&2
        exit 1
    fi
    grep -Fq "Invalid positive integer: $invalid_integer" \
        "$fixture/invalid-integer-$invalid_integer.out"
done

for missing_integer_option in max-events retention-days; do
    if run_harvest "$raw_repo" "$fixture/new.json" \
        "--$missing_integer_option" > "$fixture/missing-$missing_integer_option.out" 2>&1; then
        echo "option without a positive-integer value unexpectedly accepted: --$missing_integer_option" >&2
        exit 1
    fi
    grep -Fq -- "--$missing_integer_option requires a value" \
        "$fixture/missing-$missing_integer_option.out"
done

if (
    cd "$fixture"
    HOME="$home" \
        PATH="$bin:$PATH" \
        AGENT_MEMORY_CONFIG="$fixture/config.json" \
        RECENT_WORK_CONTEXT_FIXTURE="$fixture/new.json" \
        bun "$agent_memory" harvest --dry-run --repo --max-events 10
) > "$fixture/missing-repo.out" 2>&1; then
    echo 'repeated option parser accepted --repo without a value' >&2
    exit 1
fi
grep -Fq -- '--repo requires a value' "$fixture/missing-repo.out"

# init-global and sync-adapters must validate every managed directory before
# changing permissions, creating siblings, or following an invalid directory.
global_root="$fixture/global-memory"
global_external="$fixture/global-external"
mkdir -p "$global_root" "$global_external"
chmod 755 "$global_root" "$global_external"
ln -s "$global_external" "$global_root/global"
if HOME="$home" AGENT_MEMORY_CONFIG="$fixture/config.json" \
    bun "$agent_memory" init-global > "$fixture/init-global-symlink.out" 2>&1; then
    echo "init-global unexpectedly accepted global -> external" >&2
    exit 1
fi
grep -q 'expected private directory is a symbolic link' "$fixture/init-global-symlink.out"
test "$(stat -c '%a' "$global_root")" = 755
test "$(stat -c '%a' "$global_external")" = 755
test ! -e "$global_external/decisions"
test ! -e "$global_root/SCHEMA.md"
rm "$global_root/global"

sync_repo="$fixture/sync-repo"
sync_external="$fixture/sync-external"
mkdir -p "$sync_repo/.agent-memory" "$sync_external"
git -C "$sync_repo" init -q
chmod 755 "$sync_repo/.agent-memory" "$sync_external"
ln -s "$sync_external" "$sync_repo/.agent-memory/inbox"
if HOME="$home" AGENT_MEMORY_CONFIG="$fixture/config.json" \
    bun "$agent_memory" sync-adapters --repo "$sync_repo" > "$fixture/sync-symlink.out" 2>&1; then
    echo "sync-adapters unexpectedly accepted inbox -> external" >&2
    exit 1
fi
grep -q 'expected private directory is a symbolic link' "$fixture/sync-symlink.out"
test "$(stat -c '%a' "$sync_repo/.agent-memory")" = 755
test "$(stat -c '%a' "$sync_external")" = 755
test ! -e "$sync_external/events.jsonl"
test ! -e "$sync_repo/.agent-memory/decisions"

run_harvest "$memory_repo" "$fixture/new.json" > "$fixture/first.out"

events="$memory_repo/.agent-memory/inbox/events.jsonl"
state="$memory_repo/.agent-memory/inbox/harvest-state.json"
test "$(wc -l < "$events")" -eq 1
test "$(stat -c '%a' "$memory_repo/.agent-memory")" = 700
test "$(stat -c '%a' "$memory_repo/.agent-memory/inbox")" = 700
test "$(stat -c '%a' "$memory_repo/.agent-memory/decisions")" = 700
test "$(stat -c '%a' "$memory_repo/.agent-memory/index.md")" = 600
test "$(stat -c '%a' "$memory_repo/.agent-memory/.git/hooks/fixture-hook")" = 755
test "$(stat -c '%a' "$events")" = 600
test "$(stat -c '%a' "$state")" = 600

for leaked in old-secret hunter2 opaque-api-value nested-token-value record-secret private-material summary-secret decision-secret session-secret header.payload.signature; do
    if grep -Fq "$leaked" "$events" "$state"; then
        echo "harvest leaked fixture secret: $leaked" >&2
        exit 1
    fi
done
grep -Fq '[REDACTED]' "$events"
bun -e 'const event = JSON.parse(await Bun.file(process.argv[1]).text()); if (event.sensitivity !== "secret-redacted") process.exit(1); if (event.payload.metadata.password !== "[REDACTED]") process.exit(2); if (event.payload.metadata.nested.apiKey !== "[REDACTED]") process.exit(3)' "$events"

# Automatic compaction must never discard manually appended durable candidates.
HOME="$home" AGENT_MEMORY_CONFIG="$fixture/config.json" \
    bun "$agent_memory" append --scope repo --repo "$memory_repo" --type decision --title "manual candidate" --body "keep me" > "$fixture/append.out"
test "$(wc -l < "$events")" -eq 2

run_harvest "$memory_repo" "$fixture/new.json" > "$fixture/duplicate.out"
test "$(wc -l < "$events")" -eq 2
grep -q 'no new observations' "$fixture/duplicate.out"

run_harvest "$memory_repo" "$fixture/new-and-late.json" > "$fixture/late.out"
test "$(wc -l < "$events")" -eq 3
bun -e 'const lines = (await Bun.file(process.argv[1]).text()).trim().split("\n").map(JSON.parse); const event = lines.at(-1); if (event.payload.records.length !== 0 || event.payload.summary.sessions[0]?.sessionId !== "late") process.exit(1)' "$events"
bun -e 'const state = JSON.parse(await Bun.file(process.argv[1]).text()); if (state.watermark !== 2000000000000) process.exit(1)' "$state"

run_harvest "$memory_repo" "$fixture/third.json" > "$fixture/third.out"
test "$(wc -l < "$events")" -eq 3
grep -q 'manual candidate' "$events"
grep -q 'late/part-1' "$events"
grep -q 'third/part-1' "$events"
! grep -q 'newer/part-1' "$events"

# Compaction must not make a still-known observation look new again.
run_harvest "$memory_repo" "$fixture/new.json" > "$fixture/compacted-duplicate.out"
test "$(wc -l < "$events")" -eq 3
grep -q 'no new observations' "$fixture/compacted-duplicate.out"

# Invalid JSON is persisted only as recursively redacted raw output and is deduplicated too.
fixture_api_key_name=OPENAI_API_KEY
cat > "$fixture/raw.txt" <<EOF
tool failed: ${fixture_api_key_name}=raw-output-secret Authorization: Bearer raw.header.signature
EOF
run_harvest "$raw_repo" "$fixture/raw.txt" > "$fixture/raw.out"
raw_events="$raw_repo/.agent-memory/inbox/events.jsonl"
test "$(wc -l < "$raw_events")" -eq 1
! grep -Fq 'raw-output-secret' "$raw_events"
! grep -Fq 'raw.header.signature' "$raw_events"
grep -Fq '[REDACTED]' "$raw_events"
run_harvest "$raw_repo" "$fixture/raw.txt" > "$fixture/raw-duplicate.out"
test "$(wc -l < "$raw_events")" -eq 1

# Private storage boundaries must never follow a repository-controlled symlink.
symlink_repo="$fixture/symlink-repo"
external_memory="$fixture/external-memory"
mkdir -p "$symlink_repo" "$external_memory"
chmod 755 "$external_memory"
ln -s "$external_memory" "$symlink_repo/.agent-memory"
if run_harvest "$symlink_repo" "$fixture/new.json" > "$fixture/symlink.out" 2>&1; then
    echo "symbolic-link memory root unexpectedly accepted" >&2
    exit 1
fi
grep -q 'refusing symbolic-link directory' "$fixture/symlink.out"
test "$(stat -c '%a' "$external_memory")" = 755
test ! -e "$external_memory/inbox/events.jsonl"

# Lock publication is fenced: unknown owners are never replaced, even when old.
lock="$raw_repo/.agent-memory/inbox/.write-lock"
: > "$lock"
touch -d '2 hours ago' "$lock"
if run_harvest "$raw_repo" "$fixture/raw.txt" > "$fixture/owner-absent.out" 2>&1; then
    echo "ownerless lock unexpectedly replaced" >&2
    exit 1
fi
grep -q 'has no verifiable owner' "$fixture/owner-absent.out"
rm -f "$lock"

printf 'malformed owner\n' > "$lock"
touch -d '2 hours ago' "$lock"
if run_harvest "$raw_repo" "$fixture/raw.txt" > "$fixture/owner-malformed.out" 2>&1; then
    echo "malformed lock owner unexpectedly replaced" >&2
    exit 1
fi
grep -q 'has no verifiable owner' "$fixture/owner-malformed.out"
rm -f "$lock"

process_start_time() {
    local pid=$1 stat tail
    local -a fields
    stat=$(<"/proc/$pid/stat")
    tail=${stat##*) }
    read -r -a fields <<< "$tail"
    printf '%s\n' "${fields[19]}"
}

# A valid live owner remains authoritative regardless of lock age.
printf '{"pid":%s,"startTime":"%s","token":"live-fixture"}\n' \
    "$$" "$(process_start_time "$$")" > "$lock"
touch -d '2 hours ago' "$lock"
if run_harvest "$raw_repo" "$fixture/raw.txt" > "$fixture/owner-live.out" 2>&1; then
    echo "live lock owner unexpectedly replaced" >&2
    exit 1
fi
grep -q 'owned by a live process' "$fixture/owner-live.out"
rm -f "$lock"

# A published lock whose exact PID/start-time owner is dead is safe to recover.
"$BASH" -c 'sleep 60' &
dead_pid=$!
dead_start_time=$(process_start_time "$dead_pid")
kill "$dead_pid"
wait "$dead_pid" 2>/dev/null || true
printf '{"pid":%s,"startTime":"%s","token":"dead-fixture"}\n' \
    "$dead_pid" "$dead_start_time" > "$lock"
run_harvest "$raw_repo" "$fixture/raw.txt" > "$fixture/owner-dead.out"
test ! -e "$lock"

# Two stale-lock contenders are serialized across the dead-owner decision and
# removal. The second process must remain fenced while the first is paused at
# the exact pre-takeover boundary.
"$BASH" -c 'sleep 60' &
race_dead_pid=$!
race_dead_start_time=$(process_start_time "$race_dead_pid")
kill "$race_dead_pid"
wait "$race_dead_pid" 2>/dev/null || true
printf '{"pid":%s,"startTime":"%s","token":"race-dead-fixture"}\n' \
    "$race_dead_pid" "$race_dead_start_time" > "$lock"

dead_checked="$fixture/dead-owner-checked"
continue_takeover="$fixture/continue-takeover"
gate_attempted="$fixture/second-gate-attempted"
AGENT_MEMORY_TEST_DEAD_LOCK_CHECK_SIGNAL="$dead_checked" \
AGENT_MEMORY_TEST_DEAD_LOCK_CHECK_CONTINUE="$continue_takeover" \
    run_harvest "$raw_repo" "$fixture/raw.txt" > "$fixture/race-first.out" 2>&1 &
race_first_pid=$!
wait_for_path "$dead_checked"

AGENT_MEMORY_TEST_LOCK_GATE_ATTEMPT_SIGNAL="$gate_attempted" \
    run_harvest "$raw_repo" "$fixture/raw.txt" > "$fixture/race-second.out" 2>&1 &
race_second_pid=$!
wait_for_path "$gate_attempted"
sleep 0.05
if ! kill -0 "$race_second_pid" 2>/dev/null; then
    echo "second stale-lock contender escaped the takeover fence" >&2
    wait "$race_second_pid" || true
    exit 1
fi

touch "$continue_takeover"
wait "$race_first_pid"
wait "$race_second_pid"
test ! -e "$lock"
test -z "$(find "$raw_repo/.agent-memory/inbox" -maxdepth 1 \
    \( -name '.write-lock.stale-*' -o -name '.write-lock.candidate-*' \) -print -quit)"

# Even a lock replaced outside the cooperative gate at the pre-rename boundary
# is detected by inode/content identity and left at the canonical path.
"$BASH" -c 'sleep 60' &
swap_dead_pid=$!
swap_dead_start_time=$(process_start_time "$swap_dead_pid")
kill "$swap_dead_pid"
wait "$swap_dead_pid" 2>/dev/null || true
printf '{"pid":%s,"startTime":"%s","token":"swap-dead-fixture"}\n' \
    "$swap_dead_pid" "$swap_dead_start_time" > "$lock"

swap_checked="$fixture/swap-owner-checked"
continue_swap="$fixture/continue-swap"
AGENT_MEMORY_TEST_DEAD_LOCK_CHECK_SIGNAL="$swap_checked" \
AGENT_MEMORY_TEST_DEAD_LOCK_CHECK_CONTINUE="$continue_swap" \
    run_harvest "$raw_repo" "$fixture/raw.txt" > "$fixture/swap-race.out" 2>&1 &
swap_racer_pid=$!
wait_for_path "$swap_checked"
printf '{"pid":%s,"startTime":"%s","token":"replacement-live-fixture"}\n' \
    "$$" "$(process_start_time "$$")" > "$lock.replacement"
mv "$lock.replacement" "$lock"
touch "$continue_swap"
if wait "$swap_racer_pid"; then
    echo "takeover unexpectedly displaced a replacement live owner" >&2
    exit 1
fi
grep -q 'owned by a live process' "$fixture/swap-race.out"
grep -q 'replacement-live-fixture' "$lock"
test -z "$(find "$raw_repo/.agent-memory/inbox" -maxdepth 1 \
    \( -name '.write-lock.stale-*' -o -name '.write-lock.candidate-*' \) -print -quit)"
rm -f "$lock"

# Claude session discovery must use the canonical projectPath, not a matching
# repository basename. File evidence must remain inside the canonical repo and
# Git userinfo must never survive normalization.
context_home="$fixture/context-home"
repo_a="$fixture/repos/one/app"
repo_b="$fixture/repos/two/app"
outside_file="$fixture/repos/one/outside.ts"
project_a_dir="$context_home/.claude/projects/project-a"
project_b_dir="$context_home/.claude/projects/unrelated-app"
mkdir -p "$repo_a/src" "$repo_b/src" "$project_a_dir" "$project_b_dir"
git -C "$repo_a" init -q
git -C "$repo_b" init -q
fixture_userinfo='fixture-user:fixture-password'
git -C "$repo_a" remote add origin \
    "https://${fixture_userinfo}@example.com/org/app.git"
printf 'inside\n' > "$repo_a/src/inside.ts"
printf 'outside\n' > "$outside_file"
ln -s "$outside_file" "$repo_a/src/escape.ts"

cat > "$project_a_dir/sessions-index.json" <<EOF
{"entries":[{"projectPath":"$repo_a","sessionId":"session-a","fullPath":"$project_a_dir/session-a.jsonl","modified":"2099-01-01T00:00:00.000Z","fileMtime":4070908800000,"gitBranch":"main"}]}
EOF
cat > "$project_b_dir/sessions-index.json" <<EOF
{"entries":[{"projectPath":"$repo_b","sessionId":"session-b","fullPath":"$project_b_dir/session-b.jsonl","modified":"2099-01-01T00:00:00.000Z","fileMtime":4070908800000,"gitBranch":"main"}]}
EOF
cat > "$project_a_dir/session-a.jsonl" <<EOF
{"type":"user","timestamp":"2099-01-01T00:00:00.000Z","message":{"content":"Inspect $repo_a/src/inside.ts, ../outside.ts and $repo_a/src/escape.ts"}}
EOF
cat > "$project_b_dir/session-b.jsonl" <<'EOF'
{"type":"user","timestamp":"2099-01-01T00:00:00.000Z","message":{"content":"REPO_B_MARKER must never cross repository boundaries"}}
EOF

HOME="$context_home" bun "$recent_work_context" \
    --repo "$repo_a" --profile agent --json --since 4w \
    > "$fixture/recent-work.json"
bun -e '
  const data = JSON.parse(await Bun.file(process.argv[1]).text());
  const files = data.summary.relevantFiles.map((file) => file.path);
  const recordFiles = data.records.flatMap((record) => record.files);
  if (data.repo.root !== process.argv[2]) process.exit(1);
  if (data.repo.remoteUrl !== "example.com/org/app") process.exit(2);
  if (!files.includes("src/inside.ts")) process.exit(3);
  if (files.includes("../outside.ts") || files.includes("src/escape.ts")) process.exit(4);
  if (!recordFiles.includes("src/inside.ts")) process.exit(5);
  if (recordFiles.includes("../outside.ts") || recordFiles.includes("src/escape.ts")) process.exit(6);
' "$fixture/recent-work.json" "$repo_a"
! grep -Fq 'fixture-password' "$fixture/recent-work.json"
! grep -Fq 'fixture-user' "$fixture/recent-work.json"
! grep -Fq 'REPO_B_MARKER' "$fixture/recent-work.json"

# Raw session harvests are not durable knowledge until their provenance has
# been reviewed and explicitly accepted.
distill_repo="$fixture/distill-repo"
mkdir -p "$distill_repo/.agent-memory/inbox"
git -C "$distill_repo" init -q
cat > "$distill_repo/.agent-memory/inbox/events.jsonl" <<EOF
{"version":"0.1.0","timestamp":"2099-01-01T00:00:00.000Z","scope":"repo","type":"session-harvest","title":"review me","body":"","repo":"$distill_repo","source":"recent-work-context","sensitivity":"private","payload":{"agentContext":{"overview":["Implemented the reviewed fixture"],"decisions":["Use canonical repository identity"],"preferences":[],"relevantFiles":["src/inside.ts"],"changedAreas":["session discovery"],"failuresAndFixes":[],"sessions":[],"topCitations":["session-a#L1"]}}}
EOF

HOME="$home" AGENT_MEMORY_CONFIG="$fixture/config.json" \
    bun "$agent_memory" distill --repo "$distill_repo" \
    > "$fixture/distill-skipped.out"
grep -Fq 'Skipped 1 session-harvest event' "$fixture/distill-skipped.out"
test -z "$(find "$distill_repo/.agent-memory" -mindepth 2 -type f \
    ! -path '*/inbox/*' -print -quit)"

HOME="$home" AGENT_MEMORY_CONFIG="$fixture/config.json" \
    bun "$agent_memory" distill --repo "$distill_repo" \
    --accept-session-harvest > "$fixture/distill-accepted.out"
test -n "$(find "$distill_repo/.agent-memory" -mindepth 2 -type f \
    ! -path '*/inbox/*' -print -quit)"
grep -R -Fq 'trust: harvest-accepted' \
    "$distill_repo/.agent-memory/decisions" \
    "$distill_repo/.agent-memory/handoffs"
grep -R -Fq 'harvest-accepted' \
    "$distill_repo/.agent-memory/decisions" \
    "$distill_repo/.agent-memory/handoffs"

echo "agent-memory harvest tests passed"
