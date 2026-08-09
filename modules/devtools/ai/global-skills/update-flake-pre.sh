#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="$SCRIPT_DIR/.cache"
TARGET_DIR="$CACHE_DIR/matt-pocock-skills"
ORIGIN="https://github.com/mattpocock/skills.git"
PINNED_REV="2ab958093e83e0ec752e6c1c5932da465bf23e0c"

echo "Materializing pinned Matt Pocock skills..."

if [ -L "$CACHE_DIR" ] || [ -L "$TARGET_DIR" ]; then
  echo "Refusing symbolic-link skills cache: $TARGET_DIR" >&2
  exit 1
fi
mkdir -p "$CACHE_DIR"

if [ -e "$TARGET_DIR" ] && [ ! -d "$TARGET_DIR/.git" ]; then
  echo "Refusing non-Git skills cache: $TARGET_DIR" >&2
  exit 1
fi

if [ ! -d "$TARGET_DIR/.git" ]; then
  mkdir -p "$TARGET_DIR"
  git -C "$TARGET_DIR" init
fi

if git -C "$TARGET_DIR" remote get-url origin >/dev/null 2>&1; then
  git -C "$TARGET_DIR" remote set-url origin "$ORIGIN"
else
  git -C "$TARGET_DIR" remote add origin "$ORIGIN"
fi

if ! git -C "$TARGET_DIR" cat-file -e "$PINNED_REV^{commit}" 2>/dev/null; then
  git -C "$TARGET_DIR" fetch --depth 1 origin "$PINNED_REV"
fi

git -C "$TARGET_DIR" checkout --detach "$PINNED_REV"
git -C "$TARGET_DIR" reset --hard "$PINNED_REV"
git -C "$TARGET_DIR" clean -fd

actual_rev="$(git -C "$TARGET_DIR" rev-parse HEAD)"
if [ "$actual_rev" != "$PINNED_REV" ]; then
  echo "Matt Pocock skills revision mismatch: expected $PINNED_REV, got $actual_rev" >&2
  exit 1
fi

if [ ! -d "$TARGET_DIR/skills" ]; then
  echo "Matt Pocock skills checkout is missing skills/" >&2
  exit 1
fi

echo "Matt Pocock skills cache ready at $PINNED_REV"
