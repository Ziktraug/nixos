#!/usr/bin/env bash

set -euo pipefail

repo_root="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/tmp"

project="$fixture/project"
mkdir -p "$project/script/lib" "$fixture/bin"
cp "$repo_root/script/lib/release-update.sh" "$project/script/lib/release-update.sh"
cp "$repo_root/script/lib/release-hook-bootstrap.sh" "$project/script/lib/release-hook-bootstrap.sh"

hooks=(
    modules/devtools/ai/codex
    modules/devtools/ide/zed
    modules/devtools/cli/rtk
    modules/devtools/ai/local-llm
)

for module_dir in "${hooks[@]}"; do
    mkdir -p "$project/$module_dir"
    cp "$repo_root/$module_dir/update-flake-pre.sh" "$project/$module_dir/update-flake-pre.sh"
    cp "$repo_root/$module_dir/release.json" "$project/$module_dir/release.json"
done

cat > "$fixture/bin/nix" <<'EOF'
#!/usr/bin/env bash
printf 'nix %s\n' "$*" >> "$FIXTURE/commands.log"
case "${1:-}" in
    eval)
        [ "${2:-}" = --json ] || {
            echo "boolean option was not evaluated as JSON" >&2
            exit 88
        }
        [ "${NIX_EVAL_FAIL:-0}" = 0 ] || exit 87
        printf '%s\n' "${NIX_ENABLED:-true}"
        ;;
    hash)
        [ "${ZED_FAILURE_STAGE:-}" != hash ] || exit 92
        printf 'sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\n'
        ;;
    store)
        printf '{"hash":"sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="}\n'
        ;;
esac
EOF

cat > "$fixture/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >> "$FIXTURE/commands.log"
[ "${FAIL_REMOTE:-0}" = 0 ] || {
    echo "remote release lookup must not run" >&2
    exit 90
}
case "$*" in
    *repos/openai/codex/releases/latest*)
        cat <<'JSON'
{"tag_name":"rust-v999.0.0","assets":[
  {"name":"codex-x86_64-unknown-linux-musl.tar.gz","digest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},
  {"name":"codex-aarch64-unknown-linux-musl.tar.gz","digest":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},
  {"name":"codex-code-mode-host-x86_64-unknown-linux-musl.tar.gz","digest":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"},
  {"name":"codex-code-mode-host-aarch64-unknown-linux-musl.tar.gz","digest":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}
]}
JSON
        ;;
    *repos/zed-industries/zed/releases/latest*)
        printf 'v999.0.0\n'
        ;;
    *repos/rtk-ai/rtk/releases/latest*)
        printf 'v999.0.0\n'
        ;;
    *repos/rtk-ai/rtk/releases/tags/v999.0.0*)
        cat <<'JSON'
{"assets":[
  {"name":"rtk-x86_64-unknown-linux-musl.tar.gz","digest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},
  {"name":"rtk-aarch64-unknown-linux-gnu.tar.gz","digest":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}
]}
JSON
        ;;
    *repos/ollama/ollama/releases/latest*)
        printf 'v999.0.0\n'
        ;;
    *)
        echo "unexpected gh call: $*" >&2
        exit 89
        ;;
esac
EOF

cat > "$fixture/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >> "$FIXTURE/commands.log"
[ "${ZED_FAILURE_STAGE:-}" != curl ] || exit 91

output=""
while [ "$#" -gt 0 ]; do
    if [ "$1" = --output ]; then
        output=$2
        break
    fi
    shift
done
[ -n "$output" ]
printf 'fixture archive\n' > "$output"
EOF

cat > "$fixture/bin/tar" <<'EOF'
#!/usr/bin/env bash
printf 'tar %s\n' "$*" >> "$FIXTURE/commands.log"
[ "${ZED_FAILURE_STAGE:-}" != tar ] || exit 93

unpack_dir=""
while [ "$#" -gt 0 ]; do
    if [ "$1" = -C ]; then
        unpack_dir=$2
        break
    fi
    shift
done
[ -n "$unpack_dir" ]
printf 'fixture payload\n' > "$unpack_dir/payload"
EOF

