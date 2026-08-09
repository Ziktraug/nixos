#!/usr/bin/env bash

set -euo pipefail

repo_root="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
helper="$repo_root/modules/dotfiles-manager/user-activation.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
home="$fixture/home"
checkout="$fixture/checkout"
user="$(id -un)"
mkdir -p "$home" "$checkout/one" "$checkout/two"

apply() {
    bash "$helper" "$user" "$home" "$@" 0
}

printf 'one\n' > "$checkout/one/settings.json"
apply editor missing "$checkout/one/settings.json" "$home/.config/editor/settings.json"
test -L "$home/.config/editor/settings.json"

rm "$home/.config/editor/settings.json"
printf 'one\n' > "$home/.config/editor/settings.json"
apply editor identical "$checkout/one/settings.json" "$home/.config/editor/settings.json"
test -L "$home/.config/editor/settings.json"
test ! -d "$home/.dotfiles-backups"

rm "$home/.config/editor/settings.json"
printf 'local editor\n' > "$home/.config/editor/settings.json"
printf 'two\n' > "$checkout/two/settings.json"
mkdir -p "$home/.config/other"
printf 'local other\n' > "$home/.config/other/settings.json"
apply editor divergent "$checkout/one/settings.json" "$home/.config/editor/settings.json" > "$fixture/first.out"
apply other divergent "$checkout/two/settings.json" "$home/.config/other/settings.json" > "$fixture/second.out"
mapfile -t backups < <(find "$home/.dotfiles-backups" -name original -type f | sort)
test "${#backups[@]}" -eq 2
grep -q 'local editor' "${backups[0]}" "${backups[1]}"
grep -q 'local other' "${backups[0]}" "${backups[1]}"
grep -q 'editor--divergent--.config_editor_settings.json' "$fixture/first.out"
grep -q 'other--divergent--.config_other_settings.json' "$fixture/second.out"

before=$(find "$home/.dotfiles-backups" -name original -type f | wc -l)
apply editor divergent "$checkout/one/settings.json" "$home/.config/editor/settings.json" > "$fixture/idempotent.out"
after=$(find "$home/.dotfiles-backups" -name original -type f | wc -l)
test "$before" -eq "$after"
grep -q 'Already linked' "$fixture/idempotent.out"

ln -sfn "$checkout/two/settings.json" "$home/.config/editor/settings.json"
apply editor wrong-link "$checkout/one/settings.json" "$home/.config/editor/settings.json"
test "$(readlink -f "$home/.config/editor/settings.json")" = "$checkout/one/settings.json"

mkdir -p "$home/symlink-target"
ln -s "$home/symlink-target" "$home/linked-parent"
if apply unsafe symlink-parent "$checkout/one/settings.json" "$home/linked-parent/settings.json" 2> "$fixture/symlink.err"; then
    echo "symlinked parent unexpectedly accepted" >&2
    exit 1
fi
grep -q 'refusing symlinked parent' "$fixture/symlink.err"

if apply missing source "$checkout/missing" "$home/.config/missing/file" 2> "$fixture/missing.err"; then
    echo "missing checkout source unexpectedly accepted" >&2
    exit 1
fi
grep -q 'checkout source unavailable' "$fixture/missing.err"

printf 'not executable\n' > "$checkout/not-executable"
if bash "$helper" "$user" "$home" executable source "$checkout/not-executable" \
    "$home/.local/bin/not-executable" 1 2> "$fixture/executable.err"; then
    echo "non-executable source unexpectedly accepted" >&2
    exit 1
fi
grep -q 'requires an executable checkout source' "$fixture/executable.err"

printf 'obstruction\n' > "$home/blocked-parent"
if apply io visible "$checkout/one/settings.json" "$home/blocked-parent/settings.json" 2> "$fixture/io.err"; then
    echo "I/O obstruction unexpectedly hidden" >&2
    exit 1
fi
grep -q 'parent component is not a directory' "$fixture/io.err"

if bash "$helper" definitely-not-"$user" "$home" identity wrong "$checkout/one/settings.json" \
    "$home/.config/identity/file" 0 2> "$fixture/identity.err"; then
    echo "wrong effective user unexpectedly accepted" >&2
    exit 1
fi
grep -q 'must run as' "$fixture/identity.err"

echo 'dotfiles user activation tests passed'
