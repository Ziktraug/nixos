#!/usr/bin/env bash

# Zen Browser Configuration Setup Script
# Sync managed Zen config files into the active Zen profile

set -euo pipefail

NIXOS_REPO="${NIXOS_REPO:-$HOME/Projects/Github/nixos}"
ZEN_CONFIG_DIR="$HOME/.zen"
DOTFILES_DIR="${DOTFILES_DIR:-$NIXOS_REPO/modules/browsers/zen-browser}"

echo "Zen Browser Configuration Setup"
echo "================================"
echo "Config directory: $ZEN_CONFIG_DIR"
echo "Dotfiles source: $DOTFILES_DIR"
echo ""

# Check if Zen config directory exists
if [ ! -d "$ZEN_CONFIG_DIR" ]; then
    echo "Zen config directory not found: $ZEN_CONFIG_DIR"
    echo "Launch Zen once, then run this script again."
    exit 0
fi

# Resolve default profile from profiles.ini when available
PROFILE_DIR=""
PROFILES_INI="$ZEN_CONFIG_DIR/profiles.ini"

if [ -f "$PROFILES_INI" ]; then
    DEFAULT_PATH=$(awk -F= '
        BEGIN {
            found = 0
        }
        /^\[Profile[0-9]+\]$/ {
            if (in_profile && is_default == 1 && profile_path != "") {
                print profile_path
                found = 1
                exit
            }
            in_profile = 1
            is_default = 0
            profile_path = ""
            next
        }
        /^\[/ {
            if (in_profile && is_default == 1 && profile_path != "") {
                print profile_path
                found = 1
                exit
            }
            in_profile = 0
            next
        }
        in_profile && $1 == "Path" { profile_path = $2 }
        in_profile && $1 == "Default" { is_default = ($2 == "1") }
        END {
            if (!found && in_profile && is_default == 1 && profile_path != "") {
                print profile_path
            }
        }
    ' "$PROFILES_INI")

    if [ -n "$DEFAULT_PATH" ]; then
        PROFILE_DIR="$ZEN_CONFIG_DIR/$DEFAULT_PATH"
    fi
fi

# Fallback if profiles.ini is missing or no default profile is marked
if [ -z "$PROFILE_DIR" ]; then
    PROFILE_DIR=$(find "$ZEN_CONFIG_DIR" -maxdepth 1 -type d -iname "*Default*" ! -name "Profile Groups" 2>/dev/null | head -1)
fi

if [ -z "$PROFILE_DIR" ]; then
    echo "No Zen profile directory found."
    echo ""
    echo "Available directories in $ZEN_CONFIG_DIR:"
    ls -la "$ZEN_CONFIG_DIR" 2>/dev/null || echo "  (none)"
    echo ""
    echo "Launch Zen browser first to create a profile."
    exit 0
fi

echo "Found profile directory: $PROFILE_DIR"

# Sync files from dotfiles into active profile
sync_file() {
    local rel_path="$1"
    local source_file="$DOTFILES_DIR/$rel_path"
    local target_file="$PROFILE_DIR/$rel_path"
    local target_dir
    target_dir=$(dirname "$target_file")

    if [ ! -f "$source_file" ]; then
        echo "Skipping missing source: $source_file"
        return 0
    fi

    mkdir -p "$target_dir"

    if [ -f "$target_file" ] && cmp -s "$source_file" "$target_file"; then
        echo "Up to date: $target_file"
    else
        cp "$source_file" "$target_file"
        echo "Updated: $target_file"
    fi
}

sync_file "user.js"
sync_file "chrome/userChrome.css"
sync_file "chrome/userContent.css"

echo ""
echo "Done! Restart Zen browser to apply changes."
