#!/usr/bin/env bash

set -euo pipefail

repo_root="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
helper="$repo_root/modules/dotfiles-manager/system-copy.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
printf 'immutable\n' > "$fixture/source"
bash "$helper" gnome monitors "$fixture/source" "$fixture/etc/xdg/monitors.xml"
grep -qx immutable "$fixture/etc/xdg/monitors.xml"
echo 'dotfiles system copy tests passed'
