#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
HOSTNAME_SHORT="$(hostname -s)"
NIXOS_FLAKE_PATH="${NIXOS_FLAKE_PATH:-$PROJECT_ROOT/hosts/$HOSTNAME_SHORT}"
NIXOS_HOST_KEY="${NIXOS_HOST_KEY:-$HOSTNAME_SHORT}"
PROMPTS_ENABLED=1
RELEASE_POLICY="${RELEASE_UPDATE_POLICY:-interactive}"
if [ -n "${RELEASE_UPDATE_POLICY+x}" ]; then
  RELEASE_POLICY_EXPLICIT=1
else
  RELEASE_POLICY_EXPLICIT=0
fi
LOG_FILE=""
JSON_SUMMARY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --no-prompts)
      PROMPTS_ENABLED=0
      shift
      ;;
    --release-policy)
      RELEASE_POLICY="${2:-}"
      [ -n "$RELEASE_POLICY" ] || {
        printf '[ERROR] --release-policy requires a value\n' >&2
        exit 1
      }
      RELEASE_POLICY_EXPLICIT=1
      shift 2
      ;;
    --release-policy=*)
      RELEASE_POLICY="${1#*=}"
      RELEASE_POLICY_EXPLICIT=1
      shift
      ;;
    --log-file)
      LOG_FILE="${2:-}"
      [ -n "$LOG_FILE" ] || {
        printf '[ERROR] --log-file requires a path\n' >&2
        exit 1
      }
      shift 2
      ;;
    --json-summary)
      JSON_SUMMARY="${2:-}"
      [ -n "$JSON_SUMMARY" ] || {
        printf '[ERROR] --json-summary requires a path\n' >&2
        exit 1
      }
      shift 2
      ;;
    *)
      printf '[ERROR] Unknown option: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

if [ "$PROMPTS_ENABLED" = "0" ] && [ "$RELEASE_POLICY_EXPLICIT" = "0" ]; then
  RELEASE_POLICY="keep"
fi

case "$RELEASE_POLICY" in
  interactive|accept|keep) ;;
  *)
    printf '[ERROR] release policy must be one of: interactive, accept, keep\n' >&2
    exit 1
    ;;
esac

export RELEASE_UPDATE_POLICY="$RELEASE_POLICY"

if [ -n "$LOG_FILE" ]; then
  mkdir -p "$(dirname "$LOG_FILE")"
  exec > >(tee -a "$LOG_FILE") 2>&1
fi

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  COLOR_RESET=$'\033[0m'
  COLOR_BOLD=$'\033[1m'
  COLOR_DIM=$'\033[2m'
  COLOR_YELLOW=$'\033[33m'
  COLOR_BLUE=$'\033[34m'
  COLOR_CYAN=$'\033[36m'
else
  COLOR_RESET=''
  COLOR_BOLD=''
  COLOR_DIM=''
  COLOR_YELLOW=''
  COLOR_BLUE=''
  COLOR_CYAN=''
fi

INPUTS_BEFORE_TSV="$(mktemp)"
INPUTS_AFTER_TSV="$(mktemp)"
RELEASES_BEFORE_TSV="$(mktemp)"
RELEASES_AFTER_TSV="$(mktemp)"
INPUT_CHANGES_TSV="$(mktemp)"
RELEASE_CHANGES_TSV="$(mktemp)"
STAGE_TARGETS_TXT="$(mktemp)"
CHECK_STATUS="not-run"
trap 'rm -f "$INPUTS_BEFORE_TSV" "$INPUTS_AFTER_TSV" "$RELEASES_BEFORE_TSV" "$RELEASES_AFTER_TSV" "$INPUT_CHANGES_TSV" "$RELEASE_CHANGES_TSV" "$STAGE_TARGETS_TXT"' EXIT

section() {
  printf '%s%s%s\n' "$COLOR_BOLD$COLOR_BLUE" "$1" "$COLOR_RESET"
}

info() {
  printf '%s[INFO]%s %s\n' "$COLOR_CYAN" "$COLOR_RESET" "$1"
}

warn() {
  printf '%s[WARN]%s %s\n' "$COLOR_YELLOW" "$COLOR_RESET" "$1"
}

die() {
  printf '%s[ERROR]%s %s\n' "$COLOR_YELLOW" "$COLOR_RESET" "$1" >&2
  exit 1
}

