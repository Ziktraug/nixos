#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DISK_HEALTH_SCRIPT="${DISK_HEALTH_SCRIPT:-$SCRIPT_DIR/disk-health-check.sh}"
ASSUME_YES=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() {
    echo
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}$1${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

usage() {
    cat <<'EOF'
Usage: maintenance.sh [MODE] [--yes]

Modes:
  --diagnose       Read-only diagnostics; never deletes files or invokes sudo
  --cleanup        User cleanup; deletes announced paths and optimizes the Nix store
  --system-cleanup Privileged cleanup of old generations and journal logs
  --update         Update the active host flake inputs
  --help           Show this help

With no mode, an interactive menu is displayed. --yes only confirms an explicitly
selected state-changing mode; it never selects or broadens an operation.
EOF
}

confirm() {
    local prompt=$1
    if [ "$ASSUME_YES" -eq 1 ]; then
        return 0
    fi
    read -r -p "$prompt [y/N] " response
    [[ "${response:-n}" =~ ^[Yy]$ ]]
}

check_disk_space() {
    log_info "Current disk usage:"
    df -h / /boot 2>/dev/null || df -h /

    if mountpoint -q /boot 2>/dev/null; then
        local efi_use
        efi_use=$(df --output=pcent /boot 2>/dev/null | tail -n 1 | tr -dc '0-9')
        if [ -n "$efi_use" ] && [ "$efi_use" -ge 85 ]; then
            log_warning "EFI partition usage is high (${efi_use}% used)"
        fi
    fi
}

run_diagnostics() {
    log_section "Read-only diagnostics"
    check_disk_space
    "$DISK_HEALTH_SCRIPT"
}

announce_user_cleanup() {
    cat <<EOF
User cleanup will modify only these targets:
  - result and result-* symlinks below $PROJECT_ROOT
  - .direnv directories below $PROJECT_ROOT
  - contents of $HOME/.cache/tmp
  - build directories matching ${TMPDIR:-/tmp}/nix-build-${UID}-*
  - the Nix store metadata through: nix store optimise
EOF
}

run_user_cleanup() {
    log_section "User cleanup (state-changing)"
    announce_user_cleanup
    if ! confirm "Proceed with this user cleanup?"; then
        log_info "User cleanup cancelled"
        return 0
    fi

    find "$PROJECT_ROOT" -name result -type l -delete
    find "$PROJECT_ROOT" -name 'result-*' -type l -delete
    find "$PROJECT_ROOT" -name .direnv -type d -prune -exec rm -rf -- {} +
    if [ -d "$HOME/.cache/tmp" ]; then
        find "$HOME/.cache/tmp" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
    fi
    find "${TMPDIR:-/tmp}" -maxdepth 1 -user "$UID" -name "nix-build-${UID}-*" -exec rm -rf -- {} +
    nix store optimise
    log_success "User cleanup completed"
}

generation_count() {
    sudo nix-env --list-generations --profile /nix/var/nix/profiles/system | wc -l
}

run_system_cleanup() {
    log_section "Privileged system cleanup (state-changing)"
    cat <<'EOF'
This operation will:
  - delete system generations older than 7 days;
  - garbage-collect unreachable Nix store paths;
  - delete journal entries older than 2 days.
EOF
    if ! confirm "Proceed with privileged system cleanup?"; then
        log_info "System cleanup cancelled"
        return 0
    fi

    local before after
    before=$(generation_count)
    sudo nix-env --delete-generations 7d --profile /nix/var/nix/profiles/system
    sudo nix-collect-garbage --keep-derivations --keep-outputs
    sudo journalctl --vacuum-time=2d
    after=$(generation_count)
    log_success "System cleanup completed ($((before - after)) generations removed)"
}

run_update() {
    log_section "Host flake update (state-changing)"
    log_warning "This modifies hosts/$(hostname -s)/flake.lock and module release metadata."
    if ! confirm "Proceed with the flake update?"; then
        log_info "Flake update cancelled"
        return 0
    fi
    "$SCRIPT_DIR/update.sh"
}

interactive_menu() {
    cat <<'EOF'

NixOS Maintenance
1) Read-only diagnostics
2) User cleanup
3) Privileged system cleanup
4) Flake update
q) Quit
EOF
    read -r -p "Select option: " choice
    case "$choice" in
        1) run_diagnostics ;;
        2) run_user_cleanup ;;
        3) run_system_cleanup ;;
        4) run_update ;;
        q|Q) return 0 ;;
        *) log_error "Invalid option: $choice"; return 2 ;;
    esac
}

mode=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --diagnose|--cleanup|--system-cleanup|--update)
            if [ -n "$mode" ]; then
                log_error "Select exactly one mode"
                exit 2
            fi
            mode=$1
            ;;
        --yes|-y) ASSUME_YES=1 ;;
        --help|-h) usage; exit 0 ;;
        *) log_error "Unknown argument: $1"; usage >&2; exit 2 ;;
    esac
    shift
done

if [ "$ASSUME_YES" -eq 1 ] && [ -z "$mode" ]; then
    log_error "--yes requires an explicit state-changing mode"
    exit 2
fi

case "$mode" in
    --diagnose) run_diagnostics ;;
    --cleanup) run_user_cleanup ;;
    --system-cleanup) run_system_cleanup ;;
    --update) run_update ;;
    "") interactive_menu ;;
esac
