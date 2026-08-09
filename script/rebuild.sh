#!/usr/bin/env bash

set -euo pipefail

NIXOS_REPO="${NIXOS_REPO:-$HOME/Projects/Github/nixos}"
HOSTNAME_SHORT="$(hostname -s)"
NIXOS_FLAKE_PATH="${NIXOS_FLAKE_PATH:-$NIXOS_REPO/hosts/$HOSTNAME_SHORT}"
HOST_KEY="${NIXOS_HOST_KEY:-$HOSTNAME_SHORT}"
CURRENT_SYSTEM_LINK="${NIXOS_CURRENT_SYSTEM:-/run/current-system}"
SYSTEM_PROFILE="${NIXOS_SYSTEM_PROFILE:-/nix/var/nix/profiles/system}"
JSON_SUMMARY=""
ACTIVATION_UI_FD=""
ACTIVATION_POLICY="auto"
PROMPTS_ENABLED=1

while [ $# -gt 0 ]; do
  case "$1" in
    --no-prompts)
      PROMPTS_ENABLED=0
      shift
      ;;
    --activation-policy)
      ACTIVATION_POLICY="${2:-}"
      [ -n "$ACTIVATION_POLICY" ] || {
        printf 'Error: --activation-policy requires a value\n' >&2
        exit 1
      }
      shift 2
      ;;
    --activation-policy=*)
      ACTIVATION_POLICY="${1#*=}"
      shift
      ;;
    --json-summary)
      JSON_SUMMARY="${2:-}"
      [ -n "$JSON_SUMMARY" ] || {
        printf 'Error: --json-summary requires a path\n' >&2
        exit 1
      }
      shift 2
      ;;
    --activation-ui-fd)
      ACTIVATION_UI_FD="${2:-}"
      [ -n "$ACTIVATION_UI_FD" ] || {
        printf 'Error: --activation-ui-fd requires a file descriptor\n' >&2
        exit 1
      }
      shift 2
      ;;
    --activation-ui-fd=*)
      ACTIVATION_UI_FD="${1#*=}"
      shift
      ;;
    *)
      printf 'Error: unknown option: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

case "$ACTIVATION_POLICY" in
  auto|boot|switch) ;;
  *)
    printf 'Error: activation policy must be one of: auto, boot, switch\n' >&2
    exit 1
    ;;
esac

if [ -n "$ACTIVATION_UI_FD" ] && ! [[ "$ACTIVATION_UI_FD" =~ ^[0-9]+$ ]]; then
  printf 'Error: --activation-ui-fd must be a numeric file descriptor\n' >&2
  exit 1
fi

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  COLOR_RESET=$'\033[0m'
  COLOR_BOLD=$'\033[1m'
  COLOR_DIM=$'\033[2m'
  COLOR_RED=$'\033[31m'
  COLOR_GREEN=$'\033[32m'
  COLOR_YELLOW=$'\033[33m'
  COLOR_BLUE=$'\033[34m'
  COLOR_CYAN=$'\033[36m'
else
  COLOR_RESET=''
  COLOR_BOLD=''
  COLOR_DIM=''
  COLOR_RED=''
  COLOR_GREEN=''
  COLOR_YELLOW=''
  COLOR_BLUE=''
  COLOR_CYAN=''
fi

LOGS_DIR="$NIXOS_REPO/logs"
mkdir -p "$LOGS_DIR"
RECAP_FILE="$LOGS_DIR/rebuild-$(date +%Y%m%d-%H%M%S).log"

section() {
  printf '%s%s%s\n' "$COLOR_BOLD$COLOR_BLUE" "$1" "$COLOR_RESET"
}

info_line() {
  local label="$1"
  local value="$2"
  printf '  %s%-10s%s %s\n' "$COLOR_DIM" "$label" "$COLOR_RESET" "$value"
}

