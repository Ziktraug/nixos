#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090,SC1091
source "$SCRIPT_DIR/../../../../script/lib/release-hook-bootstrap.sh"
release_hook_bootstrap "RTK" "applications.devtools.cli.rtk.enable"

current_tag="$(jq -r .tag "$RELEASE_FILE")"
release_policy_keeps_pinned "RTK" "$current_tag" && exit 0

release_require_commands "RTK" gh || exit 0
latest_tag="$(gh api repos/rtk-ai/rtk/releases/latest --jq .tag_name)"

if ! release_should_update "RTK" "$current_tag" "$latest_tag" "Update pinned RTK release first?"; then
  exit 0
fi

release_json="$(gh api "repos/rtk-ai/rtk/releases/tags/$latest_tag")"
version="${latest_tag#v}"

extract_asset_sha() {
  local asset_name="$1"
  local digest
  digest="$(printf '%s' "$release_json" | jq -r --arg asset "$asset_name" '.assets[] | select(.name == $asset) | .digest // empty' | head -n1)"

  case "$digest" in
    sha256:*)
      printf '%s\n' "${digest#sha256:}"
      ;;
    *)
      return 1
      ;;
  esac
}

x86_asset="rtk-x86_64-unknown-linux-musl.tar.gz"
arm_asset="rtk-aarch64-unknown-linux-gnu.tar.gz"

x86_sha="$(extract_asset_sha "$x86_asset")"
arm_sha="$(extract_asset_sha "$arm_asset")"

tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT

jq -n \
  --arg version "$version" \
  --arg tag "$latest_tag" \
  --arg x86_asset "$x86_asset" \
  --arg x86_sha "$x86_sha" \
  --arg arm_asset "$arm_asset" \
  --arg arm_sha "$arm_sha" \
  '{
    version: $version,
    tag: $tag,
    assets: {
      "x86_64-linux": {
        file: $x86_asset,
        sha256: $x86_sha
      },
      "aarch64-linux": {
        file: $arm_asset,
        sha256: $arm_sha
      }
    }
  }' > "$tmp_file"

mv "$tmp_file" "$RELEASE_FILE"

release_info "Updated RTK metadata in ${RELEASE_FILE#"$PROJECT_ROOT"/}"
