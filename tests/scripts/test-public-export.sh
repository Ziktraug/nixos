#!/usr/bin/env bash

set -euo pipefail

repo_root="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
export_script="$repo_root/script/export-public.sh"
safety_script="$repo_root/script/check-public-safety.sh"
fixture_dir="$(mktemp -d)"
fixture="$(realpath --canonicalize-existing -- "$fixture_dir")"

cleanup() {
  local status=$?

  rm -rf -- "$fixture_dir"
  exit "$status"
}
trap cleanup EXIT

fail() {
  printf 'public export test failed: %s\n' "$1" >&2
  exit 1
}

if [ ! -x "$export_script" ]; then
  fail 'export-public.sh is missing or not executable'
fi
if [ ! -x "$safety_script" ]; then
  fail 'check-public-safety.sh is missing or not executable'
fi

safe_tree="$fixture/safe-tree"
mkdir -p "$safe_tree"
printf '%s\n' 'contact = fixture@example.com' > "$safe_tree/example.nix"
if ! bash "$safety_script" "$safe_tree" > "$fixture/safe.out" 2>&1; then
  sed -n '1,20p' "$fixture/safe.out" >&2
  fail 'safe tree was rejected'
fi

assert_safety_rejects() {
  local name=$1
  local category=$2
  local value=$3
  local tree="$fixture/unsafe-$name"
  local output="$fixture/unsafe-$name.out"

  mkdir -p "$tree"
  printf '%s\n' "$value" > "$tree/finding.txt"
  if bash "$safety_script" "$tree" > "$output" 2>&1; then
    fail "$name fixture unexpectedly passed"
  fi
  if ! grep -F -q -- "category=$category" "$output"; then
    fail "$name fixture did not report $category"
  fi
}

private_key_marker='-----BEGIN '
private_key_marker+='OPENSSH PRIVATE KEY-----'
assert_safety_rejects private-key private-key-marker "$private_key_marker"

printf -v token_tail '%020d' 0
printf -v token_value '%s%s%s' gh p_ "$token_tail"
assert_safety_rejects token token-prefix "$token_value"

printf -v credential_url 'https:/''/%s:%s@%s.%s/repo' fixture-user fixture-pass example com
assert_safety_rejects credential-url credential-url "$credential_url"

printf -v secret_assignment '%s%s = %s' CLIENT _SECRET fixture-value
assert_safety_rejects secret-assignment secret-assignment "$secret_assignment"

printf -v non_example_email '%s@%s.%s' person private-domain net
assert_safety_rejects email non-example-email "$non_example_email"

printf -v private_home_path '/%s/%s' home private-user
assert_safety_rejects home home-path "$private_home_path"

printf -v hardware_uuid '%s-%s-%s-%s-%s' \
  12345678 1234 5678 9abc 123456789abc
assert_safety_rejects uuid hardware-uuid "$hardware_uuid"

printf -v hardware_serial '<%s>%s</%s>' serial fixture-device serial
assert_safety_rejects serial hardware-serial "$hardware_serial"

deny_tree="$fixture/deny-tree"
deny_file="$fixture/denylist.txt"
deny_output="$fixture/denylist.out"
mkdir -p "$deny_tree"
printf -v deny_value '%s%s%s' deny- fixture- private-value
printf '  # ignored comment\r\n\r\n-%s\r\n' "$deny_value" > "$deny_file"
deny_value="-$deny_value"
printf '\0prefix %s suffix\0' "$deny_value" > "$deny_tree/finding.bin"
mkdir -p "$deny_tree/$deny_value"
printf '%s\n' safe > "$deny_tree/$deny_value/path-only.txt"
if bash "$safety_script" "$deny_tree" --denylist "$deny_file" > "$deny_output" 2>&1; then
  fail 'denylist fixture unexpectedly passed'
fi
if ! grep -F -q -- 'category=private-denylist-match' "$deny_output"; then
  fail 'denylist fixture did not report its finding category'
fi
if ! grep -F -q -- 'finding.bin' "$deny_output"; then
  fail 'denylist fixture did not inspect binary content'
fi
if ! grep -F -q -- '\[redacted-private-path\]' "$deny_output"; then
  fail 'denylist fixture did not redact a matching path'
fi
if grep -F -q -- "$deny_value" "$deny_output"; then
  fail 'denylist value was written to checker output'
fi

source_repo="$fixture/source"
mkdir -p \
  "$source_repo/script" \
  "$source_repo/private" \
  "$source_repo/plans"
