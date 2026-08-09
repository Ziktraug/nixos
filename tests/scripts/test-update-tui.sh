#!/usr/bin/env bash

set -euo pipefail

repo_root="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/project/script" "$fixture/bin"

cat > "$fixture/project/script/update.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$FIXTURE/update-args"
summary=""
while [ $# -gt 0 ]; do
    case "$1" in
        --json-summary) summary=$2; shift 2 ;;
        *) shift ;;
    esac
done
[ -n "$summary" ]
mkdir -p "$(dirname "$summary")"
cat > "$summary" <<JSON
{
  "schemaVersion": 1,
  "operation": "update",
  "status": "ok",
  "releasePolicy": "keep",
  "checkStatus": "passed",
  "dirty": false,
  "inputs": [],
  "releases": [],
  "gitTargets": []
}
JSON
echo 'backend prose is not an API'
EOF

cat > "$fixture/project/script/rebuild.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$FIXTURE/rebuild-args"
summary=""
preview_fd=""
while [ $# -gt 0 ]; do
    case "$1" in
        --json-summary) summary=$2; shift 2 ;;
        --activation-ui-fd) preview_fd=$2; shift 2 ;;
        *) shift ;;
    esac
done
[ -n "$summary" ]
[ -n "$preview_fd" ]
{
  echo
  echo '========== Activation Preview =========='
  echo '  Installed  new'
  echo 'Risky live activation detected'
  echo '  Session-critical changes'
  echo '    - NetworkManager'
  echo '    - GNOME session'
} >&"$preview_fd"
printf 'Switch now anyway? [y/N] ' >&"$preview_fd"
cat > "$summary" <<JSON
{
  "schemaVersion": 1,
  "operation": "rebuild",
  "status": "ok",
  "exitCode": 0,
  "recapFile": "$FIXTURE/project/logs/rebuild.log",
  "system": {"changed": true, "before": "old", "after": "new"},
  "activation": {
    "policy": "auto",
    "installed": true,
    "activated": false,
    "previewSucceeded": true,
    "risk": "high",
    "riskItems": ["NetworkManager", "GNOME session"],
    "rebootRequired": true,
    "installedSystem": "/nix/store/new-system"
  },
  "packages": {
    "added": 2,
    "removed": 1,
    "updated": 3,
    "addedItems": ["alpha 1", "beta 1"],
    "removedItems": ["old 1"],
    "updatedItems": ["gamma 1 -> 2"]
  },
  "dotfiles": {"changed": 4, "items": ["[zed] settings.json"]}
}
JSON
echo '========== Rebuild Summary =========='
echo 'Packages 999 values from prose must be ignored'
EOF

cat > "$fixture/bin/gum" <<'EOF'
#!/usr/bin/env bash
printf 'Rebuild now\n'
EOF

chmod +x "$fixture/project/script"/* "$fixture/bin/gum"
sed -i "1c#!${BASH}" "$fixture/project/script"/* "$fixture/bin/gum"

if env \
    PATH="$fixture/bin:$PATH" \
    FIXTURE="$fixture" \
    NIXOS_REPO="$fixture/project" \
    NO_COLOR=1 \
    bun "$repo_root/modules/devtools/tui/update-tui/update-tui.ts" \
        --release-policy > "$fixture/missing-release-policy.out" 2>&1; then
    echo 'update TUI accepted --release-policy without a value' >&2
    exit 1
fi
grep -q -- '--release-policy requires a value' "$fixture/missing-release-policy.out"

env \
    PATH="$fixture/bin:$PATH" \
    FIXTURE="$fixture" \
    NIXOS_REPO="$fixture/project" \
    NO_COLOR=1 \
    bun "$repo_root/modules/devtools/tui/update-tui/update-tui.ts" \
        --release-policy keep > "$fixture/tui.out"

grep -q -- '--no-prompts --release-policy keep' "$fixture/update-args"
grep -q -- '--json-summary' "$fixture/rebuild-args"
grep -q -- '--activation-policy auto' "$fixture/rebuild-args"
grep -q -- '--activation-ui-fd 3' "$fixture/rebuild-args"
grep -q '2 added.*1 removed.*3 updated' "$fixture/tui.out"
grep -q '4 changed' "$fixture/tui.out"
grep -q 'old.*->.*new' "$fixture/tui.out"
grep -q 'Risk.*high' "$fixture/tui.out"
grep -q 'NetworkManager' "$fixture/tui.out"
grep -q 'Reboot to activate' "$fixture/tui.out"
preview_line="$(grep -n 'Activation Preview' "$fixture/tui.out" | head -n1 | cut -d: -f1)"
service_line="$(grep -n -- '- NetworkManager' "$fixture/tui.out" | head -n1 | cut -d: -f1)"
prompt_line="$(grep -n 'Switch now anyway' "$fixture/tui.out" | head -n1 | cut -d: -f1)"
result_line="$(grep -n 'Generation installed successfully' "$fixture/tui.out" | head -n1 | cut -d: -f1)"
[ -n "$preview_line" ]
[ -n "$service_line" ]
[ -n "$prompt_line" ]
[ -n "$result_line" ]
[ "$preview_line" -lt "$service_line" ]
[ "$service_line" -lt "$prompt_line" ]
[ "$prompt_line" -lt "$result_line" ]
if grep -q '999 values' "$fixture/tui.out"; then
    echo 'TUI still parsed the rebuild prose instead of its JSON contract' >&2
    exit 1
fi

echo 'update TUI tests passed'
