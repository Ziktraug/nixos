#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NIXOS_REPO="${NIXOS_REPO:-$(dirname "$SCRIPT_DIR")}"

requested_host_key="${NIXOS_HOST_KEY:-nixos}"

if [[ -v NIXOS_CHECK_FLAKE_REF ]]; then
  HOST_FLAKE_REF="$NIXOS_CHECK_FLAKE_REF"
  NIXOS_HOST_KEY="$requested_host_key"
elif [[ -f "$NIXOS_REPO/private/hosts/$requested_host_key/flake.nix" ]]; then
  HOST_FLAKE_REF="git+file:$NIXOS_REPO?dir=private/hosts/$requested_host_key"
  NIXOS_HOST_KEY="$requested_host_key"
else
  HOST_FLAKE_REF="git+file:$NIXOS_REPO"
  NIXOS_HOST_KEY="${NIXOS_HOST_KEY:-example}"
fi

printf '[INFO] Checking host flake: %s\n' "$HOST_FLAKE_REF"
nix flake check "$HOST_FLAKE_REF" \
  --no-update-lock-file \
  --no-write-lock-file \
  --print-build-logs

case "${NIXOS_GC_BEFORE_BUILD:-0}" in
  0) ;;
  1)
    printf '[INFO] Reclaiming unreferenced Nix store paths before the system build\n'
    nix store gc
    ;;
  *)
    printf '[ERROR] NIXOS_GC_BEFORE_BUILD must be 0 or 1\n' >&2
    exit 2
    ;;
esac

nix build --no-link \
  "$HOST_FLAKE_REF#nixosConfigurations.$NIXOS_HOST_KEY.config.system.build.toplevel" \
  --no-update-lock-file \
  --no-write-lock-file \
  --print-build-logs
