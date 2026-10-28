#!/bin/bash
# Gathers all uncommitted changes (staged, unstaged, untracked) as JSON.
# Usage: bash bin/skill-scripts/commit/gather-changes.sh
#
# Output: JSON object with staged, unstaged, and untracked arrays.

set -euo pipefail

echo "{"

# Staged files
echo '  "staged": ['
FIRST=true
while IFS=$'\t' read -r status file; do
  if [ "$FIRST" = true ]; then FIRST=false; else printf ",\n"; fi
  printf '    {"status": "%s", "file": "%s"}' "$status" "$file"
done < <(git diff --cached --name-status 2>/dev/null)
echo ""
echo '  ],'

# Unstaged tracked files
echo '  "unstaged": ['
FIRST=true
while IFS=$'\t' read -r status file; do
  if [ "$FIRST" = true ]; then FIRST=false; else printf ",\n"; fi
  printf '    {"status": "%s", "file": "%s"}' "$status" "$file"
done < <(git diff --name-status 2>/dev/null)
echo ""
echo '  ],'

# Untracked files
echo '  "untracked": ['
FIRST=true
while read -r file; do
  if [ "$FIRST" = true ]; then FIRST=false; else printf ",\n"; fi
  printf '    "%s"' "$file"
done < <(git ls-files --others --exclude-standard 2>/dev/null)
echo ""
echo '  ]'

echo "}"
