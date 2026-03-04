#!/bin/bash
# DTK — Project Context Detector
# Outputs JSON with project identity, git info, and branch data.
# Usage: bash project-context.sh [--base-branch main]

set -euo pipefail

BASE_BRANCH="${1:-}"

# Parse named args
while [[ $# -gt 0 ]]; do
  case $1 in
    --base-branch) BASE_BRANCH="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# Project root (git root or cwd)
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# Git remote
REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")

# Extract owner/repo from remote URL
GIT_OWNER=""
GIT_REPO=""
if [[ -n "$REMOTE_URL" ]]; then
  # Handles both SSH (git@github.com:owner/repo.git) and HTTPS (https://github.com/owner/repo.git)
  GIT_OWNER=$(echo "$REMOTE_URL" | sed -E 's#.*[:/]([^/]+)/[^/]+\.git$#\1#; s#.*[:/]([^/]+)/[^/]+$#\1#')
  GIT_REPO=$(echo "$REMOTE_URL" | sed -E 's#.*/([^/]+)\.git$#\1#; s#.*/([^/]+)$#\1#')
fi

# Current branch
CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || echo "unknown")

# Default base branch detection
if [[ -z "$BASE_BRANCH" ]]; then
  if git rev-parse --verify main >/dev/null 2>&1; then
    BASE_BRANCH="main"
  elif git rev-parse --verify master >/dev/null 2>&1; then
    BASE_BRANCH="master"
  elif git rev-parse --verify develop >/dev/null 2>&1; then
    BASE_BRANCH="develop"
  else
    BASE_BRANCH="main"
  fi
fi

# Task ID from branch name (common patterns: XX-123, PROJ-456, feat/XX-123)
TASK_ID=$(echo "$CURRENT_BRANCH" | grep -oP '[A-Z]{2,}-\d+' | head -1 || echo "")

# Changed files count (branch vs base)
CHANGED_FILES_COUNT=$(git diff --name-only "${BASE_BRANCH}...HEAD" 2>/dev/null | wc -l || echo "0")

# Uncommitted changes
UNSTAGED_COUNT=$(git diff --name-only 2>/dev/null | wc -l || echo "0")
STAGED_COUNT=$(git diff --cached --name-only 2>/dev/null | wc -l || echo "0")
UNTRACKED_COUNT=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l || echo "0")

# Ahead/behind
AHEAD=0
BEHIND=0
UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo "")
if [[ -n "$UPSTREAM" ]]; then
  AHEAD=$(git rev-list --count HEAD ^"$UPSTREAM" 2>/dev/null || echo "0")
  BEHIND=$(git rev-list --count "$UPSTREAM" ^HEAD 2>/dev/null || echo "0")
fi

# Output JSON
cat <<EOF
{
  "project_root": "$PROJECT_ROOT",
  "remote_url": "$REMOTE_URL",
  "git_owner": "$GIT_OWNER",
  "git_repo": "$GIT_REPO",
  "current_branch": "$CURRENT_BRANCH",
  "base_branch": "$BASE_BRANCH",
  "task_id": "$TASK_ID",
  "changed_files_count": $CHANGED_FILES_COUNT,
  "unstaged_count": $UNSTAGED_COUNT,
  "staged_count": $STAGED_COUNT,
  "untracked_count": $UNTRACKED_COUNT,
  "ahead": $AHEAD,
  "behind": $BEHIND
}
EOF
