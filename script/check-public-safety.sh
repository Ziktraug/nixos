#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Usage: %s <tree> [--denylist <private-file>]\n' "${0##*/}" >&2
  exit 2
}

if [ "$#" -lt 1 ]; then
  usage
fi

tree_input=$1
shift
denylist_input=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --denylist)
      [ "$#" -ge 2 ] || usage
      denylist_input=$2
      shift 2
      ;;
    *) usage ;;
  esac
done

if [ -z "$tree_input" ]; then
  printf 'Safety check refused an empty tree path\n' >&2
  exit 2
fi

tree_lexical="$(realpath --canonicalize-missing --no-symlinks -- "$tree_input")"
if ! tree="$(realpath --canonicalize-existing -- "$tree_input" 2>/dev/null)"; then
  printf 'Safety check refused an unresolved tree path\n' >&2
  exit 2
fi

if [ ! -d "$tree" ] || [ "$tree" = / ] || [ "$tree_lexical" != "$tree" ]; then
  printf 'Safety check refused an unsafe tree path\n' >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source_repo="$(git -C "$script_dir/.." rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$source_repo" ]; then
  source_repo="$(realpath --canonicalize-existing -- "$source_repo")"
fi

if [ -n "${PUBLICATION_SOURCE_REPO:-}" ]; then
  if ! declared_source="$(realpath --canonicalize-existing -- "$PUBLICATION_SOURCE_REPO" 2>/dev/null)"; then
    printf 'Safety check refused an unresolved source repository\n' >&2
    exit 2
  fi
  if [ "$tree" = "$declared_source" ]; then
    printf 'Safety check refused the canonical source repository\n' >&2
    exit 2
  fi
elif [ -n "$source_repo" ] && [ "$tree" = "$source_repo" ] && [ -e "$tree/private" ]; then
  printf 'Safety check refused the private source repository\n' >&2
  exit 2
fi

denylist=""
if [ -n "$denylist_input" ]; then
  if ! denylist="$(realpath --canonicalize-existing -- "$denylist_input" 2>/dev/null)"; then
    printf 'Safety check refused an unresolved denylist\n' >&2
    exit 2
  fi
  if [ ! -f "$denylist" ] || [ ! -r "$denylist" ]; then
    printf 'Safety check refused an unreadable denylist\n' >&2
    exit 2
  fi
fi

findings=0

relative_path() {
  local path=$1
  printf '%s\n' "${path#"$tree"/}"
}

report_finding() {
  local category=$1
  local path=$2
  local relative
  relative="$(relative_path "$path")"
  printf 'public-safety finding category=%s path=' "$category" >&2
  printf '%q\n' "$relative" >&2
  findings=$((findings + 1))
}

report_denylist_finding() {
  local path=$1
  local private_value=$2
  local relative

  relative="$(relative_path "$path")"
  if [[ "$relative" == *"$private_value"* ]]; then
    relative='[redacted-private-path]'
  fi
  printf 'public-safety finding category=private-denylist-match path=' >&2
  printf '%q\n' "$relative" >&2
  findings=$((findings + 1))
}

is_allowed_email() {
  local email=$1
  local relative=$2
  local app_indicator_email
  local protonvpn_systemd_unit

  # Keep the single upstream extension UUID path-scoped without embedding the
  # complete non-example address in this scanner's own source.
  app_indicator_email='appindicatorsupport@'
  app_indicator_email+='rgcjonas.gmail.com'
  protonvpn_systemd_unit='gnome-session@'
  protonvpn_systemd_unit+='gnome.target'

  case "$email" in
    *@example.com | *@example.org | *@users.noreply.github.com | git@github.com) return 0 ;;
  esac

  if [ "$relative" = modules/ui/gnome/default.nix ] &&
    [ "$email" = "$app_indicator_email" ]; then
    return 0
  fi

  # This is a systemd unit name, not an email address.
  if [ "$relative" = modules/services/networking/protonvpn/default.nix ] &&
    [ "$email" = "$protonvpn_systemd_unit" ]; then
    return 0
  fi

  return 1
}

while IFS= read -r -d '' path; do
  relative="$(relative_path "$path")"
  case "/$relative" in
    /private | /private/*)
      report_finding private-subtree "$path"
      ;;
    /.env | */.env | /.env.* | */.env.* | */settings.local.json | */events.jsonl)
      report_finding local-state-path "$path"
      ;;
    */.bash_history | */.zsh_history | */.python_history | *.history | *.sqlite | *.sqlite3 | *.db)
      report_finding local-history-path "$path"
      ;;
    */id_rsa | */id_dsa | */id_ecdsa | */id_ed25519 | *.pem | *.p12 | *.pfx | *.key)
      report_finding private-key-path "$path"
      ;;
  esac
