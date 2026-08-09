#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090,SC1091
source "$SCRIPT_DIR/../../../../script/lib/release-hook-bootstrap.sh"
release_hook_bootstrap "Zed" "applications.devtools.ide.zed.enable"

current_tag="$(jq -r .tag "$RELEASE_FILE")"
release_policy_keeps_pinned "Zed" "$current_tag" && exit 0

release_require_commands "Zed" curl gh tar || exit 0
latest_tag="$(gh api repos/zed-industries/zed/releases/latest --jq .tag_name)"

if ! release_should_update "Zed" "$current_tag" "$latest_tag" "Update pinned Zed binary release first?"; then
  exit 0
fi

version="${latest_tag#v}"
x86_asset="zed-linux-x86_64.tar.gz"
arm_asset="zed-linux-aarch64.tar.gz"
x86_url="https://github.com/zed-industries/zed/releases/download/${latest_tag}/${x86_asset}"
arm_url="https://github.com/zed-industries/zed/releases/download/${latest_tag}/${arm_asset}"

work_dir=""
tmp_file=""

cleanup() {
  [ -z "$work_dir" ] || rm -rf "$work_dir"
  [ -z "$tmp_file" ] || rm -f "$tmp_file"
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

work_dir="$(mktemp -d)"

hash_fetchzip_source() {
  local name="$1"
  local url="$2"
  local archive
  local unpack_dir
  local hash

  archive="$work_dir/$name.tar.gz"
  unpack_dir="$work_dir/$name"
  if ! mkdir -p "$unpack_dir"; then
    return 1
  fi

  if ! curl -L --fail --output "$archive" "$url"; then
    return 1
  fi
  if ! tar -xzf "$archive" -C "$unpack_dir"; then
    return 1
  fi
  if ! hash="$(nix hash path "$unpack_dir")"; then
    return 1
  fi

  printf '%s\n' "$hash"
}

if ! x86_hash="$(hash_fetchzip_source x86_64 "$x86_url")"; then
  release_warn "Failed to download, unpack, or hash $x86_asset"
  exit 1
fi
if ! arm_hash="$(hash_fetchzip_source aarch64 "$arm_url")"; then
  release_warn "Failed to download, unpack, or hash $arm_asset"
  exit 1
fi

tmp_file="$(mktemp "${RELEASE_FILE}.tmp.XXXXXX")"

jq -n \
  --arg version "$version" \
  --arg tag "$latest_tag" \
  --arg x86_asset "$x86_asset" \
  --arg x86_hash "$x86_hash" \
  --arg arm_asset "$arm_asset" \
  --arg arm_hash "$arm_hash" \
  '{
    version: $version,
    tag: $tag,
    assets: {
      "x86_64-linux": {
        file: $x86_asset,
        hash: $x86_hash
      },
      "aarch64-linux": {
        file: $arm_asset,
        hash: $arm_hash
      }
    }
  }' > "$tmp_file"

mv "$tmp_file" "$RELEASE_FILE"
tmp_file=""

release_info "Updated Zed metadata in ${RELEASE_FILE#"$PROJECT_ROOT"/}"
