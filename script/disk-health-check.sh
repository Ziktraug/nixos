#!/usr/bin/env bash

set -euo pipefail

FINDMNT_BIN="${FINDMNT_BIN:-findmnt}"
LSBLK_BIN="${LSBLK_BIN:-lsblk}"
SMARTCTL_BIN="${SMARTCTL_BIN:-smartctl}"
DISK_HEALTH_MOUNT_POINTS="${DISK_HEALTH_MOUNT_POINTS:-/ /mnt/hdd2tb}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

resolve_mount() {
    local mount_point=$1
    local -a sources
    mapfile -t sources < <("$FINDMNT_BIN" -rn -o SOURCE --mountpoint "$mount_point" 2>/dev/null || true)

    if [ "${#sources[@]}" -eq 0 ]; then
        log_warning "$mount_point is not mounted; skipping" >&2
        return 1
    fi
    if [ "${#sources[@]}" -ne 1 ] || [ -z "${sources[0]}" ]; then
        log_error "Ambiguous source for $mount_point; refusing to guess a device" >&2
        return 2
    fi
    printf '%s\n' "${sources[0]}"
}

physical_device_for() {
    local source=$1
    local current=$source
    local -a parents

    while true; do
        mapfile -t parents < <("$LSBLK_BIN" -ndo PKNAME "$current" 2>/dev/null | awk 'NF' || true)
        if [ "${#parents[@]}" -eq 0 ]; then
            printf '%s\n' "$current"
            return 0
        fi
        if [ "${#parents[@]}" -ne 1 ]; then
            log_error "Ambiguous physical devices below $source; refusing to guess" >&2
            return 1
        fi
        current="/dev/${parents[0]}"
    done
}

stable_description() {
    local source=$1
    local uuid
    uuid=$("$LSBLK_BIN" -ndo UUID "$source" 2>/dev/null | head -n 1 || true)
    if [ -n "$uuid" ]; then
        printf 'UUID=%s (resolved as %s)' "$uuid" "$source"
    else
        printf '%s (no filesystem UUID reported)' "$source"
    fi
}

check_smart() {
    local disk=$1
    local description=$2
    local output

    if ! output=$("$SMARTCTL_BIN" -H -A "$disk" 2>&1); then
        log_warning "SMART unavailable for $description on $disk: $output"
        return 1
    fi
    if grep -Eq 'PASSED|SMART overall-health self-assessment test result:[[:space:]]+PASSED' <<< "$output"; then
        log_success "SMART passed for $description on $disk"
    else
        log_error "SMART did not report a passing health status for $description on $disk"
        return 1
    fi

    if awk '/Reallocated_Sector|Current_Pending_Sector|Offline_Uncorrectable/ && $NF != 0 { found=1 } END { exit !found }' <<< "$output"; then
        log_warning "SMART reports reallocated, pending, or uncorrectable sectors on $disk"
        return 1
    fi
    if grep -Eq 'Critical Warning:[[:space:]]+(0x)?0*[1-9a-fA-F]' <<< "$output"; then
        log_warning "NVMe critical warning reported on $disk"
        return 1
    fi
}

check_filesystem_status() {
    local mount_point=$1
    local source=$2
    local fstype
    fstype=$("$FINDMNT_BIN" -rn -o FSTYPE --mountpoint "$mount_point" 2>/dev/null || true)
    if [[ "$fstype" == ntfs* ]]; then
        log_info "NTFS volume $(stable_description "$source") is mounted at $mount_point."
        log_info "A persistent mount option such as 'force' does not prove the NTFS dirty flag is set."
        log_info "Dirty-state inspection or repair must be performed manually with the volume unmounted."
    fi
}

main() {
    local status=0 resolve_status mount_point source disk description
    local -A checked_disks=()

    log_info "Disk diagnostics derived from configured mount points"
    for mount_point in $DISK_HEALTH_MOUNT_POINTS; do
        resolve_status=0
        source=$(resolve_mount "$mount_point") || resolve_status=$?
        if [ "$resolve_status" -ne 0 ]; then
            if [ "$resolve_status" -eq 2 ] || [ "$mount_point" = "/" ]; then
                status=1
            fi
            continue
        fi
        description=$(stable_description "$source")
        log_info "$mount_point uses $description"
        check_filesystem_status "$mount_point" "$source"

        if ! disk=$(physical_device_for "$source"); then
            status=1
            continue
        fi
        if [ -z "${checked_disks[$disk]:-}" ]; then
            check_smart "$disk" "$description" || status=1
            checked_disks[$disk]=1
        fi
    done
    return "$status"
}

main