warn() {
  printf '%s[WARN]%s %s\n' "$COLOR_YELLOW" "$COLOR_RESET" "$1"
}

confirm_live_activation() {
  local default_answer="$1"
  local prompt suffix reply

  if [ "$default_answer" = yes ]; then
    prompt="Apply the installed generation now?"
    suffix='[Y/n]'
  else
    prompt="Switch now anyway?"
    suffix='[y/N]'
  fi

  if [ "$PROMPTS_ENABLED" = 0 ]; then
    return 1
  fi

  if [ -n "$ACTIVATION_UI_FD" ]; then
    printf '%s %s ' "$prompt" "$suffix" >&"$ACTIVATION_UI_FD"
    if { : < /dev/tty; } 2>/dev/null; then
      if ! IFS= read -r reply < /dev/tty; then
        return 1
      fi
    elif ! IFS= read -r reply; then
      return 1
    fi
  elif { : < /dev/tty; } 2>/dev/null; then
    printf '%s %s ' "$prompt" "$suffix" > /dev/tty
    if ! IFS= read -r reply < /dev/tty; then
      return 1
    fi
  else
    printf '%s %s ' "$prompt" "$suffix" >&2
    if ! IFS= read -r reply; then
      return 1
    fi
  fi

  if [ -z "$reply" ]; then
    [ "$default_answer" = yes ]
    return
  fi

  [[ "$reply" =~ ^[Yy]$ ]]
}

add_activation_risk() {
  local label="$1"
  local pattern="$2"
  local scan="$3"

  if printf '%s\n' "$scan" | grep -Eqi "$pattern"; then
    ACTIVATION_RISK_ITEMS+=("$label")
  fi
}

