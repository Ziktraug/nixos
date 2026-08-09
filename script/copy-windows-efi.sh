#!/usr/bin/env bash

set -euo pipefail

windows_efi_device="${WINDOWS_EFI_DEVICE:-}"
boot_efi_dir="${BOOT_EFI_DIR:-/boot/EFI}"
mount_bin="${MOUNT_BIN:-mount}"
umount_bin="${UMOUNT_BIN:-umount}"
mountpoint_bin="${MOUNTPOINT_BIN:-mountpoint}"
mktemp_bin="${MKTEMP_BIN:-mktemp}"
cp_bin="${CP_BIN:-cp}"
rm_bin="${RM_BIN:-rm}"

if [ -z "$windows_efi_device" ]; then
    echo "WINDOWS_EFI_DEVICE must be set" >&2
    exit 1
fi

if [ ! -b "$windows_efi_device" ] && [ "${ALLOW_NON_BLOCK_DEVICE:-0}" != 1 ]; then
    exit 0
fi

mount_dir="$($mktemp_bin -d "${TMPDIR:-/tmp}/windows-efi.XXXXXX")"
destination="$boot_efi_dir/Microsoft"
staging="$boot_efi_dir/.Microsoft.new.$$"
backup="$boot_efi_dir/.Microsoft.old.$$"
mounted=0
transaction_started=0

cleanup() {
    local status=${1:-$?}

    trap - EXIT INT TERM

    if [ "$transaction_started" -eq 1 ]; then
        if [ -e "$staging" ] || [ -L "$staging" ]; then
            "$rm_bin" -rf -- "$staging"
        fi
        if [ -e "$backup" ] || [ -L "$backup" ]; then
            if [ ! -e "$destination" ] && [ ! -L "$destination" ]; then
                mv -- "$backup" "$destination"
            else
                "$rm_bin" -rf -- "$backup"
            fi
        fi
    fi

    if [ "$mounted" -eq 1 ] && ! "$umount_bin" "$mount_dir"; then
        status=1
    fi
    rmdir "$mount_dir" 2>/dev/null || true
    exit "$status"
}

trap 'cleanup $?' EXIT
trap 'cleanup 130' INT TERM

if "$mountpoint_bin" -q "$mount_dir"; then
    echo "Refusing to use an already-mounted temporary path: $mount_dir" >&2
    exit 1
fi

"$mount_bin" -t vfat -o ro "$windows_efi_device" "$mount_dir"
mounted=1

if [ -d "$mount_dir/EFI/Microsoft" ]; then
    mkdir -p "$boot_efi_dir"

    if [ -e "$staging" ] || [ -L "$staging" ] || [ -e "$backup" ] || [ -L "$backup" ]; then
        echo "Refusing colliding EFI transaction paths under $boot_efi_dir" >&2
        exit 1
    fi

    transaction_started=1
    "$cp_bin" -a -- "$mount_dir/EFI/Microsoft" "$staging"
    if [ ! -d "$staging" ]; then
        echo "Staged Microsoft EFI directory is missing after copy" >&2
        exit 1
    fi

    if [ -e "$destination" ] || [ -L "$destination" ]; then
        mv -- "$destination" "$backup"
    fi
    mv -- "$staging" "$destination"

    if [ -e "$backup" ] || [ -L "$backup" ]; then
        "$rm_bin" -rf -- "$backup"
    fi
    transaction_started=0
fi