cp "$export_script" "$source_repo/script/export-public.sh"
cp "$safety_script" "$source_repo/script/check-public-safety.sh"
cp "$repo_root/.gitattributes" "$source_repo/.gitattributes"
cp "$repo_root/.gitleaks.toml" "$source_repo/.gitleaks.toml"
chmod +x \
  "$source_repo/script/export-public.sh" \
  "$source_repo/script/check-public-safety.sh"
printf '%s\n' 'public fixture' > "$source_repo/public.txt"
printf '%s\n' 'excluded private fixture' > "$source_repo/private/value.txt"
printf '%s\n' 'excluded plan fixture' > "$source_repo/plans/plan.md"

git -C "$source_repo" init -q
git -C "$source_repo" config user.name 'Fixture User'
git -C "$source_repo" config user.email fixture@example.com
git -C "$source_repo" add -A
git -C "$source_repo" commit -q -m 'Create export fixture'

gitleaks_stub="$fixture/gitleaks-stub"
gitleaks_calls="$fixture/gitleaks.calls"
touch "$gitleaks_calls"
cat > "$gitleaks_stub" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

tree=''
for argument in "$@"; do
  tree=$argument
done

[ -n "$tree" ]
[ -d "$tree" ]
[ -f "$tree/public.txt" ]
[ ! -e "$tree/private" ]
[ ! -e "$tree/plans" ]
printf '%s\n' called >> "${GITLEAKS_CALLS:?}"
EOF
chmod +x "$gitleaks_stub"
sed -i "1c#!${BASH}" "$gitleaks_stub"

if ! GITLEAKS_BIN="$gitleaks_stub" \
  GITLEAKS_CALLS="$gitleaks_calls" \
  bash "$source_repo/script/export-public.sh" --check-only \
  > "$fixture/check-only.out" 2>&1; then
  fail 'check-only export failed'
fi
if [ ! -s "$gitleaks_calls" ]; then
  fail 'check-only export did not scan its archive'
fi

target_repo="$fixture/target"
mkdir -p "$target_repo"
git -C "$target_repo" init -q
git -C "$target_repo" config user.name 'Fixture User'
git -C "$target_repo" config user.email fixture@example.com
printf '%s\n' 'remove only from validated target' > "$target_repo/stale.txt"
git -C "$target_repo" add stale.txt
git -C "$target_repo" commit -q -m 'Create target fixture'
printf '%s\n' 'preserve git metadata' > "$target_repo/.git/export-test-marker"

if ! env -u RSYNC_BIN \
  GITLEAKS_BIN="$gitleaks_stub" \
  GITLEAKS_CALLS="$gitleaks_calls" \
  bash "$source_repo/script/export-public.sh" \
  --target "$target_repo" \
  --revision HEAD \
  > "$fixture/target.out" 2>&1; then
  fail 'target export failed'
fi
if [ ! -f "$target_repo/public.txt" ]; then
  fail 'public file was not copied'
fi
if [ -e "$target_repo/stale.txt" ]; then
  fail 'stale target file was not removed'
fi
if [ ! -f "$target_repo/.git/export-test-marker" ]; then
  fail 'target Git metadata was not preserved'
fi
if [ -e "$target_repo/private" ] || [ -e "$target_repo/plans" ]; then
  fail 'archive exclusions were copied to the target'
fi

rsync_stub="$fixture/rsync-must-not-run"
rsync_calls="$fixture/rsync.calls"
cat > "$rsync_stub" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' called >> "${RSYNC_CALLS:?}"
exit 97
EOF
chmod +x "$rsync_stub"
sed -i "1c#!${BASH}" "$rsync_stub"

assert_target_rejected_without_rsync() {
  local name=$1
  local target=$2
  local output="$fixture/rejected-$name.out"

  : > "$rsync_calls"
  if GITLEAKS_BIN="$gitleaks_stub" \
    GITLEAKS_CALLS="$gitleaks_calls" \
    RSYNC_BIN="$rsync_stub" \
    RSYNC_CALLS="$rsync_calls" \
    bash "$source_repo/script/export-public.sh" --target "$target" \
    > "$output" 2>&1; then
    fail "$name target unexpectedly passed"
  fi
  if [ -s "$rsync_calls" ]; then
    fail "$name target reached the destructive copy backend"
  fi
}

no_git_target="$fixture/no-git-target"
mkdir -p "$no_git_target"
assert_target_rejected_without_rsync empty ''
assert_target_rejected_without_rsync root /
assert_target_rejected_without_rsync source "$source_repo"
assert_target_rejected_without_rsync no-git "$no_git_target"

printf '%s\n' 'public export tests passed'
