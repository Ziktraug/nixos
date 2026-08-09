#!/usr/bin/env bash

# Shared launcher for module-local release hooks. The caller remains responsible
# only for product-specific release lookup, asset selection and metadata writes.

release_hook_bootstrap() {
  local product="$1"
  local option_path="$2"
  local caller_script="${BASH_SOURCE[1]}"

  SCRIPT_DIR="$(cd "$(dirname "$caller_script")" && pwd)"
  PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
  RELEASE_FILE="$SCRIPT_DIR/release.json"
  export HOST_FLAKE_PATH="${NIXOS_FLAKE_PATH:-}"
  export HOST_KEY="${NIXOS_HOST_KEY:-}"

  local release_lib="$PROJECT_ROOT/script/lib/release-update.sh"
  if [ ! -r "$release_lib" ]; then
    printf '[ERROR] Shared release update library not found at %s\n' "$release_lib" >&2
    exit 1
  fi

  # Resolved from the repository root at runtime.
  # shellcheck disable=SC1090,SC1091
  source "$release_lib"

  release_validate_policy
  release_require_commands "$product" jq nix || exit 0
  release_require_metadata "$product" "$RELEASE_FILE" || exit 0
  release_module_enabled "$product" "$option_path" || exit 0
}
