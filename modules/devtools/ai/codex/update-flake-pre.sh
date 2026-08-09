#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090,SC1091
source "$SCRIPT_DIR/../../../../script/lib/release-hook-bootstrap.sh"
release_hook_bootstrap "Codex" "applications.devtools.ai.codex.enable"

current_tag="$(jq -r .tag "$RELEASE_FILE")"
release_policy_keeps_pinned "Codex" "$current_tag" && exit 0

release_require_commands "Codex" gh || exit 0
release_json="$(gh api repos/openai/codex/releases/latest)"
latest_tag="$(printf '%s' "$release_json" | jq -r .tag_name)"

if ! release_should_update "Codex" "$current_tag" "$latest_tag" "Update pinned Codex binary release first?"; then
  exit 0
fi

version="${latest_tag#rust-v}"

asset_digest() {
  local asset_name="$1"
  local digest
  digest="$(printf '%s' "$release_json" | jq -r --arg asset "$asset_name" '.assets[] | select(.name == $asset) | .digest // empty' | head -n1)"
  if [[ "$digest" != sha256:* ]]; then
    release_warn "Missing SHA-256 digest for $asset_name"
    exit 1
  fi
  nix hash convert --hash-algo sha256 --to sri "${digest#sha256:}"
}

x86_asset="codex-x86_64-unknown-linux-musl.tar.gz"
arm_asset="codex-aarch64-unknown-linux-musl.tar.gz"
x86_host_asset="codex-code-mode-host-x86_64-unknown-linux-musl.tar.gz"
arm_host_asset="codex-code-mode-host-aarch64-unknown-linux-musl.tar.gz"
x86_hash="$(asset_digest "$x86_asset")"
arm_hash="$(asset_digest "$arm_asset")"
x86_host_hash="$(asset_digest "$x86_host_asset")"
arm_host_hash="$(asset_digest "$arm_host_asset")"

tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT

jq -n \
  --arg version "$version" \
  --arg tag "$latest_tag" \
  --arg x86_asset "$x86_asset" \
  --arg x86_hash "$x86_hash" \
  --arg arm_asset "$arm_asset" \
  --arg arm_hash "$arm_hash" \
  --arg x86_host_asset "$x86_host_asset" \
  --arg x86_host_hash "$x86_host_hash" \
  --arg arm_host_asset "$arm_host_asset" \
  --arg arm_host_hash "$arm_host_hash" \
  '{
    version: $version,
    tag: $tag,
    assets: {
      "x86_64-linux": {
        file: $x86_asset,
        binary: "codex-x86_64-unknown-linux-musl",
        hash: $x86_hash,
        codeModeHost: {
          file: $x86_host_asset,
          binary: "codex-code-mode-host-x86_64-unknown-linux-musl",
          hash: $x86_host_hash
        }
      },
      "aarch64-linux": {
        file: $arm_asset,
        binary: "codex-aarch64-unknown-linux-musl",
        hash: $arm_hash,
        codeModeHost: {
          file: $arm_host_asset,
          binary: "codex-code-mode-host-aarch64-unknown-linux-musl",
          hash: $arm_host_hash
        }
      }
    }
  }' > "$tmp_file"

mv "$tmp_file" "$RELEASE_FILE"

release_info "Updated Codex metadata in ${RELEASE_FILE#"$PROJECT_ROOT"/}"
