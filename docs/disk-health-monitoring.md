# Disk health monitoring

## Source of truth

Run the repository diagnostic instead of copying device names from this guide:

```bash
./script/disk-health-check.sh
```

The script starts from configured mount points (`/` and `/mnt/hdd2tb` by
default), resolves their current block devices with `findmnt` and `lsblk`, then
runs SMART against each physical disk once. Device names such as `/dev/sda`,
`/dev/sdc`, and `/dev/nvme0n1` are deliberately not encoded in the script or in
this document because firmware and hardware changes can reorder them.

Override the inspected mounts when needed:

```bash
DISK_HEALTH_MOUNT_POINTS="/ /mnt/archive" ./script/disk-health-check.sh
```

An unmounted optional volume is reported and skipped. A missing or ambiguous
source for `/`, an ambiguous physical parent, a failed SMART health result, or
critical media attributes make the command fail.

## What is checked

For every resolved mount, the diagnostic reports:

- the source currently returned by `findmnt`;
- a filesystem UUID when `lsblk` exposes one;
- the physical disk containing that source;
- SMART overall health;
- reallocated, pending, or uncorrectable SATA sectors;
- non-zero NVMe critical warnings.

The mapping can be inspected manually without guessing a device:

```bash
mount_point=/mnt/hdd2tb
source="$(findmnt -rn -o SOURCE --target "$mount_point")"
printf 'source: %s\n' "$source"
lsblk -o NAME,PATH,PKNAME,FSTYPE,UUID,MOUNTPOINTS "$source"
```

Only run `smartctl` after the physical disk has been identified from that
output. A partition is not always the device that exposes SMART data.

## NTFS dirty state

The persistent `force` mount option is configuration, not evidence that the
NTFS dirty flag is currently set. The diagnostic therefore never interprets
`force` as a dirty-state signal and never prints a repair command containing a
guessed device.

If a mount fails and the kernel explicitly reports a dirty NTFS volume:

1. identify the exact source with `findmnt`/`lsblk` and its UUID;
2. verify that the volume is unmounted;
3. preserve important data before attempting repair;
4. prefer Windows `chkdsk` for a complete NTFS repair;
5. treat `ntfsfix` only as limited first aid, not as a Linux equivalent of
   `chkdsk`;
6. remount and confirm the filesystem and SMART status afterwards.

Do not infer the dirty flag from `mount` output alone. Do not reuse a device
path from an old log or example.

## Automatic SMART monitoring

NixOS enables `smartd` through `services.smartd`. Check its current state and
recent messages with:

```bash
systemctl status smartd
journalctl -u smartd --since today
```

`smartd` complements the repository diagnostic: it can report changes between
manual checks, while `disk-health-check.sh` verifies the devices backing the
mounts that matter to this host right now.

## Suggested schedule

- After an unexpected shutdown: run the repository diagnostic.
- Monthly: review `smartd` logs and run the diagnostic.
- Before a long SMART self-test: resolve the current physical device, ensure
  the system can remain powered, and consult that drive's documentation.
- On any SMART warning: back up data first and investigate replacement rather
  than repeatedly clearing the warning.

## Testing

The command-stubbed regression suite covers SATA, NVMe, missing mounts and
ambiguous mappings:

```bash
bash tests/scripts/test-disk-health-check.sh
```

The same suite is part of `./script/check.sh`.

## Related files

- `script/disk-health-check.sh`
- `tests/scripts/test-disk-health-check.sh`
- `script/maintenance.sh` (`--diagnose` is read-only)
- the consuming host's root-flake configuration (mounts and `smartd` configuration)
- `docs/troubleshooting.md`
