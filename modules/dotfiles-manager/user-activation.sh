#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 7 ]; then
    echo "Usage: $0 USER HOME MODULE MAPPING SOURCE TARGET EXECUTABLE" >&2
    exit 2
fi

expected_user=$1
user_home=${2%/}
module_name=$3
mapping_name=$4
source_path=$5
target_path=$6
executable=$7
backup_dir="$user_home/.dotfiles-backups"

if [ "$(id -un)" != "$expected_user" ]; then
    echo "Error: ${module_name}.${mapping_name} must run as $expected_user, not $(id -un)" >&2
    exit 1
fi
if [ ! -d "$user_home" ] || [ -L "$user_home" ]; then
    echo "Error: user home must be a real directory: $user_home" >&2
    exit 1
fi
case "$target_path" in
    "$user_home"/*) ;;
    *) echo "Error: target is outside $user_home: $target_path" >&2; exit 1 ;;
esac
if [ ! -f "$source_path" ]; then
    echo "Error: checkout source unavailable for ${module_name}.${mapping_name}: $source_path" >&2
    exit 1
fi
if [ "$executable" = 1 ] && [ ! -x "$source_path" ]; then
    echo "Error: ${module_name}.${mapping_name} requires an executable checkout source: $source_path" >&2
    exit 1
fi

ensure_real_parent_path() {
    local target_dir=$1
    local relative=${target_dir#"$user_home"/}
    local current=$user_home
    local part

    IFS=/ read -r -a parts <<< "$relative"
    for part in "${parts[@]}"; do
        [ -n "$part" ] || continue
        if [ "$part" = . ] || [ "$part" = .. ]; then
            echo "Error: refusing relative parent component for ${module_name}.${mapping_name}: $part" >&2
            return 1
        fi
        current="$current/$part"
        if [ -L "$current" ]; then
            echo "Error: refusing symlinked parent for ${module_name}.${mapping_name}: $current" >&2
            return 1
        fi
        if [ -e "$current" ] && [ ! -d "$current" ]; then
            echo "Error: parent component is not a directory for ${module_name}.${mapping_name}: $current" >&2
            return 1
        fi
        mkdir -p -- "$current"
    done
}

ensure_real_parent_path "$(dirname "$target_path")"

if [ -e "$target_path" ] && [ ! -L "$target_path" ]; then
    if cmp -s -- "$source_path" "$target_path"; then
        echo "Identical target needs no backup: $target_path (source: $source_path)"
        rm -- "$target_path"
    else
        relative_target=${target_path#"$user_home"/}
        safe_target=${relative_target//\//_}
        safe_module=$(printf '%s' "$module_name" | tr -c 'A-Za-z0-9._-' _)
        safe_mapping=$(printf '%s' "$mapping_name" | tr -c 'A-Za-z0-9._-' _)
        mkdir -p -- "$backup_dir"
        backup_slot=$(mktemp -d -- "$backup_dir/${safe_module}--${safe_mapping}--${safe_target}.$(date +%Y%m%d-%H%M%S).XXXXXX")
        backup_path="$backup_slot/original"
        mv -T -- "$target_path" "$backup_path"
        printf 'Conflict for %s.%s\n  source: %s\n  target: %s\n  backup: %s\n' \
            "$module_name" "$mapping_name" "$source_path" "$target_path" "$backup_path"
        printf '  review: diff -u -- %q %q\n' "$backup_path" "$source_path"
    fi
elif [ -L "$target_path" ]; then
    current_link=$(readlink -f -- "$target_path" 2>/dev/null || true)
    if [ "$current_link" = "$source_path" ]; then
        echo "Already linked: $target_path -> $source_path"
        exit 0
    fi
    rm -- "$target_path"
fi

ln -s -- "$source_path" "$target_path"
echo "Linked ${module_name}.${mapping_name}: $target_path -> $source_path"
