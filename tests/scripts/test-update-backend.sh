#!/usr/bin/env bash

set -euo pipefail

repo_root="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

project="$fixture/project"
mkdir -p "$project/script" "$project/modules/fixture" "$project/hosts/test" "$fixture/bin"
cp "$repo_root/script/update.sh" "$project/script/update.sh"
cp "$repo_root/script/rebuild.sh" "$project/script/rebuild.sh"
touch "$project/hosts/test/flake.nix"
printf 'managed settings\n' > "$project/modules/fixture/settings.json"
ln -s "$project/modules/fixture/settings.json" "$fixture/settings.json"
mkdir -p "$fixture/old-system" "$fixture/new-system/bin"
ln -s "$fixture/old-system" "$fixture/current-system"
ln -s "$fixture/old-system" "$fixture/system-profile"

cat > "$project/modules/fixture/update-flake-pre.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${RELEASE_UPDATE_POLICY:-missing}" >> "$FIXTURE/policies.log"
EOF
chmod +x "$project/modules/fixture/update-flake-pre.sh"
sed -i "1c#!${BASH}" "$project/modules/fixture/update-flake-pre.sh"

cat > "$fixture/bin/nix" <<'EOF'
#!/usr/bin/env bash
printf 'nix %s\n' "$*" >> "$FIXTURE/commands.log"
case "${1:-} ${2:-}" in
    'flake update'|'flake check')
        exit 0
        ;;
    'eval --json')
        jq -nc \
            --arg source_dir 'modules/fixture' \
            --arg target '$HOME/settings.json' \
            '{fixture: {enable: true, sourceDir: $source_dir, mappings: {settings: {source: "settings.json", target: $target}}}}'
        ;;
    'eval --raw')
        printf '%s\n' "$FIXTURE"
        ;;
    'store diff-closures')
        exit 0
        ;;
    *)
        echo "unexpected nix call: $*" >&2
        exit 92
        ;;
esac
EOF

cat > "$fixture/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >> "$FIXTURE/commands.log"
if [ "${SUDO_EXIT:-0}" -ne 0 ]; then
    exit "$SUDO_EXIT"
fi

if [ "${1:-} ${2:-}" = 'nixos-rebuild boot' ]; then
    ln -sfn "$FIXTURE/new-system" "$FIXTURE/system-profile"
    exit 0
fi

case "${2:-}" in
    dry-activate)
        printf '%s\n' "${DRY_ACTIVATE_OUTPUT:-would restart sshd.service}"
        exit "${DRY_ACTIVATE_EXIT:-0}"
        ;;
    switch)
        ln -sfn "$FIXTURE/new-system" "$FIXTURE/current-system"
        if [ "${REPAIR_DOTFILE:-0}" = 1 ]; then
            rm -f -- "$FIXTURE/settings.json"
            ln -s -- "$FIXTURE/project/modules/fixture/settings.json" "$FIXTURE/settings.json"
        fi
        exit 0
        ;;
esac

echo "unexpected sudo call: $*" >&2
exit 93
EOF

