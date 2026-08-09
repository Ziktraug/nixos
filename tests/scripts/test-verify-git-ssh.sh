#!/usr/bin/env bash

set -euo pipefail

repo_root="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
script="$repo_root/script/verify-git-ssh.sh"
fixture="$(mktemp -d)"

cleanup() {
  local status=$?
  local output

  if [ "$status" -ne 0 ]; then
    for output in "$fixture"/*.out; do
      [ -f "$output" ] || continue
      printf '%s\n' "--- $output ---" >&2
      sed -n '1,240p' "$output" >&2
    done
  fi
  rm -rf "$fixture"
  exit "$status"
}
trap cleanup EXIT

home="$fixture/home"
repository_root="$fixture/repositories"
config_source="$fixture/identity.gitconfig"
private_key="$home/.ssh/id_ed25519-work"
mkdir -p "$home/.ssh" "$repository_root"

printf 'private fixture\n' > "$private_key"
printf 'public fixture\n' > "$private_key.pub"
chmod 600 "$private_key"
chmod 644 "$private_key.pub"

cat > "$config_source" <<'EOF'
[user]
    name = Fixture User
    email = fixture@example.com
[core]
    sshCommand = ssh -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519-work
EOF

success_ssh="$fixture/ssh-success"
cat > "$success_ssh" <<'EOF'
#!/usr/bin/env bash
case " $* " in
  *' -o IdentitiesOnly=yes '*) ;;
  *)
    printf 'missing IdentitiesOnly=yes: %s\n' "$*" >&2
    exit 90
    ;;
esac
printf "Hi fixture! You've successfully authenticated, but the service does not provide shell access.\n" >&2
exit 1
EOF

unexpected_ssh="$fixture/ssh-unexpected"
cat > "$unexpected_ssh" <<'EOF'
#!/usr/bin/env bash
printf 'ssh: connection timed out\n' >&2
exit 255
EOF

sed -i "1c#!${BASH}" "$success_ssh" "$unexpected_ssh"
chmod +x "$success_ssh" "$unexpected_ssh"

# Omitting both supported config inputs must fail clearly.
if env -u GIT_SSH_CONFIG_SOURCE -u WORK_GITHUB_CONFIG_SOURCE \
  HOME="$home" \
  GIT_CONFIG_NOSYSTEM=1 \
  GIT_REPOSITORY_ROOT="$repository_root" \
  SSH_BIN="$success_ssh" \
  bash "$script" > "$fixture/missing-config.out" 2>&1; then
  echo 'missing Git config unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'Git config path is required' "$fixture/missing-config.out"

# The environment-variable interface works without consulting repository files.
HOME="$home" \
GIT_CONFIG_NOSYSTEM=1 \
GIT_REPOSITORY_ROOT="$repository_root" \
GIT_SSH_CONFIG_SOURCE="$config_source" \
SSH_BIN="$success_ssh" \
  bash "$script" > "$fixture/no-repository.out"
grep -q 'No Git repositories found to test' "$fixture/no-repository.out"
grep -q 'All checks passed' "$fixture/no-repository.out"

HOME="$home" GIT_CONFIG_NOSYSTEM=1 git -C "$repository_root" init -q repository
HOME="$home" GIT_CONFIG_NOSYSTEM=1 \
  git -C "$repository_root/repository" config user.email fixture@example.com
HOME="$home" GIT_CONFIG_NOSYSTEM=1 \
  git -C "$repository_root/repository" config core.sshCommand \
  'ssh -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519-work'

# A positional config path takes precedence and validates a fully temporary repo.
env -u GIT_SSH_CONFIG_SOURCE -u WORK_GITHUB_CONFIG_SOURCE \
  HOME="$home" \
  GIT_CONFIG_NOSYSTEM=1 \
  GIT_REPOSITORY_ROOT="$repository_root" \
  SSH_BIN="$success_ssh" \
  bash "$script" "$config_source" > "$fixture/success.out"
grep -q 'All checks passed' "$fixture/success.out"

if HOME="$home" \
  GIT_CONFIG_NOSYSTEM=1 \
  GIT_REPOSITORY_ROOT="$repository_root" \
  GIT_SSH_CONFIG_SOURCE="$config_source" \
  SSH_BIN="$unexpected_ssh" \
  bash "$script" > "$fixture/unexpected.out" 2>&1; then
  echo 'unexpected SSH response was reported as success' >&2
  exit 1
fi
grep -q 'Unexpected response' "$fixture/unexpected.out"

echo "verify-git-ssh tests passed"
