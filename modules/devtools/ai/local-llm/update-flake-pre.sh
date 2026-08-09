#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090,SC1091
source "$SCRIPT_DIR/../../../../script/lib/release-hook-bootstrap.sh"
release_hook_bootstrap "Ollama" 'applications.devtools.ai."local-llm".enable'

current_tag="$(jq -r .tag "$RELEASE_FILE")"
release_policy_keeps_pinned "Ollama" "$current_tag" && exit 0

release_require_commands "Ollama" gh || exit 0
latest_tag="$(gh api repos/ollama/ollama/releases/latest --jq .tag_name)"

if ! release_should_update "Ollama" "$current_tag" "$latest_tag" "Update pinned Ollama release first? This downloads the Linux tarball once to compute its fixed-output hash."; then
  exit 0
fi

version="${latest_tag#v}"
x86_asset="ollama-linux-amd64.tar.zst"
x86_url="https://github.com/ollama/ollama/releases/download/${latest_tag}/${x86_asset}"
x86_hash="$(nix store prefetch-file --json --unpack "$x86_url" | jq -r .hash)"

tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT

jq -n \
  --arg version "$version" \
  --arg tag "$latest_tag" \
  --arg x86_asset "$x86_asset" \
  --arg x86_hash "$x86_hash" \
  '{
    version: $version,
    tag: $tag,
    assets: {
      "x86_64-linux": {
        file: $x86_asset,
        hash: $x86_hash
      }
    }
  }' > "$tmp_file"

mv "$tmp_file" "$RELEASE_FILE"

release_info "Updated Ollama metadata in ${RELEASE_FILE#"$PROJECT_ROOT"/}"