chmod +x "$fixture/bin"/*
sed -i "1c#!${BASH}" "$fixture/bin"/*

run_update() {
    env \
        PATH="$fixture/bin:$PATH" \
        FIXTURE="$fixture" \
        NIXOS_FLAKE_PATH="$project/hosts/test" \
        NIXOS_HOST_KEY=test \
        NO_COLOR=1 \
        bash "$project/script/update.sh" "$@"
}

rebuild_env() {
    env \
        PATH="$fixture/bin:$PATH" \
        FIXTURE="$fixture" \
        NIXOS_REPO="$project" \
        NIXOS_FLAKE_PATH="$project/hosts/test" \
        NIXOS_HOST_KEY=test \
        NIXOS_CURRENT_SYSTEM="$fixture/current-system" \
        NIXOS_SYSTEM_PROFILE="$fixture/system-profile" \
        NO_COLOR=1 \
        "$@"
}

run_update --no-prompts --release-policy accept --json-summary "$fixture/accept.json" > "$fixture/accept.out"
[ "$(tail -n1 "$fixture/policies.log")" = accept ]
[ "$(jq -r .releasePolicy "$fixture/accept.json")" = accept ]
[ "$(jq -r .operation "$fixture/accept.json")" = update ]

# --no-prompts remains a safe compatibility shorthand: it keeps release pins
# unless the caller made its release policy explicit.
run_update --no-prompts --json-summary "$fixture/keep.json" > "$fixture/keep.out"
[ "$(tail -n1 "$fixture/policies.log")" = keep ]
[ "$(jq -r .releasePolicy "$fixture/keep.json")" = keep ]

if run_update --no-prompts --release-policy invalid > "$fixture/invalid.out" 2>&1; then
    echo "invalid backend release policy unexpectedly succeeded" >&2
    exit 1
fi
grep -q 'release policy must be one of: interactive, accept, keep' "$fixture/invalid.out"

rebuild_env \
    DRY_ACTIVATE_OUTPUT='would restart sshd.service' \
    bash "$project/script/rebuild.sh" \
    --no-prompts \
    --json-summary "$fixture/rebuild.json" > "$fixture/rebuild.out"

[ "$(jq -r .operation "$fixture/rebuild.json")" = rebuild ]
[ "$(jq -r .status "$fixture/rebuild.json")" = ok ]
[ "$(jq -r .exitCode "$fixture/rebuild.json")" -eq 0 ]
[ "$(jq -r .activation.installed "$fixture/rebuild.json")" = true ]
[ "$(jq -r .activation.activated "$fixture/rebuild.json")" = false ]
[ "$(jq -r .activation.risk "$fixture/rebuild.json")" = low ]
[ "$(jq -r .activation.rebootRequired "$fixture/rebuild.json")" = true ]
[ "$(jq -r .packages.updated "$fixture/rebuild.json")" -eq 0 ]
[ "$(jq -r .dotfiles.changed "$fixture/rebuild.json")" -eq 0 ]
grep -q 'sudo nixos-rebuild boot ' "$fixture/commands.log"
if grep -q 'switch-to-configuration switch' "$fixture/commands.log"; then
    echo 'non-interactive auto rebuild unexpectedly switched live' >&2
    exit 1
fi

rebuild_env \
    DRY_ACTIVATE_OUTPUT='would stop NetworkManager.service, gnome-session-monitor.service, dbus.service' \
    bash "$project/script/rebuild.sh" \
    --no-prompts \
    --json-summary "$fixture/rebuild-risky.json" > "$fixture/rebuild-risky.out"
[ "$(jq -r .activation.risk "$fixture/rebuild-risky.json")" = high ]
[ "$(jq -r '.activation.riskItems | index("NetworkManager") != null' "$fixture/rebuild-risky.json")" = true ]
[ "$(jq -r '.activation.riskItems | index("GNOME session") != null' "$fixture/rebuild-risky.json")" = true ]
[ "$(jq -r '.activation.riskItems | index("user D-Bus") != null' "$fixture/rebuild-risky.json")" = true ]
grep -q 'Risky live activation detected' "$fixture/rebuild-risky.out"

rebuild_env \
    DRY_ACTIVATE_OUTPUT='would stop NetworkManager.service, gnome-session-monitor.service, dbus.service' \
    bash "$project/script/rebuild.sh" \
    --no-prompts \
    --activation-ui-fd 3 \
    --json-summary "$fixture/rebuild-risky-forwarded.json" \
    > "$fixture/rebuild-risky-forwarded.out" \
    3> "$fixture/rebuild-risky-preview.out"
[ "$(jq -r .activation.risk "$fixture/rebuild-risky-forwarded.json")" = high ]
grep -q 'Risky live activation detected' "$fixture/rebuild-risky-preview.out"
grep -q 'user D-Bus' "$fixture/rebuild-risky-preview.out"
if grep -q 'Risky live activation detected' "$fixture/rebuild-risky-forwarded.out"; then
    echo 'forwarded activation preview was also written to backend stdout' >&2
    exit 1
fi

ln -sfn "$fixture/old-system" "$fixture/current-system"
printf '\n' | rebuild_env \
    DRY_ACTIVATE_OUTPUT='would stop NetworkManager.service and gnome-session-monitor.service' \
    bash "$project/script/rebuild.sh" \
    --json-summary "$fixture/rebuild-risky-default.json" \
    > "$fixture/rebuild-risky-default.out" \
    2> "$fixture/rebuild-risky-default.err"
[ "$(jq -r .activation.activated "$fixture/rebuild-risky-default.json")" = false ]
[ "$(jq -r .activation.rebootRequired "$fixture/rebuild-risky-default.json")" = true ]
grep -q 'Switch now anyway? \[y/N\]' "$fixture/rebuild-risky-default.err"

ln -sfn "$fixture/old-system" "$fixture/current-system"
printf '\n' | rebuild_env \
    DRY_ACTIVATE_OUTPUT='would stop NetworkManager.service and dbus.service' \
    bash "$project/script/rebuild.sh" \
    --activation-ui-fd 3 \
    --json-summary "$fixture/rebuild-risky-ui.json" \
    > "$fixture/rebuild-risky-ui.out" \
    2> "$fixture/rebuild-risky-ui.err" \
    3> "$fixture/rebuild-risky-ui.txt"
[ "$(jq -r .activation.activated "$fixture/rebuild-risky-ui.json")" = false ]
ui_service_line="$(grep -n -- '- user D-Bus' "$fixture/rebuild-risky-ui.txt" | cut -d: -f1)"
ui_prompt_line="$(grep -n 'Switch now anyway? \[y/N\]' "$fixture/rebuild-risky-ui.txt" | cut -d: -f1)"
[ -n "$ui_service_line" ]
[ -n "$ui_prompt_line" ]
[ "$ui_service_line" -lt "$ui_prompt_line" ]

ln -sfn "$fixture/old-system" "$fixture/current-system"
printf '\n' | rebuild_env \
    DRY_ACTIVATE_OUTPUT='would restart sshd.service' \
    bash "$project/script/rebuild.sh" \
    --json-summary "$fixture/rebuild-safe-default.json" \
    > "$fixture/rebuild-safe-default.out" \
    2> "$fixture/rebuild-safe-default.err"
[ "$(jq -r .activation.activated "$fixture/rebuild-safe-default.json")" = true ]
[ "$(jq -r .activation.rebootRequired "$fixture/rebuild-safe-default.json")" = false ]
grep -q 'Apply the installed generation now? \[Y/n\]' "$fixture/rebuild-safe-default.err"

ln -sfn "$fixture/old-system" "$fixture/current-system"
set +e
rebuild_env \
    SUDO_EXIT=7 \
    bash "$project/script/rebuild.sh" --json-summary "$fixture/rebuild-failed.json" > "$fixture/rebuild-failed.out"
failed_exit=$?
set -e
[ "$failed_exit" -eq 7 ]
[ "$(jq -r .status "$fixture/rebuild-failed.json")" = failed ]
[ "$(jq -r .exitCode "$fixture/rebuild-failed.json")" -eq 7 ]
[ "$(jq -r .activation.installed "$fixture/rebuild-failed.json")" = false ]

rm -- "$fixture/settings.json"
rebuild_env \
    REPAIR_DOTFILE=1 \
    DRY_ACTIVATE_OUTPUT='would restart sshd.service' \
    bash "$project/script/rebuild.sh" \
    --no-prompts \
    --activation-policy switch \
    --json-summary "$fixture/rebuild-created.json" > "$fixture/rebuild-created.out"
[ "$(jq -r .activation.activated "$fixture/rebuild-created.json")" = true ]
[ "$(jq -r .activation.rebootRequired "$fixture/rebuild-created.json")" = false ]
[ "$(jq -r .dotfiles.changed "$fixture/rebuild-created.json")" -eq 1 ]
[ "$(jq -r '.dotfiles.items[0]' "$fixture/rebuild-created.json")" = '[fixture] settings.json' ]
[ "$(readlink -- "$fixture/settings.json")" = "$project/modules/fixture/settings.json" ]

rm -- "$fixture/settings.json"
ln -s -- "$fixture/wrong-settings.json" "$fixture/settings.json"
rebuild_env \
    REPAIR_DOTFILE=1 \
    DRY_ACTIVATE_OUTPUT='would restart sshd.service' \
    bash "$project/script/rebuild.sh" \
    --no-prompts \
    --activation-policy switch \
    --json-summary "$fixture/rebuild-repaired.json" > "$fixture/rebuild-repaired.out"
[ "$(jq -r .dotfiles.changed "$fixture/rebuild-repaired.json")" -eq 1 ]
[ "$(jq -r '.dotfiles.items[0]' "$fixture/rebuild-repaired.json")" = '[fixture] settings.json' ]
[ "$(readlink -- "$fixture/settings.json")" = "$project/modules/fixture/settings.json" ]

echo 'update backend tests passed'
