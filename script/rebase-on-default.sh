#!/bin/bash
set -euo pipefail

CURRENT_BRANCH=$(git branch --show-current)
if [ -z "$CURRENT_BRANCH" ]; then
    echo "Not on a branch; aborting."
    exit 1
fi

echo "Current branch: $CURRENT_BRANCH"

get_default_branch() {
    local detected

    detected=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)
    if [ -n "$detected" ]; then
        echo "${detected#origin/}"
        return
    fi

    detected=$(git remote show origin 2>/dev/null | sed -n '/HEAD branch/s/.*: //p' | head -n1)
    if [ -n "$detected" ]; then
        echo "$detected"
        return
    fi

    detected=$(git config --get init.defaultBranch || true)
    if [ -n "$detected" ]; then
        echo "$detected"
        return
    fi

    if git show-ref --verify --quiet refs/remotes/origin/main || git show-ref --verify --quiet refs/heads/main; then
        echo "main"
        return
    fi

    echo "master"
}

DEFAULT_BRANCH=$(get_default_branch)
REMOTE_DEFAULT_REF="origin/$DEFAULT_BRANCH"

echo "Fetching latest $REMOTE_DEFAULT_REF..."
git fetch origin "$DEFAULT_BRANCH"

if ! git show-ref --verify --quiet "refs/remotes/$REMOTE_DEFAULT_REF"; then
    echo "Could not find remote ref $REMOTE_DEFAULT_REF after fetch; aborting."
    exit 1
fi

COMMITS_BEHIND=$(git rev-list --count "HEAD..$REMOTE_DEFAULT_REF")
COMMITS_AHEAD=$(git rev-list --count "$REMOTE_DEFAULT_REF..HEAD")

if [ "$COMMITS_BEHIND" -gt 0 ] || [ "$COMMITS_AHEAD" -gt 0 ]; then
    echo "Branch status: $COMMITS_AHEAD commit(s) ahead, $COMMITS_BEHIND commit(s) behind $REMOTE_DEFAULT_REF"
else
    echo "Branch is up to date with $REMOTE_DEFAULT_REF"
fi

if [ "$COMMITS_BEHIND" -eq 0 ]; then
    echo "No rebase needed!"
    exit 0
fi

HAS_CHANGES=false
if ! git diff-index --quiet HEAD --; then
    echo "Stashing uncommitted changes..."
    git stash push -u -m "Auto-stash for rebase on $REMOTE_DEFAULT_REF"
    HAS_CHANGES=true
fi

echo "Rebasing $CURRENT_BRANCH on $REMOTE_DEFAULT_REF..."
if git rebase "$REMOTE_DEFAULT_REF"; then
    echo "Rebase completed successfully!"
    if [ "$HAS_CHANGES" = true ]; then
        echo "Restoring stashed changes..."
        git stash pop
    fi
else
    echo "Rebase failed. Resolve conflicts and continue with: git rebase --continue"
    if [ "$HAS_CHANGES" = true ]; then
        echo "Your changes are safely stashed. Use: git stash pop"
    fi
    exit 1
fi
