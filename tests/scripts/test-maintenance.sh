#!/usr/bin/env bash

set -euo pipefail

repo_root="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
script="$repo_root/script/maintenance.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/bin" "$fixture/home"

for command in rm sudo nix; do
    cat > "$fixture/bin/$command" <<EOF
#!/usr/bin/env bash
echo "$command called during diagnostics" >&2
exit 97
EOF
    chmod +x "$fixture/bin/$command"
done
cat > "$fixture/disk-health" <<'EOF'
#!/usr/bin/env bash
echo "stub disk diagnostics"
EOF
chmod +x "$fixture/disk-health"
sed -i "1c#!${BASH}" "$fixture/bin"/* "$fixture/disk-health"

PATH="$fixture/bin:$PATH" HOME="$fixture/home" DISK_HEALTH_SCRIPT="$fixture/disk-health" \
    bash "$script" --diagnose > "$fixture/diagnose.out"
grep -q 'Read-only diagnostics' "$fixture/diagnose.out"
grep -q 'stub disk diagnostics' "$fixture/diagnose.out"

if PATH="$fixture/bin:$PATH" HOME="$fixture/home" bash "$script" --yes > /dev/null 2>&1; then
    echo "--yes without an explicit mode unexpectedly succeeded" >&2
    exit 1
fi

printf 'n\n' | HOME="$fixture/home" bash "$script" --cleanup > "$fixture/cleanup.out"
grep -Fq "result and result-* symlinks below $repo_root" "$fixture/cleanup.out"
expected_cache_path="$fixture/ho""me/.cache/tmp"
grep -Fq "$expected_cache_path" "$fixture/cleanup.out"
grep -q 'User cleanup cancelled' "$fixture/cleanup.out"

echo "maintenance tests passed"
