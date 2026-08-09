#!/usr/bin/env bash

set -euo pipefail

repo_root="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
script="$repo_root/modules/ui/waybar/scripts/solaar-headset.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

export XDG_RUNTIME_DIR="$fixture/runtime"
export HEADSET_CACHE_MAX_AGE_SECONDS=300
cache_dir="$XDG_RUNTIME_DIR/logitech-headset-battery"
cache_file="$cache_dir/percent"
mkdir -p "$cache_dir"

printf '42\n' > "$cache_file"
fresh_output="$(bash "$script")"
grep -q '"text":"42"' <<< "$fresh_output"

touch -d '@0' "$cache_file"
stale_output="$(bash "$script")"
grep -q '"text":"N/A"' <<< "$stale_output"

printf 'invalid\n' > "$cache_file"
invalid_output="$(bash "$script")"
grep -q '"text":"N/A"' <<< "$invalid_output"