chmod +x "$fixture/bin"/*
sed -i "1c#!${BASH}" "$fixture/bin"/*

run_hook() {
    local module_dir=$1
    shift
    env \
        PATH="$fixture/bin:$PATH" \
        FIXTURE="$fixture" \
        TMPDIR="$fixture/tmp" \
        NIXOS_FLAKE_PATH="$fixture/flake" \
        NIXOS_HOST_KEY=test \
        "$@" \
        bash "$project/$module_dir/update-flake-pre.sh"
}

# Every hook evaluates its boolean module option as JSON and honours keep without
# any remote release lookup, download, or metadata rewrite.
: > "$fixture/commands.log"
for module_dir in "${hooks[@]}"; do
    before="$(sha256sum "$project/$module_dir/release.json")"
    run_hook "$module_dir" FAIL_REMOTE=1 RELEASE_UPDATE_POLICY=keep > "$fixture/keep.out"
    after="$(sha256sum "$project/$module_dir/release.json")"
    [ "$before" = "$after" ]
done

[ "$(grep -c '^nix eval --json ' "$fixture/commands.log")" -eq 4 ]
if grep -Eq '^(gh|curl) ' "$fixture/commands.log"; then
    echo "keep policy performed a remote release lookup" >&2
    exit 1
fi
if grep -q '^nix eval --raw ' "$fixture/commands.log"; then
    echo "a release hook still evaluates a boolean option with --raw" >&2
    exit 1
fi

# A valid false value skips the remote release lookup; an evaluation error is
# visible and conservative rather than being coerced into a string.
gh_calls_before="$(grep -c '^gh ' "$fixture/commands.log" || true)"
run_hook modules/devtools/cli/rtk NIX_ENABLED=false RELEASE_UPDATE_POLICY=accept > "$fixture/disabled.out"
[ "$(grep -c '^gh ' "$fixture/commands.log" || true)" -eq "$gh_calls_before" ]
run_hook modules/devtools/ai/local-llm NIX_EVAL_FAIL=1 RELEASE_UPDATE_POLICY=accept > "$fixture/eval-failure.out"
grep -q 'Could not evaluate whether Ollama is enabled' "$fixture/eval-failure.out"
[ "$(grep -c '^gh ' "$fixture/commands.log" || true)" -eq "$gh_calls_before" ]

# Interactive mode is conservative when no answer can be read.
zed_release="$project/modules/devtools/ide/zed/release.json"
zed_before="$(sha256sum "$zed_release")"
run_hook modules/devtools/ide/zed < /dev/null > "$fixture/eof.out"
[ "$zed_before" = "$(sha256sum "$zed_release")" ]
grep -q 'No response received; keeping pinned Zed release' "$fixture/eof.out"

# Every fallible stage inside Zed's hash command substitution is fatal, leaves
# the atomic metadata file untouched, and removes every temporary artifact.
for failure_stage in curl tar hash; do
    zed_before="$(sha256sum "$zed_release")"
    if run_hook modules/devtools/ide/zed \
        RELEASE_UPDATE_POLICY=accept \
        ZED_FAILURE_STAGE="$failure_stage" \
        > "$fixture/zed-$failure_stage-failure.out" 2>&1; then
        echo "Zed hook masked a failed $failure_stage stage" >&2
        exit 1
    fi
    [ "$zed_before" = "$(sha256sum "$zed_release")" ]
    if find "$fixture/tmp" -mindepth 1 -print -quit | grep -q .; then
        echo "Zed hook leaked temporary files after a failed $failure_stage stage" >&2
        exit 1
    fi
done

# The same staged workspace supports both architecture assets on success and is
# still removed after the atomic metadata replacement.
run_hook modules/devtools/ide/zed RELEASE_UPDATE_POLICY=accept > "$fixture/zed-success.out"
[ "$(jq -r .tag "$zed_release")" = v999.0.0 ]
[ "$(jq -r '.assets["x86_64-linux"].hash' "$zed_release")" = sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA= ]
[ "$(jq -r '.assets["aarch64-linux"].hash' "$zed_release")" = sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA= ]
if find "$fixture/tmp" -mindepth 1 -print -quit | grep -q .; then
    echo "Zed hook leaked temporary files after a successful update" >&2
    exit 1
fi

# Accept is the only non-interactive policy that rewrites metadata.
run_hook modules/devtools/cli/rtk RELEASE_UPDATE_POLICY=accept > "$fixture/accept.out"
[ "$(jq -r .tag "$project/modules/devtools/cli/rtk/release.json")" = v999.0.0 ]

# Codex updates keep the CLI and code-mode host pinned to the same release.
codex_release="$project/modules/devtools/ai/codex/release.json"
run_hook modules/devtools/ai/codex RELEASE_UPDATE_POLICY=accept > "$fixture/codex-accept.out"
[ "$(jq -r .tag "$codex_release")" = rust-v999.0.0 ]
[ "$(jq -r '.assets["x86_64-linux"].codeModeHost.file' "$codex_release")" = codex-code-mode-host-x86_64-unknown-linux-musl.tar.gz ]
[ "$(jq -r '.assets["aarch64-linux"].codeModeHost.file' "$codex_release")" = codex-code-mode-host-aarch64-unknown-linux-musl.tar.gz ]

# Invalid policy values fail before any implicit decision is made.
if run_hook modules/devtools/ai/codex RELEASE_UPDATE_POLICY=invalid > "$fixture/invalid.out" 2>&1; then
    echo "invalid release policy unexpectedly succeeded" >&2
    exit 1
fi
grep -q 'Invalid release update policy' "$fixture/invalid.out"

echo 'release update hook tests passed'
