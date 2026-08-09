#!/usr/bin/env bash

set -euo pipefail

repo_root="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
script="$repo_root/script/disk-health-check.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/bin"

cat > "$fixture/bin/findmnt" <<'EOF'
#!/usr/bin/env bash
field=""
target="${@: -1}"
selector=""
while [ "$#" -gt 0 ]; do
    [ "$1" != -o ] || { field=$2; shift; }
    case "$1" in
        --target|--mountpoint) selector=$1 ;;
    esac
    shift
done
if [ "$field" = SOURCE ]; then
    case "$target" in
        /) echo "${ROOT_SOURCE:-/dev/nvme0n1p2}" ;;
        /mnt/hdd2tb)
            if [ "${HDD_MOUNTED:-1}" = 1 ]; then
                echo "${HDD_SOURCE:-/dev/sata2}"
            elif [ "$selector" = --target ]; then
                # Real findmnt --target resolves the containing root filesystem.
                echo "${ROOT_SOURCE:-/dev/nvme0n1p2}"
            fi
            ;;
        /ambiguous) printf '/dev/a\n/dev/b\n' ;;
    esac
else
    case "$target" in
        /) echo ext4 ;;
        /mnt/hdd2tb)
            if [ "${HDD_MOUNTED:-1}" = 1 ]; then
                echo ntfs3
            elif [ "$selector" = --target ]; then
                echo ext4
            fi
            ;;
        /ambiguous) echo ext4 ;;
    esac
fi
EOF
cat > "$fixture/bin/lsblk" <<'EOF'
#!/usr/bin/env bash
field=$2
source="${@: -1}"
case "$field:$source" in
    PKNAME:/dev/mapper/root) echo nvme0n1p2 ;;
    PKNAME:/dev/nvme0n1p2) echo nvme0n1 ;;
    UUID:/dev/nvme0n1p2) echo ROOT-UUID ;;
    PKNAME:/dev/sata2) echo sda ;;
    UUID:/dev/sata2) echo HDD-UUID ;;
esac
if [ "${MULTI_PARENT:-0}" = 1 ] && [ "$field:$source" = PKNAME:/dev/nvme0n1p2 ]; then
    printf 'nvme0n1\nnvme1n1\n'
fi
EOF
cat > "$fixture/bin/smartctl" <<'EOF'
#!/usr/bin/env bash
if [ "${SMART_FAIL:-0}" = 1 ]; then
    echo "device missing"
    exit 2
fi
cat <<OUT
SMART overall-health self-assessment test result: PASSED
Critical Warning: 0x00
Current_Pending_Sector 0
OUT
EOF
sed -i "1c#!${BASH}" "$fixture/bin"/*
chmod +x "$fixture/bin"/*

common=(FINDMNT_BIN="$fixture/bin/findmnt" LSBLK_BIN="$fixture/bin/lsblk" SMARTCTL_BIN="$fixture/bin/smartctl")
env "${common[@]}" bash "$script" > "$fixture/sata-nvme.out"
grep -q 'UUID=ROOT-UUID' "$fixture/sata-nvme.out"
grep -q 'UUID=HDD-UUID' "$fixture/sata-nvme.out"
grep -q 'on /dev/nvme0n1' "$fixture/sata-nvme.out"
grep -q 'on /dev/sda' "$fixture/sata-nvme.out"
grep -q "does not prove the NTFS dirty flag" "$fixture/sata-nvme.out"
! grep -q '/dev/sdc2' "$fixture/sata-nvme.out"

env "${common[@]}" ROOT_SOURCE=/dev/mapper/root bash "$script" > "$fixture/recursive.out"
grep -q 'on /dev/nvme0n1' "$fixture/recursive.out"

env "${common[@]}" HDD_MOUNTED=0 bash "$script" > "$fixture/unmounted.out" 2>&1
grep -q '/mnt/hdd2tb is not mounted' "$fixture/unmounted.out"

if env "${common[@]}" DISK_HEALTH_MOUNT_POINTS='/ambiguous' bash "$script" > "$fixture/ambiguous.out" 2>&1; then
    echo "ambiguous source unexpectedly succeeded" >&2
    exit 1
fi
grep -q 'refusing to guess a device' "$fixture/ambiguous.out"

if env "${common[@]}" MULTI_PARENT=1 bash "$script" > "$fixture/multi-parent.out" 2>&1; then
    echo "multiple physical devices unexpectedly succeeded" >&2
    exit 1
fi
grep -q 'Ambiguous physical devices' "$fixture/multi-parent.out"

if env "${common[@]}" SMART_FAIL=1 bash "$script" > "$fixture/missing-device.out" 2>&1; then
    echo "missing SMART device unexpectedly succeeded" >&2
    exit 1
fi
grep -q 'SMART unavailable.*device missing' "$fixture/missing-device.out"

echo "disk-health-check tests passed"
