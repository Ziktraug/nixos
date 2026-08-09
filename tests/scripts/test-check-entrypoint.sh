#!/usr/bin/env bash

set -euo pipefail

repo_root="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
script="$repo_root/script/check.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/bin"

cat > "$fixture/bin/nix" <<'EOF'
#!/usr/bin/env bash
printf '%s\t' "$@" >> "$NIX_CALLS_FILE"
printf '\n' >> "$NIX_CALLS_FILE"

has_no_update=0
has_no_write=0
for argument in "$@"; do
    [ "$argument" = --no-update-lock-file ] && has_no_update=1
    [ "$argument" = --no-write-lock-file ] && has_no_write=1
done
if { [ "${1:-}" != store ] || [ "${2:-}" != gc ]; } &&
    { [ "$has_no_update" -ne 1 ] || [ "$has_no_write" -ne 1 ]; }; then
    printf 'mutated\n' >> "$LOCK_FILE"
fi
EOF
sed -i "1c#!${BASH}" "$fixture/bin/nix"
chmod +x "$fixture/bin/nix"

lock_file="$fixture/flake.lock"
printf 'fixture lock\n' > "$lock_file"

assert_calls() {
    local calls_file=$1
    local expected_ref=$2
    local expected_host=$3
    local expected_gc=${4:-0}
    local expected_check
    local expected_build
    local expected_store_gc
    local -a calls_made

    mapfile -t calls_made < "$calls_file"

    expected_check=$'flake\tcheck\t'"$expected_ref"$'\t--no-update-lock-file\t--no-write-lock-file\t--print-build-logs\t'
    expected_build=$'build\t--no-link\t'"$expected_ref#nixosConfigurations.$expected_host.config.system.build.toplevel"$'\t--no-update-lock-file\t--no-write-lock-file\t--print-build-logs\t'
    expected_store_gc=$'store\tgc\t'

    test "${calls_made[0]}" = "$expected_check"
    if [ "$expected_gc" -eq 1 ]; then
        test "${#calls_made[@]}" -eq 3
        test "${calls_made[1]}" = "$expected_store_gc"
        test "${calls_made[2]}" = "$expected_build"
    else
        test "${#calls_made[@]}" -eq 2
        test "${calls_made[1]}" = "$expected_build"
    fi
}

test_repo="$fixture/repo"
mkdir -p "$test_repo/private/hosts/nixos" "$fixture/public-repo"
printf 'fixture\n' > "$test_repo/private/hosts/nixos/flake.nix"

explicit_ref="git+file:$fixture/example?dir=custom/host"
explicit_calls="$fixture/explicit-nix-calls"
(
    cd "$fixture"
    env \
    PATH="$fixture/bin:$PATH" \
    NIX_CALLS_FILE="$explicit_calls" \
    LOCK_FILE="$lock_file" \
    NIXOS_REPO="$test_repo" \
    NIXOS_HOST_KEY=custom \
    NIXOS_CHECK_FLAKE_REF="$explicit_ref" \
    bash "$script"
)
assert_calls "$explicit_calls" "$explicit_ref" custom

private_calls="$fixture/private-nix-calls"
(
    cd "$fixture"
    env -u NIXOS_CHECK_FLAKE_REF \
    PATH="$fixture/bin:$PATH" \
    NIX_CALLS_FILE="$private_calls" \
    LOCK_FILE="$lock_file" \
    NIXOS_REPO="$test_repo" \
    NIXOS_HOST_KEY=nixos \
    bash "$script"
)
private_ref="git+file:$test_repo?dir=private/hosts/nixos"
assert_calls "$private_calls" "$private_ref" nixos

public_calls="$fixture/public-nix-calls"
(
    cd "$fixture"
    env -u NIXOS_CHECK_FLAKE_REF -u NIXOS_HOST_KEY \
    PATH="$fixture/bin:$PATH" \
    NIX_CALLS_FILE="$public_calls" \
    LOCK_FILE="$lock_file" \
    NIXOS_REPO="$fixture/public-repo" \
    bash "$script"
)
public_ref="git+file:$fixture/public-repo"
assert_calls "$public_calls" "$public_ref" example

gc_calls="$fixture/gc-nix-calls"
(
    cd "$fixture"
    env -u NIXOS_CHECK_FLAKE_REF -u NIXOS_HOST_KEY \
    PATH="$fixture/bin:$PATH" \
    NIX_CALLS_FILE="$gc_calls" \
    LOCK_FILE="$lock_file" \
    NIXOS_REPO="$fixture/public-repo" \
    NIXOS_GC_BEFORE_BUILD=1 \
    bash "$script"
)
assert_calls "$gc_calls" "$public_ref" example 1

test "$(cat "$lock_file")" = 'fixture lock'

echo "check entrypoint tests passed"
