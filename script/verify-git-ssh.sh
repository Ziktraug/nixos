#!/usr/bin/env bash
# Verify the per-directory Git identity and SSH key declared by this repository.

set -uo pipefail

if [ "$#" -gt 1 ]; then
  printf 'Usage: %s [git-config-path]\n' "${0##*/}" >&2
  exit 2
fi

GIT_SSH_CONFIG_SOURCE="${1:-${GIT_SSH_CONFIG_SOURCE:-${WORK_GITHUB_CONFIG_SOURCE:-}}}"
GIT_REPOSITORY_ROOT="${GIT_REPOSITORY_ROOT:-${WORK_GITHUB_DIR:-$HOME/Projects/Work/Github}}"
GIT_SSH_HOST="${GIT_SSH_HOST:-github.com}"
SSH_BIN="${SSH_BIN:-ssh}"
GIT_BIN="${GIT_BIN:-git}"

BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

ALL_OK=true
EXPECTED_EMAIL=""
EXPECTED_SSH_COMMAND=""
EXPECTED_KEY=""

expand_home_path() {
  local value=$1
  if [[ $value == \~/* ]]; then
    printf '%s/%s\n' "$HOME" "${value#\~/}"
  else
    printf '%s\n' "$value"
  fi
}

identity_file_from_command() {
  local command=$1
  local -a parts=()
  local index

  read -r -a parts <<< "$command"
  for ((index = 0; index < ${#parts[@]}; index++)); do
    if [ "${parts[$index]}" = "-i" ] && [ $((index + 1)) -lt ${#parts[@]} ]; then
      printf '%s\n' "${parts[$((index + 1))]}"
      return 0
    fi
    if [[ "${parts[$index]}" == -i?* ]]; then
      printf '%s\n' "${parts[$index]#-i}"
      return 0
    fi
  done
  return 1
}

load_expected_config() {
  local configured_key

  if [ -z "$GIT_SSH_CONFIG_SOURCE" ]; then
    printf "  ${RED}✗${NC} Git config path is required (argument or GIT_SSH_CONFIG_SOURCE)\n"
    ALL_OK=false
    return 1
  fi

  if [ ! -f "$GIT_SSH_CONFIG_SOURCE" ]; then
    printf "  ${RED}✗${NC} Git config not found: %s\n" "$GIT_SSH_CONFIG_SOURCE"
    ALL_OK=false
    return 1
  fi

  EXPECTED_EMAIL="$($GIT_BIN config --file "$GIT_SSH_CONFIG_SOURCE" --get user.email 2>/dev/null || true)"
  EXPECTED_SSH_COMMAND="$($GIT_BIN config --file "$GIT_SSH_CONFIG_SOURCE" --get core.sshCommand 2>/dev/null || true)"
  configured_key="$(identity_file_from_command "$EXPECTED_SSH_COMMAND" || true)"

  if [ -z "$EXPECTED_EMAIL" ] || [ -z "$configured_key" ]; then
    printf "  ${RED}✗${NC} Git config must declare user.email and core.sshCommand -i\n"
    ALL_OK=false
    return 1
  fi

  EXPECTED_KEY="$(expand_home_path "$configured_key")"
}

check_ssh_key() {
  local key_path=$1
  local key_name=$2
  local perms
  local expected_perms

  printf "${BOLD}Checking: %s${NC}\n" "$key_name"

  if [ ! -f "$key_path" ]; then
    printf "  ${RED}✗${NC} Key not found: %s\n" "$key_path"
    printf "    ${YELLOW}→${NC} See docs/git-ssh-configuration.md for setup instructions\n"
    ALL_OK=false
    return 0
  fi

  perms="$(stat -c '%a' "$key_path")"
  if [[ "$key_path" == *.pub ]]; then
    expected_perms=644
  else
    expected_perms=600
  fi

  if [ "$perms" != "$expected_perms" ]; then
    printf "  ${RED}✗${NC} Incorrect permissions: %s (expected %s)\n" "$perms" "$expected_perms"
    printf "    ${YELLOW}→${NC} Fix with: chmod %s %s\n" "$expected_perms" "$key_path"
    ALL_OK=false
    return 0
  fi

  printf "  ${GREEN}✓${NC} Key exists with correct permissions (%s)\n" "$perms"
}

test_ssh_connection() {
  local key_path=$1
  local host=$2
  local description=$3
  local output
  local ssh_status
  local username

  printf "\n${BOLD}Testing SSH connection: %s${NC}\n" "$description"

  if [ ! -f "$key_path" ]; then
    printf "  ${YELLOW}⊘${NC} Skipped (key not found)\n"
    return 0
  fi

  output="$($SSH_BIN -o BatchMode=yes -o ConnectTimeout=10 -o IdentitiesOnly=yes -i "$key_path" -T "git@$host" 2>&1)"
  ssh_status=$?

  if grep -q "successfully authenticated" <<< "$output"; then
    username="$(sed -n 's/^Hi \([^!]*\)!.*/\1/p' <<< "$output" | head -n 1)"
    printf "  ${GREEN}✓${NC} Connected successfully as: %s\n" "${username:-unknown}"
  elif grep -q "Permission denied" <<< "$output"; then
    printf "  ${RED}✗${NC} Permission denied\n"
    printf "    ${YELLOW}→${NC} Key may not be added to %s\n" "$host"
    ALL_OK=false
  elif grep -q "UNPROTECTED PRIVATE KEY" <<< "$output"; then
    printf "  ${RED}✗${NC} Key permissions too open\n"
    printf "    ${YELLOW}→${NC} Fix with: chmod 600 %s\n" "$key_path"
    ALL_OK=false
  else
    printf "  ${RED}?${NC} Unexpected response (ssh exit %s): %s\n" "$ssh_status" "$output"
    ALL_OK=false
  fi
}

check_git_config() {
  local test_dir=$1
  local expected_email=$2
  local expected_ssh=$3
  local description=$4
  local actual_email
  local actual_ssh

  printf "\n${BOLD}Checking Git config: %s${NC}\n" "$description"

  if [ ! -d "$test_dir" ]; then
    printf "  ${YELLOW}⊘${NC} Skipped (directory not found: %s)\n" "$test_dir"
    return 0
  fi

  actual_email="$($GIT_BIN -C "$test_dir" config --get user.email 2>/dev/null || true)"
  if [ "$actual_email" = "$expected_email" ]; then
    printf "  ${GREEN}✓${NC} Email: %s\n" "$actual_email"
  else
    printf "  ${RED}✗${NC} Email: %s (expected: %s)\n" "${actual_email:-"(not set)"}" "$expected_email"
    printf "    ${YELLOW}→${NC} Check includeIf directives in ~/.gitconfig\n"
    ALL_OK=false
  fi

  actual_ssh="$($GIT_BIN -C "$test_dir" config --get core.sshCommand 2>/dev/null || true)"
  if [ "$actual_ssh" = "$expected_ssh" ]; then
    printf "  ${GREEN}✓${NC} SSH command: %s\n" "$actual_ssh"
  else
    printf "  ${RED}✗${NC} SSH command: %s\n" "${actual_ssh:-"(not set)"}"
    printf "    ${YELLOW}→${NC} Expected: %s\n" "$expected_ssh"
    ALL_OK=false
  fi
}

printf "${BOLD}Git SSH Configuration Verification${NC}\n\n"

if load_expected_config; then
  printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
  printf "${BOLD}1. SSH Key Files${NC}\n"
  printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
  check_ssh_key "$EXPECTED_KEY" "Configured identity (private)"
  check_ssh_key "$EXPECTED_KEY.pub" "Configured identity (public)"

  printf '\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
  printf "${BOLD}2. SSH Connection${NC}\n"
  printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
  test_ssh_connection "$EXPECTED_KEY" "$GIT_SSH_HOST" "Configured Git host"

  printf '\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
  printf "${BOLD}3. Git Configuration${NC}\n"
  printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'

  repository_git_dir=""
  if [ -d "$GIT_REPOSITORY_ROOT" ]; then
    repository_git_dir="$(find "$GIT_REPOSITORY_ROOT" -maxdepth 2 -name .git -type d -print -quit)"
  fi

  if [ -n "$repository_git_dir" ]; then
    check_git_config "$(dirname "$repository_git_dir")" "$EXPECTED_EMAIL" "$EXPECTED_SSH_COMMAND" "Configured Git repository"
  else
    printf "\n${YELLOW}⊘${NC} No Git repositories found to test\n"
    printf "  ${YELLOW}→${NC} Clone a repository under %s to test includeIf resolution\n" "$GIT_REPOSITORY_ROOT"
  fi
fi

printf '\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
printf "${BOLD}Summary${NC}\n"
printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'

if [ "$ALL_OK" = true ]; then
  printf "${GREEN}✓${NC} All checks passed!\n"
else
  printf "${RED}✗${NC} Some checks failed. See above for details.\n"
  printf "\n${BOLD}Documentation:${NC} docs/git-ssh-configuration.md\n"
  exit 1
fi
