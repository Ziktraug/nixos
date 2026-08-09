#!/usr/bin/env bash
# Validate Nix files after modification
# Called by Claude Code hooks

set -euo pipefail

# Read input from stdin (hook provides JSON)
input=$(cat)

# Extract file path from hook input
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")

# Only validate .nix files
if [[ ! "$file_path" =~ \.nix$ ]]; then
    exit 0
fi

# Run syntax check
if command -v nix-instantiate &> /dev/null; then
    if ! nix-instantiate --parse "$file_path" &> /dev/null; then
        echo "[hook] Syntax error in $file_path - run 'nix-instantiate --parse $file_path' for details"
        exit 1
    fi
fi

exit 0
