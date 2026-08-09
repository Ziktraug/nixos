#!/usr/bin/env bash

# Shared release-hook behavior. Product-specific metadata, asset names and hash
# strategies deliberately stay in each module beside its release.json.

release_info() {
  printf '[INFO] %s\n' "$1"
}

release_warn() {
  printf '[WARN] %s\n' "$1"
}

release_validate_policy() {
  RELEASE_UPDATE_POLICY="${RELEASE_UPDATE_POLICY:-interactive}"

  case "$RELEASE_UPDATE_POLICY" in
    interactive|accept|keep)
      export RELEASE_UPDATE_POLICY
      ;;
    *)
      release_warn "Invalid release update policy '$RELEASE_UPDATE_POLICY'; expected interactive, accept, or keep"
      return 2
      ;;
  esac
}

release_require_commands() {
  local product="$1"
  shift

  local command
  for command in "$@"; do
    if ! command -v "$command" >/dev/null 2>&1; then
      release_warn "$command not found, skipping $product pre-update hook"
      return 1
    fi
  done
}

release_require_metadata() {
  local product="$1"
  local release_file="$2"

  if [ ! -f "$release_file" ]; then
    release_warn "release.json not found, skipping $product pre-update hook"
    return 1
  fi
}

release_module_enabled() {
  local product="$1"
  local option_path="$2"

  if [ -z "${HOST_FLAKE_PATH:-}" ] || [ -z "${HOST_KEY:-}" ]; then
    return 0
  fi

  local value
  if ! value="$(nix eval --json "${HOST_FLAKE_PATH}#nixosConfigurations.${HOST_KEY}.config.${option_path}" 2>/dev/null)"; then
    release_warn "Could not evaluate whether $product is enabled; skipping its pre-update hook"
    return 1
  fi

  if ! printf '%s\n' "$value" | jq -e 'type == "boolean" and . == true' >/dev/null; then
    return 1
  fi
}

release_policy_keeps_pinned() {
  local product="$1"
  local current_tag="$2"

  if [ "$RELEASE_UPDATE_POLICY" != keep ]; then
    return 1
  fi

  release_info "Keeping pinned $product release at $current_tag"
  return 0
}

release_should_update() {
  local product="$1"
  local current_tag="$2"
  local latest_tag="$3"
  local prompt="$4"

  if [ -z "$current_tag" ] || [ -z "$latest_tag" ] || [ "$latest_tag" = null ] || [ "$current_tag" = "$latest_tag" ]; then
    return 1
  fi

  release_info "$product pinned: $current_tag"
  release_info "$product latest: $latest_tag"

  case "$RELEASE_UPDATE_POLICY" in
    accept)
      return 0
      ;;
    keep)
      release_info "Keeping pinned $product release at $current_tag"
      return 1
      ;;
    interactive)
      local reply
      while true; do
        if ! read -r -p "$prompt [Y/n] " reply; then
          release_info "No response received; keeping pinned $product release at $current_tag"
          return 1
        fi

        case "${reply:-y}" in
          y|Y|yes|YES|Yes)
            return 0
            ;;
          n|N|no|NO|No)
            release_info "Keeping pinned $product release at $current_tag"
            return 1
            ;;
          *)
            release_warn "Please answer yes or no"
            ;;
        esac
      done
      ;;
  esac
}