snapshot_root_inputs() {
  local output_file="$1"

  if ! command -v jq >/dev/null 2>&1 || [ ! -f "$NIXOS_FLAKE_PATH/flake.lock" ]; then
    : > "$output_file"
    return
  fi

  jq -r '
    .nodes as $nodes
    | .nodes[.root].inputs
    | to_entries[]
    | select((.value | type) == "string")
    | .key as $alias
    | .value as $nodeKey
    | $nodes[$nodeKey] as $node
    | [
        $alias,
        ($node.locked.lastModified // 0 | tostring),
        ($node.locked.rev // "-")
      ]
    | @tsv
  ' "$NIXOS_FLAKE_PATH/flake.lock" > "$output_file"
}

snapshot_release_versions() {
  local output_file="$1"
  : > "$output_file"

  if ! command -v jq >/dev/null 2>&1; then
    return
  fi

  shopt -s nullglob globstar
  local file
  for file in "$PROJECT_ROOT"/modules/**/release.json; do
    local name version
    name="$(basename "$(dirname "$file")")"
    version="$(jq -r '.version // .tag // "-"' "$file")"
    printf '%s\t%s\t%s\n' "$name" "${file#"$PROJECT_ROOT"/}" "$version" >> "$output_file"
  done
  shopt -u nullglob globstar
}

format_input_ref() {
  local epoch="$1"
  local rev="$2"
  local ref_label=""

  if [ -n "$epoch" ] && [ "$epoch" != "0" ]; then
    ref_label="$(date -d "@$epoch" +%Y-%m-%d 2>/dev/null || printf '%s' "$epoch")"
  fi

  if [ -n "$rev" ] && [ "$rev" != "-" ]; then
    ref_label="${ref_label:+$ref_label@}${rev:0:7}"
  fi

  printf '%s\n' "${ref_label:--}"
}

compute_update_changes() {
  declare -A INPUTS_BEFORE=()
  declare -A RELEASES_BEFORE=()
  local alias epoch rev current next release_name release_path release_version

  : > "$INPUT_CHANGES_TSV"
  : > "$RELEASE_CHANGES_TSV"

  while IFS=$'\t' read -r alias epoch rev; do
    [ -z "${alias:-}" ] && continue
    INPUTS_BEFORE["$alias"]="$(format_input_ref "$epoch" "$rev")"
  done < "$INPUTS_BEFORE_TSV"

  while IFS=$'\t' read -r alias epoch rev; do
    [ -z "${alias:-}" ] && continue
    current="${INPUTS_BEFORE[$alias]:-}"
    next="$(format_input_ref "$epoch" "$rev")"
    if [ -n "$current" ] && [ "$current" != "$next" ]; then
      printf '%s\t%s\t%s\n' "$alias" "$current" "$next" >> "$INPUT_CHANGES_TSV"
    fi
  done < "$INPUTS_AFTER_TSV"

  while IFS=$'\t' read -r release_name release_path release_version; do
    [ -z "${release_name:-}" ] && continue
    RELEASES_BEFORE["$release_path"]="$release_version"
  done < "$RELEASES_BEFORE_TSV"

  while IFS=$'\t' read -r release_name release_path release_version; do
    [ -z "${release_name:-}" ] && continue
    current="${RELEASES_BEFORE[$release_path]:-}"
    if [ -n "$current" ] && [ "$current" != "$release_version" ]; then
      printf '%s\t%s\t%s\t%s\n' "$release_name" "$release_path" "$current" "$release_version" >> "$RELEASE_CHANGES_TSV"
    fi
  done < "$RELEASES_AFTER_TSV"
}

print_update_summary() {
  local -a INPUT_LINES=()
  local -a RELEASE_LINES=()
  local alias current next release_name release_path release_version

  while IFS=$'\t' read -r alias current next; do
    [ -z "${alias:-}" ] && continue
    INPUT_LINES+=("$alias $COLOR_DIM$current -> $next$COLOR_RESET")
  done < "$INPUT_CHANGES_TSV"

  while IFS=$'\t' read -r release_name release_path current release_version; do
    [ -z "${release_name:-}" ] && continue
    RELEASE_LINES+=("$release_name $COLOR_DIM$current -> $release_version$COLOR_RESET")
  done < "$RELEASE_CHANGES_TSV"

  echo
  section "========== Update Summary =========="
  printf '  %sInputs refreshed%s %s\n' "$COLOR_DIM" "$COLOR_RESET" "${#INPUT_LINES[@]}"
  if [ ${#INPUT_LINES[@]} -gt 0 ]; then
    printf '    - %s\n' "${INPUT_LINES[@]}"
  fi
  printf '  %sPinned releases%s %s\n' "$COLOR_DIM" "$COLOR_RESET" "${#RELEASE_LINES[@]}"
  if [ ${#RELEASE_LINES[@]} -gt 0 ]; then
    printf '    - %s\n' "${RELEASE_LINES[@]}"
  fi
  if [ ${#INPUT_LINES[@]} -eq 0 ] && [ ${#RELEASE_LINES[@]} -eq 0 ]; then
    printf '  %sNo lock or pinned release changes detected.%s\n' "$COLOR_DIM" "$COLOR_RESET"
  else
    printf '  %sRebuild summary will show installed package version changes.%s\n' "$COLOR_DIM" "$COLOR_RESET"
  fi
}

collect_stage_targets() {
  : > "$STAGE_TARGETS_TXT"

  if ! git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return
  fi

  local targets=("hosts/$NIXOS_HOST_KEY/flake.lock")
  shopt -s nullglob globstar
  local release_files=("$PROJECT_ROOT"/modules/**/release.json)
  shopt -u nullglob globstar

  local file
  for file in "${release_files[@]}"; do
    targets+=("${file#"$PROJECT_ROOT"/}")
  done

  for file in "${targets[@]}"; do
    if [ -n "$(git -C "$PROJECT_ROOT" status --porcelain -- "$file" 2>/dev/null)" ]; then
      printf '%s\n' "$file" >> "$STAGE_TARGETS_TXT"
    fi
  done
}

write_json_summary() {
  local status="$1"
  local error_message="${2:-}"

  [ -n "$JSON_SUMMARY" ] || return 0
  mkdir -p "$(dirname "$JSON_SUMMARY")"

  if ! command -v jq >/dev/null 2>&1; then
    printf '{"schemaVersion":1,"operation":"update","status":"%s","releasePolicy":"%s","error":"jq not available for full summary"}\n' \
      "$status" "$RELEASE_POLICY" > "$JSON_SUMMARY"
    return 0
  fi

  local dirty="0"
  if git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 && [ -n "$(git -C "$PROJECT_ROOT" status --porcelain 2>/dev/null)" ]; then
    dirty="1"
  fi

  jq -n \
    --arg status "$status" \
    --arg error "$error_message" \
    --arg repo "$PROJECT_ROOT" \
    --arg host "$NIXOS_HOST_KEY" \
    --arg flakePath "$NIXOS_FLAKE_PATH" \
    --arg logFile "$LOG_FILE" \
    --arg checkStatus "$CHECK_STATUS" \
    --arg dirty "$dirty" \
    --arg releasePolicy "$RELEASE_POLICY" \
    --rawfile inputChanges "$INPUT_CHANGES_TSV" \
    --rawfile releaseChanges "$RELEASE_CHANGES_TSV" \
    --rawfile stageTargets "$STAGE_TARGETS_TXT" \
    '
    def rows($value): $value | split("\n") | map(select(length > 0) | split("\t"));
    {
      status: $status,
      schemaVersion: 1,
      operation: "update",
      releasePolicy: $releasePolicy,
      error: (if $error == "" then null else $error end),
      repo: $repo,
      host: $host,
      flakePath: $flakePath,
      logFile: (if $logFile == "" then null else $logFile end),
      checkStatus: $checkStatus,
      dirty: ($dirty == "1"),
      inputs: [rows($inputChanges)[] | {name: .[0], before: .[1], after: .[2]}],
      releases: [rows($releaseChanges)[] | {name: .[0], path: .[1], before: .[2], after: .[3]}],
      gitTargets: ($stageTargets | split("\n") | map(select(length > 0)))
    }
    ' > "$JSON_SUMMARY"
}

confirm_yes_default() {
  local prompt="$1"
  local reply
  if ! read -r -p "$prompt [Y/n] " reply; then
    warn "No response received; skipping rebuild"
    return 1
  fi
  reply=${reply:-y}
  [[ "$reply" =~ ^[Yy]$ ]]
}

ensure_host_flake() {
  if [ ! -f "$NIXOS_FLAKE_PATH/flake.nix" ]; then
    die "Host flake not found at $NIXOS_FLAKE_PATH/flake.nix"
  fi
}

run_pre_update_hooks() {
  shopt -s nullglob globstar
  local hooks=("$PROJECT_ROOT"/modules/**/update-flake-pre.sh)
  shopt -u nullglob globstar

  if [ ${#hooks[@]} -eq 0 ]; then
    info "No pre-update hooks found"
    return
  fi

  info "Running pre-update hooks..."
  local hook
  for hook in "${hooks[@]}"; do
    local rel_hook="${hook#"$PROJECT_ROOT"/}"
    if [ ! -x "$hook" ]; then
      warn "Skipping non-executable hook: $rel_hook"
      continue
    fi

    info "Running hook: $rel_hook"
    NIXOS_FLAKE_PATH="$NIXOS_FLAKE_PATH" \
      NIXOS_HOST_KEY="$NIXOS_HOST_KEY" \
      RELEASE_UPDATE_POLICY="$RELEASE_POLICY" \
      "$hook"
  done
}

run_flake_update() {
  local attempt=1
  local max_attempts=3

  while [ "$attempt" -le "$max_attempts" ]; do
    info "Running host flake update (attempt $attempt/$max_attempts): $NIXOS_FLAKE_PATH"

    local output_file
    output_file="$(mktemp)"

    if nix flake update --flake "$NIXOS_FLAKE_PATH" 2>&1 | tee "$output_file"; then
      if grep -q "could not update local clone of Git repository" "$output_file"; then
        rm -f "$output_file"
        if [ "$attempt" -lt "$max_attempts" ]; then
          warn "flake update used stale git input(s); retrying shortly..."
          sleep 3
          attempt=$((attempt + 1))
          continue
        fi
        warn "flake update used stale git input(s); no lock refresh was completed"
        warn "Please rerun update when network access to failing remotes is restored"
        return 1
      fi

      rm -f "$output_file"
      return 0
    fi

    if grep -q "Failed to fetch git repository" "$output_file" || grep -q "could not update local clone of Git repository" "$output_file"; then
      rm -f "$output_file"
      if [ "$attempt" -lt "$max_attempts" ]; then
        warn "git input fetch failed; retrying shortly..."
        sleep 3
        attempt=$((attempt + 1))
        continue
      fi
      warn "flake update failed after $max_attempts attempts due to git input fetch errors"
      return 1
    fi

    rm -f "$output_file"
    warn "flake update failed"
    return 1
  done
}

run_lightweight_checks() {
  info "Running lightweight flake checks: $NIXOS_FLAKE_PATH"

  if nix flake check --no-build "$NIXOS_FLAKE_PATH"; then
    CHECK_STATUS="passed"
    return 0
  fi

  CHECK_STATUS="failed"
  warn "Lightweight flake checks failed"
  warn "Skipping rebuild prompt until the evaluation issue is fixed"
  return 1
}

propose_next_steps() {
  echo

  collect_stage_targets
  if [ -s "$STAGE_TARGETS_TXT" ]; then
    local stage_targets=()
    while IFS= read -r file; do
      [ -z "$file" ] && continue
      stage_targets+=("$file")
    done < "$STAGE_TARGETS_TXT"

    info "For safety, git staging stays manual."
    info "Please run: git -C \"$PROJECT_ROOT\" add -- ${stage_targets[*]}"
  elif ! git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    warn "Not a git worktree at $PROJECT_ROOT, skipping staging suggestion"
  else
    info "No lock or release metadata changes to stage."
  fi

  if confirm_yes_default "Run rebuild script now?"; then
    "$PROJECT_ROOT/script/rebuild.sh"
  fi
}

main() {
  ensure_host_flake
  snapshot_root_inputs "$INPUTS_BEFORE_TSV"
  snapshot_release_versions "$RELEASES_BEFORE_TSV"
  run_pre_update_hooks

  if ! run_flake_update; then
    collect_stage_targets
    write_json_summary "update_failed" "flake update failed"
    return 1
  fi

  snapshot_root_inputs "$INPUTS_AFTER_TSV"
  snapshot_release_versions "$RELEASES_AFTER_TSV"
  compute_update_changes
  collect_stage_targets
  print_update_summary

  if ! run_lightweight_checks; then
    write_json_summary "checks_failed" "lightweight flake checks failed"
    return 1
  fi

  write_json_summary "ok" ""

  if [ "$PROMPTS_ENABLED" = "1" ]; then
    propose_next_steps
  fi
}

main "$@"
