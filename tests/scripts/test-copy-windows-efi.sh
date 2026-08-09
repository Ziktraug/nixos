#!/usr/bin/env bash

set -euo pipefail

repo_root="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
script="$repo_root/script/copy-windows-efi.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

make_stubs() {
    local scenario=$1
    local bin_dir="$fixture/$scenario/bin"
    mkdir -p "$bin_dir"

    cat > "$bin_dir/mktemp" <<'EOF'
#!/usr/bin/env bash
mkdir -p "$FIXTURE/mount"
printf '%s\n' "$FIXTURE/mount"
EOF
    cat > "$bin_dir/mountpoint" <<'EOF'
#!/usr/bin/env bash
[ "${MOUNTPOINT_OCCUPIED:-0}" = 1 ]
EOF
    cat > "$bin_dir/mount" <<'EOF'
#!/usr/bin/env bash
printf 'mount %s\n' "$*" >> "$FIXTURE/log"
[ "${MOUNT_FAIL:-0}" = 0 ] || exit 32
mkdir -p "${@: -1}/EFI/Microsoft/Boot"
printf 'bootloader' > "${@: -1}/EFI/Microsoft/Boot/bootmgfw.efi"
printf 'fresh' > "${@: -1}/EFI/Microsoft/current.txt"
EOF
    cat > "$bin_dir/umount" <<'EOF'
#!/usr/bin/env bash
printf 'umount %s\n' "$*" >> "$FIXTURE/log"
EOF
    sed -i "1c#!${BASH}" "$bin_dir"/*
    chmod +x "$bin_dir"/*
    printf '%s\n' "$bin_dir"
}

run_case() {
    local scenario=$1
    shift
    local case_dir="$fixture/$scenario"
    local bin_dir
    mkdir -p "$case_dir/boot"
    bin_dir="$(make_stubs "$scenario")"
    FIXTURE="$case_dir" \
        ALLOW_NON_BLOCK_DEVICE=1 \
        WINDOWS_EFI_DEVICE="$case_dir/device" \
        BOOT_EFI_DIR="$case_dir/boot" \
        MKTEMP_BIN="$bin_dir/mktemp" \
        MOUNTPOINT_BIN="$bin_dir/mountpoint" \
        MOUNT_BIN="$bin_dir/mount" \
        UMOUNT_BIN="$bin_dir/umount" \
        "$@" bash "$script"
}
assert_no_transaction_dirs() {
    local boot_dir=$1
    test -z "$(find "$boot_dir" -maxdepth 1 \
        \( -name '.Microsoft.new.*' -o -name '.Microsoft.old.*' \) \
        -print -quit)"
}

# A missing device must fail before creating a mount point or invoking mount.
missing_device_dir="$fixture/missing-device"
missing_device_bin="$(make_stubs missing-device)"
mkdir -p "$missing_device_dir/boot"
if env -u WINDOWS_EFI_DEVICE \
    FIXTURE="$missing_device_dir" \
    ALLOW_NON_BLOCK_DEVICE=1 \
    BOOT_EFI_DIR="$missing_device_dir/boot" \
    MKTEMP_BIN="$missing_device_bin/mktemp" \
    MOUNTPOINT_BIN="$missing_device_bin/mountpoint" \
    MOUNT_BIN="$missing_device_bin/mount" \
    UMOUNT_BIN="$missing_device_bin/umount" \
    bash "$script" > "$missing_device_dir/stdout" 2> "$missing_device_dir/stderr"; then
    echo "missing WINDOWS_EFI_DEVICE unexpectedly succeeded" >&2
    exit 1
fi
grep -q 'WINDOWS_EFI_DEVICE must be set' "$missing_device_dir/stderr"
test ! -e "$missing_device_dir/mount"
test ! -e "$missing_device_dir/log"

# A provided fake device exercises the existing mount and copy transaction.
run_case success env
test -f "$fixture/success/boot/Microsoft/Boot/bootmgfw.efi"
test "$(grep -c '^umount ' "$fixture/success/log")" -eq 1
assert_no_transaction_dirs "$fixture/success/boot"

replacement_dir="$fixture/replacement"
mkdir -p "$replacement_dir/boot/Microsoft"
printf 'old' > "$replacement_dir/boot/Microsoft/old.txt"
printf 'stale' > "$replacement_dir/boot/Microsoft/stale.txt"
run_case replacement env
test -f "$replacement_dir/boot/Microsoft/Boot/bootmgfw.efi"
test -f "$replacement_dir/boot/Microsoft/current.txt"
test ! -e "$replacement_dir/boot/Microsoft/old.txt"
test ! -e "$replacement_dir/boot/Microsoft/stale.txt"
assert_no_transaction_dirs "$replacement_dir/boot"

copy_failure_dir="$fixture/copy-failure"
bin_dir="$(make_stubs copy-failure)"
mkdir -p "$copy_failure_dir/boot/Microsoft"
printf 'old' > "$copy_failure_dir/boot/Microsoft/old.txt"
cat > "$bin_dir/cp" <<'EOF'
#!/usr/bin/env bash
destination=""
for destination; do :; done
mkdir -p "$destination"
printf 'partial' > "$destination/partial.txt"
exit 41
EOF
chmod +x "$bin_dir/cp"
sed -i "1c#!$BASH" "$bin_dir/cp"
if FIXTURE="$copy_failure_dir" ALLOW_NON_BLOCK_DEVICE=1 \
    WINDOWS_EFI_DEVICE="$copy_failure_dir/device" BOOT_EFI_DIR="$copy_failure_dir/boot" \
    MKTEMP_BIN="$bin_dir/mktemp" MOUNTPOINT_BIN="$bin_dir/mountpoint" \
    MOUNT_BIN="$bin_dir/mount" UMOUNT_BIN="$bin_dir/umount" CP_BIN="$bin_dir/cp" \
    bash "$script"; then
    echo "failed copy unexpectedly replaced the destination" >&2
    exit 1
fi
test -f "$copy_failure_dir/boot/Microsoft/old.txt"
test ! -e "$copy_failure_dir/boot/Microsoft/current.txt"
assert_no_transaction_dirs "$copy_failure_dir/boot"
test "$(grep -c '^umount ' "$copy_failure_dir/log")" -eq 1

if run_case mount-failure env MOUNT_FAIL=1; then
    echo "mount failure unexpectedly succeeded" >&2
    exit 1
fi
! grep -q '^umount ' "$fixture/mount-failure/log"

if run_case occupied env MOUNTPOINT_OCCUPIED=1; then
    echo "occupied mount point unexpectedly succeeded" >&2
    exit 1
fi
test ! -e "$fixture/occupied/log"

interrupt_dir="$fixture/interruption"
mkdir -p "$interrupt_dir/boot/Microsoft"
printf 'old' > "$interrupt_dir/boot/Microsoft/old.txt"
bin_dir="$(make_stubs interruption)"
cat > "$bin_dir/cp" <<'EOF'
#!/usr/bin/env bash
kill -TERM "$PPID"
EOF
chmod +x "$bin_dir/cp"
sed -i "1c#!${BASH}" "$bin_dir/cp"
if FIXTURE="$interrupt_dir" ALLOW_NON_BLOCK_DEVICE=1 \
    WINDOWS_EFI_DEVICE="$interrupt_dir/device" BOOT_EFI_DIR="$interrupt_dir/boot" \
    MKTEMP_BIN="$bin_dir/mktemp" MOUNTPOINT_BIN="$bin_dir/mountpoint" \
    MOUNT_BIN="$bin_dir/mount" UMOUNT_BIN="$bin_dir/umount" CP_BIN="$bin_dir/cp" \
    bash "$script"; then
    echo "interrupted copy unexpectedly succeeded" >&2
    exit 1
fi
test "$(grep -c '^umount ' "$interrupt_dir/log")" -eq 1
test -f "$interrupt_dir/boot/Microsoft/old.txt"
test ! -e "$interrupt_dir/boot/Microsoft/current.txt"
assert_no_transaction_dirs "$interrupt_dir/boot"

echo "copy-windows-efi tests passed"
