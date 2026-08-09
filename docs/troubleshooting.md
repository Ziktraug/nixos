# Troubleshooting guide

## NTFS mount failures

### Diagnose without guessing a device

Start with the read-only repository diagnostic:

```bash
./script/maintenance.sh --diagnose
# or
./script/disk-health-check.sh
```

The disk script resolves configured mount points through `findmnt` and `lsblk`.
Do not substitute a remembered `/dev/sdX` or `/dev/nvmeXnY` path: those names
can change across boots, firmware updates, and hardware changes.

For one mount point:

```bash
mount_point=/mnt/hdd2tb
findmnt --target "$mount_point"
source="$(findmnt -rn -o SOURCE --target "$mount_point")"
lsblk -o NAME,PATH,PKNAME,FSTYPE,UUID,MOUNTPOINTS "$source"
journalctl -k -b | grep -i ntfs
```

An optional volume that is not mounted is not by itself a disk failure. An
ambiguous source is a reason to stop and inspect the block topology, not to
guess.

### `force` does not mean “currently dirty”

The host configuration contains a persistent NTFS `force` option. Its presence
in mount options only proves that the option was configured. It does not expose
the current NTFS dirty flag, so neither the script nor this guide uses it as a
repair trigger.

Only treat the volume as dirty when an authoritative diagnostic—such as an
explicit kernel mount error or a filesystem tool run against the verified,
unmounted volume—reports that state.

### Repair safety

Before any repair:

1. resolve and record the exact source and UUID;
2. make sure the volume is unmounted;
3. back up irreplaceable data;
4. prefer Windows `chkdsk` for full NTFS repair;
5. remember that `ntfsfix` performs limited repairs and schedules a Windows
   consistency check—it is not a full `chkdsk` replacement.

This repository intentionally does not provide a copy-paste repair command,
because such a command is only safe after the target has been identified at
runtime.

### Apply a mount configuration change

Validate and build the public fixture from the root flake:

```bash
./script/check.sh
nix build --no-link .#nixosConfigurations.example.config.system.build.toplevel --no-update-lock-file --no-write-lock-file
```

If changing a live mount prevents `switch`, configure the next boot instead:

```bash
sudo nixos-rebuild boot --flake .#<host>
sudo reboot
```

After reboot, verify the exact mount and service state:

```bash
findmnt --target /mnt/hdd2tb
systemctl status mnt-hdd2tb.mount
./script/disk-health-check.sh
```

## DNS startup problems

The local DNS stack is owned by
`applications.services.networking.localDns`. Inspect both services and their
ordering together:

```bash
systemctl status unbound adguardhome
journalctl -b -u unbound -u adguardhome
ss -lntup | grep -E ':(53|5335|3010)\b'
```

The expected topology is AdGuard Home on local DNS port 53, forwarding to
Unbound on loopback. The actual ports are declared once in
`modules/services/networking/default.nix`.

## ProtonVPN does not autostart

The user service waits for NetworkManager and the Secret Service. A readiness
timeout now makes the unit fail and retry instead of being silently skipped.

```bash
systemctl --user status protonvpn-autostart
journalctl --user -b -u protonvpn-autostart
systemctl --user restart protonvpn-autostart
```

If retries continue, verify the GNOME keyring/Secret Service and network state;
do not add a blind sleep to the service.

## Related documentation

- `docs/disk-health-monitoring.md`
- `script/README.md`
- `docs/git-ssh-configuration.md`