done < <(
  find "$tree" -path "$tree/.git" -prune -o \( -type f -o -type l \) -print0
)

while IFS= read -r -d '' path; do
  report_finding symlink "$path"
done < <(find "$tree" -path "$tree/.git" -prune -o -type l -print0)

known_prefix_pattern='gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|glpat-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{20,}'
credential_url_pattern='://[^[:space:]/:@]+:'
credential_url_pattern+='[^[:space:]/@]+@'
assignment_pattern='(password|passwd|api[_-]?key|client[_-]?secret|access[_-]?token)[[:space:]]*[:=][[:space:]]*[[:graph:]]{4,}'
email_pattern='[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}'
uuid_pattern='[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}'
home_pattern='/home/[[:alnum:]_.-]+'

while IFS= read -r -d '' path; do
  if [ ! -s "$path" ]; then
    continue
  fi

  relative="$(relative_path "$path")"

  if LC_ALL=C grep -a -q -E -- '-----BEGIN (OPENSSH|RSA|DSA|EC|PGP) PRIVATE KEY-----' "$path"; then
    report_finding private-key-marker "$path"
  fi
  if LC_ALL=C grep -a -q -E -- "$known_prefix_pattern" "$path"; then
    report_finding token-prefix "$path"
  fi
  if LC_ALL=C grep -a -q -E -- "$credential_url_pattern" "$path"; then
    report_finding credential-url "$path"
  fi
  if LC_ALL=C grep -a -q -i -E -- "$assignment_pattern" "$path"; then
    report_finding secret-assignment "$path"
  fi
  if LC_ALL=C grep -a -q -E -- "$home_pattern" "$path"; then
    report_finding home-path "$path"
  fi
  if LC_ALL=C grep -a -q -E -- "$uuid_pattern" "$path"; then
    report_finding hardware-uuid "$path"
  fi
  if LC_ALL=C grep -a -q -E -- '<serial([[:space:]][^>]*)?>' "$path"; then
    report_finding hardware-serial "$path"
  fi

  while IFS= read -r email; do
    [ -n "$email" ] || continue
    if ! is_allowed_email "$email" "$relative"; then
      report_finding non-example-email "$path"
      break
    fi
  done < <(LC_ALL=C grep -a -E -o -- "$email_pattern" "$path" 2>/dev/null | sort -u || true)

  if awk '
    BEGIN { in_user = 0; bad = 0 }
    /^[[:space:]]*\[user\][[:space:]]*$/ { in_user = 1; next }
    /^[[:space:]]*\[/ { in_user = 0 }
    in_user && /^[[:space:]]*name[[:space:]]*=/ {
      value = $0
      sub(/^[^=]*=[[:space:]]*/, "", value)
      if (value !~ /^(Alice Example|Example User|Fixture User|Your Name)$/) bad = 1
    }
    END { exit bad ? 0 : 1 }
  ' "$path"; then
    report_finding git-user-identity "$path"
  fi
done < <(find "$tree" -path "$tree/.git" -prune -o -type f -print0)

if [ -n "$denylist" ]; then
  while IFS= read -r private_value || [ -n "$private_value" ]; do
    private_value="${private_value%$'\r'}"
    if [[ "$private_value" =~ ^[[:space:]]*$ ]] ||
      [[ "$private_value" =~ ^[[:space:]]*# ]]; then
      continue
    fi
    [ "${#private_value}" -ge 4 ] || continue

    while IFS= read -r -d '' path; do
      relative="$(relative_path "$path")"
      if [[ "$relative" == *"$private_value"* ]]; then
        report_denylist_finding "$path" "$private_value"
      fi
    done < <(find "$tree" -mindepth 1 -path "$tree/.git" -prune -o -print0)

    while IFS= read -r -d '' path; do
      [ "$path" = "$denylist" ] && continue
      report_denylist_finding "$path" "$private_value"
    done < <(
      find "$tree" -path "$tree/.git" -prune -o -type f -print0 |
        xargs -0 -r grep -F -l -Z -- "$private_value" 2>/dev/null || true
    )
  done < "$denylist"
fi

if [ "$findings" -ne 0 ]; then
  printf 'Public safety check failed with %s finding(s)\n' "$findings" >&2
  exit 1
fi

printf 'Public safety check passed\n'