classify_activation_risk() {
  local preview="$1"
  local scan
  scan="$(printf '%s\n' "$preview" | grep -Eiv 'NOT restarting' || true)"

  ACTIVATION_RISK_ITEMS=()
  add_activation_risk "NetworkManager" 'NetworkManager' "$scan"
  add_activation_risk "GNOME session" 'gnome-session|graphical-session' "$scan"
  add_activation_risk "display manager" 'display-manager|gdm\.service' "$scan"
  add_activation_risk "login sessions" 'systemd-logind|user@[0-9]+\.service' "$scan"
  add_activation_risk "user D-Bus" '(^|[^[:alnum:]])dbus([^[:alnum:]]|$)|D-Bus User' "$scan"

  if [ ${#ACTIVATION_RISK_ITEMS[@]} -gt 0 ]; then
    ACTIVATION_RISK="high"
  else
    ACTIVATION_RISK="low"
  fi
}

print_activation_preview() {
  echo
  section "========== Activation Preview =========="
  info_line "Installed" "$NEW_GENERATION_LABEL"

  if [ "$ACTIVATION_PREVIEW_OK" != true ]; then
    ACTIVATION_RISK="unknown"
    warn "Could not preview live activation safely. The generation remains installed for reboot."
    return
  fi

  if [ "$ACTIVATION_RISK" = high ]; then
    printf '%s⚠ Risky live activation detected%s\n' "$COLOR_BOLD$COLOR_RED" "$COLOR_RESET"
    print_items "Session-critical changes" "$COLOR_YELLOW" 0 "${ACTIVATION_RISK_ITEMS[@]}"
    warn "Switching now may terminate GNOME or interrupt networking."
    printf '  %sThe update is already installed and will activate on reboot.%s\n' "$COLOR_DIM" "$COLOR_RESET"
  else
    printf '  %sNo session-critical service detected.%s\n' "$COLOR_GREEN" "$COLOR_RESET"
  fi
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

system_generation_label() {
  local system_path="$1"
  local base
  base="$(basename "$system_path")"
  printf '%s\n' "${base#*-nixos-system-"${HOST_KEY}"-}"
}

print_items() {
  local title="$1"
  local color="$2"
  local limit="$3"
  shift 3
  local items=("$@")
  local total=${#items[@]}

  [ "$total" -eq 0 ] && return 0

  printf '  %s%s%s\n' "$COLOR_BOLD$color" "$title" "$COLOR_RESET"

  local index
  local shown=0
  if [ "$limit" -le 0 ]; then
    limit=$total
  fi

  for ((index = 0; index < total && index < limit; index++)); do
    printf '    - %s\n' "${items[$index]}"
    shown=$((shown + 1))
  done

  if [ "$shown" -lt "$total" ]; then
    printf '    %s... %s more%s\n' "$COLOR_DIM" "$((total - shown))" "$COLOR_RESET"
  fi
}

write_json_summary() {
  [ -n "$JSON_SUMMARY" ] || return 0
  mkdir -p "$(dirname "$JSON_SUMMARY")"

  local status="ok"
  if [ "$REBUILD_EXIT" -ne 0 ]; then
    status="failed"
  fi

  local system_changed="false"
  if [ -n "$OLD_SYSTEM" ] && [ -n "$NEW_SYSTEM" ] && [ "$OLD_SYSTEM" != "$NEW_SYSTEM" ]; then
    system_changed="true"
  fi

  local package_added_lines package_removed_lines package_updated_lines dotfile_summary_lines activation_risk_lines
  package_added_lines="$(printf '%s\n' "${PKG_ADDED_LINES[@]}")"
  package_removed_lines="$(printf '%s\n' "${PKG_REMOVED_LINES[@]}")"
  package_updated_lines="$(printf '%s\n' "${PKG_UPDATED_LINES[@]}")"
  dotfile_summary_lines="$(printf '%s\n' "${DOTFILE_SUMMARY_LINES[@]}")"
  activation_risk_lines="$(printf '%s\n' "${ACTIVATION_RISK_ITEMS[@]}")"

  jq -n \
    --arg status "$status" \
    --argjson exitCode "$REBUILD_EXIT" \
    --arg repo "$NIXOS_REPO" \
    --arg host "$HOST_KEY" \
    --arg flakePath "$NIXOS_FLAKE_PATH" \
    --arg recapFile "$RECAP_FILE" \
    --arg before "$OLD_GENERATION_LABEL" \
    --arg after "$NEW_GENERATION_LABEL" \
    --argjson systemChanged "$system_changed" \
    --arg activationPolicy "$ACTIVATION_POLICY" \
    --arg activationRisk "$ACTIVATION_RISK" \
    --argjson activationInstalled "$ACTIVATION_INSTALLED" \
    --argjson activationActivated "$ACTIVATION_ACTIVATED" \
    --argjson activationPreviewSucceeded "$ACTIVATION_PREVIEW_OK" \
    --argjson rebootRequired "$REBOOT_REQUIRED" \
    --arg installedSystem "$INSTALLED_SYSTEM" \
    --argjson packageAdded "$PKG_ADDED" \
    --argjson packageRemoved "$PKG_REMOVED" \
    --argjson packageUpdated "$PKG_UPDATED" \
    --argjson dotfilesChanged "$UPDATED_COUNT" \
    --arg packageAddedLines "$package_added_lines" \
    --arg packageRemovedLines "$package_removed_lines" \
    --arg packageUpdatedLines "$package_updated_lines" \
    --arg dotfileSummaryLines "$dotfile_summary_lines" \
    --arg activationRiskLines "$activation_risk_lines" \
    '
    def lines($value): $value | split("\n") | map(select(length > 0));
    {
      schemaVersion: 1,
      operation: "rebuild",
      status: $status,
      exitCode: $exitCode,
      repo: $repo,
      host: $host,
      flakePath: $flakePath,
      recapFile: $recapFile,
      system: {
        changed: $systemChanged,
        before: (if $before == "" then null else $before end),
        after: (if $after == "" then null else $after end)
      },
      activation: {
        policy: $activationPolicy,
        installed: $activationInstalled,
        activated: $activationActivated,
        previewSucceeded: $activationPreviewSucceeded,
        risk: $activationRisk,
        riskItems: lines($activationRiskLines),
        rebootRequired: $rebootRequired,
        installedSystem: (if $installedSystem == "" then null else $installedSystem end)
      },
      packages: {
        added: $packageAdded,
        removed: $packageRemoved,
        updated: $packageUpdated,
        addedItems: lines($packageAddedLines),
        removedItems: lines($packageRemovedLines),
        updatedItems: lines($packageUpdatedLines)
      },
      dotfiles: {
        changed: $dotfilesChanged,
        items: lines($dotfileSummaryLines)
      }
    }
    ' > "$JSON_SUMMARY"
}

if ! command -v nix >/dev/null 2>&1; then
  echo "Error: nix command not found"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required for rebuild recap"
  exit 1
fi

if [ ! -f "$NIXOS_FLAKE_PATH/flake.nix" ]; then
  echo "Error: host flake not found at $NIXOS_FLAKE_PATH/flake.nix"
  exit 1
fi

echo "Preparing rebuild recap data..."
echo "Using host flake: $NIXOS_FLAKE_PATH"
echo "Using host config: $HOST_KEY"

DOTFILES_JSON="$(nix eval --json "${NIXOS_FLAKE_PATH}#nixosConfigurations.${HOST_KEY}.config.dotfiles.modules")"
DOTFILES_HOME="$(
  nix eval --raw \
    --apply 'config: config.users.users.${config.dotfiles.user}.home' \
    "${NIXOS_FLAKE_PATH}#nixosConfigurations.${HOST_KEY}.config"
)"

MAPPINGS_TSV="$(mktemp)"
PRE_STATE_TSV="$(mktemp)"
POST_STATE_TSV="$(mktemp)"
trap 'rm -f "$MAPPINGS_TSV" "$PRE_STATE_TSV" "$POST_STATE_TSV"' EXIT

printf '%s\n' "$DOTFILES_JSON" | jq -r '
  to_entries[]
  | select(.value.enable == true)
  | .key as $module
  | .value.sourceDir as $sourceDir
  | .value.mappings
  | to_entries[]
  | [$module, .key, $sourceDir, .value.source, .value.target]
  | @tsv
' > "$MAPPINGS_TSV"

snapshot_dotfiles_state() {
  local output_file="$1"
  : > "$output_file"

  while IFS=$'\t' read -r module mapping _source_dir source target; do
    [ -z "${module:-}" ] && continue
    local target_path="$target"
    local state_type="missing"
    local fingerprint="-"

    case "$target_path" in
      '$HOME') target_path="$DOTFILES_HOME" ;;
      '$HOME/'*) target_path="$DOTFILES_HOME/${target_path#\$HOME/}" ;;
    esac

    if [ -L "$target_path" ]; then
      state_type="symlink"
      if ! fingerprint="$(readlink -z -- "$target_path" | sha256sum | cut -d' ' -f1)"; then
        fingerprint="unreadable"
      fi
    elif [ -f "$target_path" ]; then
      state_type="file"
      if ! fingerprint="$(sha256sum -- "$target_path" | cut -d' ' -f1)"; then
        fingerprint="unreadable"
      fi
    elif [ -d "$target_path" ]; then
      state_type="directory"
    elif [ -e "$target_path" ]; then
      state_type="other"
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$module" "$mapping" "$source" "$target_path" "$state_type" "$fingerprint" >> "$output_file"
  done < "$MAPPINGS_TSV"
}

snapshot_dotfiles_state "$PRE_STATE_TSV"

OLD_SYSTEM="$(readlink -f "$CURRENT_SYSTEM_LINK" 2>/dev/null || true)"
INSTALLED_SYSTEM=""
NEW_SYSTEM="$OLD_SYSTEM"
ACTIVE_SYSTEM="$OLD_SYSTEM"
REBUILD_EXIT=0
ACTIVATION_INSTALLED=false
ACTIVATION_ACTIVATED=false
ACTIVATION_PREVIEW_OK=false
ACTIVATION_RISK="not-run"
REBOOT_REQUIRED=false
ACTIVATION_PREVIEW=""
declare -a ACTIVATION_RISK_ITEMS=()

PKG_DIFF_OUTPUT=""
PKG_ADDED=0; PKG_REMOVED=0; PKG_UPDATED=0
declare -a PKG_ADDED_LINES=() PKG_REMOVED_LINES=() PKG_UPDATED_LINES=()
OLD_GENERATION_LABEL=""
NEW_GENERATION_LABEL=""
[ -n "$OLD_SYSTEM" ] && OLD_GENERATION_LABEL="$(system_generation_label "$OLD_SYSTEM")"

echo ""
section "========== Stage 1: Build and Install =========="
echo "Running nixos-rebuild boot..."
set +e
sudo nixos-rebuild boot --flake "${NIXOS_FLAKE_PATH}#${HOST_KEY}"
REBUILD_EXIT=$?
set -e

if [ "$REBUILD_EXIT" -eq 0 ]; then
  INSTALLED_SYSTEM="$(readlink -f "$SYSTEM_PROFILE" 2>/dev/null || true)"
  if [ -z "$INSTALLED_SYSTEM" ]; then
    warn "The system profile did not resolve after nixos-rebuild boot."
    REBUILD_EXIT=1
  else
    ACTIVATION_INSTALLED=true
    NEW_SYSTEM="$INSTALLED_SYSTEM"
    NEW_GENERATION_LABEL="$(system_generation_label "$NEW_SYSTEM")"

    set +e
    ACTIVATION_PREVIEW="$(sudo "$INSTALLED_SYSTEM/bin/switch-to-configuration" dry-activate 2>&1)"
    preview_exit=$?
    set -e
    if [ "$preview_exit" -eq 0 ]; then
      ACTIVATION_PREVIEW_OK=true
      classify_activation_risk "$ACTIVATION_PREVIEW"
    else
      ACTIVATION_RISK="unknown"
    fi

    if [ -n "$ACTIVATION_UI_FD" ]; then
      if ! { : >&"$ACTIVATION_UI_FD"; } 2>/dev/null; then
        printf 'Error: activation UI file descriptor %s is not open\n' "$ACTIVATION_UI_FD" >&2
        exit 1
      fi
      print_activation_preview >&"$ACTIVATION_UI_FD"
    else
      print_activation_preview
    fi

    SHOULD_SWITCH=false
    case "$ACTIVATION_POLICY" in
      switch)
        SHOULD_SWITCH=true
        ;;
      boot)
        ;;
      auto)
        if [ "$ACTIVATION_PREVIEW_OK" = true ]; then
          if [ "$ACTIVATION_RISK" = high ]; then
            confirm_live_activation no && SHOULD_SWITCH=true
          else
            confirm_live_activation yes && SHOULD_SWITCH=true
          fi
        fi
        ;;
    esac

    if [ "$SHOULD_SWITCH" = true ]; then
      echo
      section "========== Stage 2: Live Activation =========="
      set +e
      sudo "$INSTALLED_SYSTEM/bin/switch-to-configuration" switch
      REBUILD_EXIT=$?
      set -e
    else
      echo
      info_line "Activation" "deferred until reboot"
    fi
  fi
