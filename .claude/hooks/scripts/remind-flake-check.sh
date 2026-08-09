#!/usr/bin/env bash
# Remind to run ./script/check.sh after .nix file modifications

set -euo pipefail

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")

if [[ "$file_path" =~ \.nix$ ]]; then
    echo "[reminder] Nix file modified. Run './script/check.sh' to validate."
fi

exit 0
