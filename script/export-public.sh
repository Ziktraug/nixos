#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Usage: %s --check-only\n' "${0##*/}" >&2
  printf '       %s --target <existing-public-checkout> [--revision <commit>]\n' "${0##*/}" >&2
  exit 2
}

fail() {
  printf '%s\n' "$1" >&2
  exit 2
}

paths_overlap() {
  local first=$1
  local second=$2

  case "$first/" in "$second/"*) return 0 ;; esac
  case "$second/" in "$first/"*) return 0 ;; esac
  return 1
}

mode=""
target_input=""
revision="HEAD"
revision_requested=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check-only)
      [ -z "$mode" ] || usage
      mode="check-only"
      shift
      ;;
    --target)
      [ -z "$mode" ] || usage
      [ "$#" -ge 2 ] || usage
      [ -n "$2" ] || usage
      mode="target"
      target_input=$2
      shift 2
      ;;
    --revision)
      [ "$#" -ge 2 ] || usage
      [ -n "$2" ] || usage
      [ "$revision_requested" -eq 0 ] || usage
      revision=$2
      revision_requested=1
      shift 2
      ;;
    *) usage ;;
  esac
done

[ -n "$mode" ] || usage
if [ "$mode" = "check-only" ] && [ "$revision_requested" -ne 0 ]; then
  usage
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if ! source_repo_input="$(git -C "$script_dir/.." rev-parse --show-toplevel 2>/dev/null)"; then
  fail 'Public export requires a Git source repository'
fi
if ! source_repo="$(realpath --canonicalize-existing -- "$source_repo_input" 2>/dev/null)"; then
  fail 'Public export could not resolve the source repository'
fi

safety_checker="$source_repo/script/check-public-safety.sh"
gitleaks_config="$source_repo/.gitleaks.toml"
denylist="$source_repo/private/publication/denylist.txt"

[ -x "$safety_checker" ] || fail 'Public export requires the safety checker'
[ -f "$gitleaks_config" ] || fail 'Public export requires a Gitleaks configuration'

if ! resolved_revision="$(
  git -C "$source_repo" rev-parse --verify --end-of-options "$revision^{commit}" 2>/dev/null
)"; then
  fail 'Public export requires a valid commit revision'
fi

target=""
if [ "$mode" = "target" ]; then
  if ! source_status="$(
    git -C "$source_repo" status --porcelain=v1 --untracked-files=normal 2>/dev/null
  )"; then
    fail 'Public export could not inspect the source worktree'
  fi
  if [ -n "$source_status" ]; then
    fail 'Public export requires a clean source worktree'
  fi

  if ! target_lexical="$(realpath --canonicalize-missing --no-symlinks -- "$target_input" 2>/dev/null)"; then
    fail 'Public export refused an unresolved target'
  fi
  if ! target="$(realpath --canonicalize-existing -- "$target_input" 2>/dev/null)"; then
    fail 'Public export refused an unresolved target'
  fi
  if [ ! -d "$target" ] || [ "$target" = / ] || [ "$target_lexical" != "$target" ]; then
    fail 'Public export refused an unsafe target'
  fi
  if paths_overlap "$target" "$source_repo"; then
    fail 'Public export refused a target overlapping the source repository'
  fi
  if { [ ! -d "$target/.git" ] && [ ! -f "$target/.git" ]; } || [ -L "$target/.git" ]; then
    fail 'Public export requires a non-symlink Git target'
  fi
  if ! target_git_root_input="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)"; then
    fail 'Public export requires a valid Git target'
  fi
  if ! target_git_root="$(realpath --canonicalize-existing -- "$target_git_root_input" 2>/dev/null)"; then
    fail 'Public export could not resolve the target repository'
  fi
  if [ "$target_git_root" != "$target" ]; then
    fail 'Public export target must be the Git worktree root'
  fi
  if ! target_status="$(
    git -C "$target" status --porcelain=v1 --untracked-files=normal 2>/dev/null
  )"; then
    fail 'Public export could not inspect the target worktree'
  fi
  if [ -n "$target_status" ]; then
    fail 'Public export requires a clean target worktree'
  fi
fi

archive_dir="$(mktemp -d)"
readonly archive_dir
if ! archive_tree="$(realpath --canonicalize-existing -- "$archive_dir" 2>/dev/null)"; then
  fail 'Public export could not resolve its temporary directory'
fi
readonly archive_tree

cleanup() {
  rm -rf -- "$archive_dir"
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if paths_overlap "$archive_tree" "$source_repo"; then
  fail 'Public export refused a temporary directory overlapping the source repository'
fi
if [ "$mode" = "target" ] && paths_overlap "$archive_tree" "$target"; then
  fail 'Public export refused a temporary directory overlapping the target repository'
fi

git -C "$source_repo" archive --format=tar "$resolved_revision" |
  tar -x -C "$archive_tree"

safety_check() {
  local tree=$1
  local -a arguments=("$tree")

  if [ -e "$denylist" ] || [ -L "$denylist" ]; then
    arguments+=(--denylist "$denylist")
  fi

  PUBLICATION_SOURCE_REPO="$source_repo" bash "$safety_checker" "${arguments[@]}"
}

resolve_executable() {
  local candidate=$1
  local resolved

  if ! resolved="$(command -v -- "$candidate" 2>/dev/null)" || [ ! -x "$resolved" ]; then
    return 1
  fi
  printf '%s\n' "$resolved"
}

gitleaks_scan() {
  local tree=$1
  local gitleaks_override

  if [ -n "${GITLEAKS_BIN:-}" ]; then
    if ! gitleaks_override="$(resolve_executable "$GITLEAKS_BIN")"; then
      fail 'Public export requires an executable GITLEAKS_BIN override'
    fi
    "$gitleaks_override" dir --redact=100 --config "$gitleaks_config" "$tree"
  else
    nix shell "$source_repo#gitleaks" -c \
      gitleaks dir --redact=100 --config "$gitleaks_config" "$tree"
  fi
}

safety_check "$archive_tree"
gitleaks_scan "$archive_tree"

if [ "$mode" = "check-only" ]; then
  printf 'Public export checks passed\n'
  exit 0
fi

if [ -n "${RSYNC_BIN:-}" ]; then
  if ! rsync_command="$(resolve_executable "$RSYNC_BIN")"; then
    fail 'Public export requires an executable RSYNC_BIN override'
  fi
else
  if ! rsync_command="$(resolve_executable rsync)"; then
    fail 'Public export requires rsync'
  fi
fi

"$rsync_command" --archive --delete --exclude '/.git' -- "$archive_tree/" "$target/"

safety_check "$target"
gitleaks_scan "$target"

printf 'Public export completed and verified\n'