fi

ACTIVE_SYSTEM="$(readlink -f "$CURRENT_SYSTEM_LINK" 2>/dev/null || true)"
if [ "$ACTIVATION_INSTALLED" = true ] && [ -n "$ACTIVE_SYSTEM" ] && [ "$ACTIVE_SYSTEM" = "$INSTALLED_SYSTEM" ]; then
  ACTIVATION_ACTIVATED=true
fi
if [ "$ACTIVATION_INSTALLED" = true ] && [ "$ACTIVATION_ACTIVATED" != true ]; then
  REBOOT_REQUIRED=true
fi

snapshot_dotfiles_state "$POST_STATE_TSV"

if [ -n "$OLD_SYSTEM" ] && [ -n "$NEW_SYSTEM" ] && [ "$OLD_SYSTEM" != "$NEW_SYSTEM" ]; then
  PKG_DIFF_TMP="$(mktemp)"
  trap 'rm -f "$MAPPINGS_TSV" "$PRE_STATE_TSV" "$POST_STATE_TSV" "$PKG_DIFF_TMP"' EXIT
  nix store diff-closures "$OLD_SYSTEM" "$NEW_SYSTEM" > "$PKG_DIFF_TMP" 2>&1 || true
  PKG_ADDED="$(grep -c ': ε →' "$PKG_DIFF_TMP" || true)"
  PKG_REMOVED="$(grep -c '→ ε,' "$PKG_DIFF_TMP" || true)"
  PKG_UPDATED="$(awk '/ → / && $0 !~ /: ε →/ && $0 !~ /→ ε,/ { count++ } END { print count + 0 }' "$PKG_DIFF_TMP")"
  PKG_DIFF_OUTPUT="$(cat "$PKG_DIFF_TMP")"

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in
      *": "*" → "*) ;;
      *) continue ;;
    esac

    pkg_name="$(trim "${line%%:*}")"
    change_part="${line#*: }"
    change_part="${change_part%%,*}"
    old_version="$(trim "${change_part%% → *}")"
    new_version="$(trim "${change_part#* → }")"

    if [ "$old_version" = "ε" ]; then
      PKG_ADDED_LINES+=("$pkg_name (new) $new_version")
    elif [ "$new_version" = "ε" ]; then
      PKG_REMOVED_LINES+=("$pkg_name (old) $old_version")
    else
      PKG_UPDATED_LINES+=("$pkg_name $old_version -> $new_version")
    fi
  done < "$PKG_DIFF_TMP"
fi

declare -A PRE_TYPE PRE_FINGERPRINT

while IFS=$'\t' read -r module mapping source target state_type fingerprint; do
  key="$module|$mapping"
  PRE_TYPE["$key"]="$state_type"
  PRE_FINGERPRINT["$key"]="$fingerprint"
done < "$PRE_STATE_TSV"

UPDATED_COUNT=0
DOTFILE_LINES=""
declare -a DOTFILE_SUMMARY_LINES=()

while IFS=$'\t' read -r module mapping source target state_type fingerprint; do
  key="$module|$mapping"
  prev_type="${PRE_TYPE[$key]:-missing}"
  prev_fingerprint="${PRE_FINGERPRINT[$key]:--}"

  if [ "$state_type" != "$prev_type" ] || [ "$fingerprint" != "$prev_fingerprint" ]; then
    UPDATED_COUNT=$((UPDATED_COUNT + 1))
    DOTFILE_LINES+="- [$module] $source\n  target: $target\n  state:  $prev_type -> $state_type\n"
    DOTFILE_SUMMARY_LINES+=("[$module] $source")
  fi
done < "$POST_STATE_TSV"

{
  echo "========== Rebuild Recap =========="
  echo "Date: $(date)"
  if [ -n "$OLD_GENERATION_LABEL" ] && [ -n "$NEW_GENERATION_LABEL" ]; then
    echo "Generation: $OLD_GENERATION_LABEL -> $NEW_GENERATION_LABEL"
    echo ""
  fi
  echo "--- Activation ---"
  echo "  policy: $ACTIVATION_POLICY"
  echo "  installed: $ACTIVATION_INSTALLED"
  echo "  activated: $ACTIVATION_ACTIVATED"
  echo "  risk: $ACTIVATION_RISK"
  echo "  reboot required: $REBOOT_REQUIRED"
  if [ ${#ACTIVATION_RISK_ITEMS[@]} -gt 0 ]; then
    printf '  sensitive: %s\n' "${ACTIVATION_RISK_ITEMS[@]}"
  fi
  echo ""
  echo "--- Package changes (+added -removed ~updated) ---"
  echo "  +${PKG_ADDED}  -${PKG_REMOVED}  ~${PKG_UPDATED}"
  echo ""
  if [ ${#PKG_UPDATED_LINES[@]} -gt 0 ]; then
    echo "Updated packages:"
    printf '  - %s\n' "${PKG_UPDATED_LINES[@]}"
    echo ""
  fi
  if [ ${#PKG_ADDED_LINES[@]} -gt 0 ]; then
    echo "Added packages:"
    printf '  - %s\n' "${PKG_ADDED_LINES[@]}"
    echo ""
  fi
  if [ ${#PKG_REMOVED_LINES[@]} -gt 0 ]; then
    echo "Removed packages:"
    printf '  - %s\n' "${PKG_REMOVED_LINES[@]}"
    echo ""
  fi
  echo "Raw diff-closures output:"
  if [ -n "$PKG_DIFF_OUTPUT" ]; then
    echo "$PKG_DIFF_OUTPUT"
  else
    echo "No system closure change detected."
  fi
  echo ""
  echo "--- Dotfile changes ---"
  if [ "$UPDATED_COUNT" -gt 0 ]; then
    printf '%b' "$DOTFILE_LINES"
  else
    echo "No managed dotfiles changed during this rebuild."
  fi
  echo ""
  echo "Recap done."
} > "$RECAP_FILE" 2>&1

echo ""
section "========== Rebuild Summary =========="

if [ -n "$OLD_GENERATION_LABEL" ] && [ -n "$NEW_GENERATION_LABEL" ]; then
  info_line "Generation" "$COLOR_CYAN$OLD_GENERATION_LABEL$COLOR_RESET -> $COLOR_GREEN$NEW_GENERATION_LABEL$COLOR_RESET"
fi

if [ "$ACTIVATION_ACTIVATED" = true ]; then
  info_line "Activation" "$COLOR_GREEN active now$COLOR_RESET"
elif [ "$REBOOT_REQUIRED" = true ]; then
  info_line "Activation" "$COLOR_YELLOW deferred; reboot required$COLOR_RESET"
else
  info_line "Activation" "not installed"
fi
info_line "Risk" "$ACTIVATION_RISK"
info_line "Packages" "$COLOR_GREEN+${PKG_ADDED}$COLOR_RESET added   $COLOR_YELLOW-${PKG_REMOVED}$COLOR_RESET removed   $COLOR_CYAN~${PKG_UPDATED}$COLOR_RESET updated"
info_line "Dotfiles" "$UPDATED_COUNT changed"
echo ""

print_items "Updated packages" "$COLOR_CYAN" 0 "${PKG_UPDATED_LINES[@]}"
print_items "Added packages" "$COLOR_GREEN" 0 "${PKG_ADDED_LINES[@]}"
print_items "Removed packages" "$COLOR_YELLOW" 0 "${PKG_REMOVED_LINES[@]}"
print_items "Dotfile changes" "$COLOR_BLUE" 0 "${DOTFILE_SUMMARY_LINES[@]}"

if [ ${#PKG_UPDATED_LINES[@]} -eq 0 ] && [ ${#PKG_ADDED_LINES[@]} -eq 0 ] && [ ${#PKG_REMOVED_LINES[@]} -eq 0 ] && [ ${#DOTFILE_SUMMARY_LINES[@]} -eq 0 ]; then
  printf '  %sNo package or dotfile changes detected.%s\n' "$COLOR_DIM" "$COLOR_RESET"
fi

echo ""
info_line "Recap" "$RECAP_FILE"

write_json_summary

exit "$REBUILD_EXIT"
