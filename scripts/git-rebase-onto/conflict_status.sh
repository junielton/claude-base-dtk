#!/usr/bin/env bash
#
# conflict_status.sh — Summarize the current rebase conflict state.
#
# Run this whenever a rebase is paused. It prints, for the commit being applied:
#   - which commit (of the original series) is currently being replayed
#   - the list of conflicted files
#   - per file, how many conflict hunks and which sides touched it
# Read-only. It changes nothing.
#
set -euo pipefail

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git work tree" >&2; exit 1; }

RB_MERGE=$(git rev-parse --git-path rebase-merge)
RB_APPLY=$(git rev-parse --git-path rebase-apply)
if [ ! -d "$RB_MERGE" ] && [ ! -d "$RB_APPLY" ]; then
  echo "No rebase in progress. Nothing to resolve."
  exit 0
fi

echo "============================================================"
echo " REBASE CONFLICT STATUS"
echo "============================================================"

# Which commit is being applied right now?
if [ -f "$RB_MERGE/message" ]; then
  echo " Currently applying:"
  sed 's/^/   /' "$RB_MERGE/message" | head -n 3
fi
if [ -f "$RB_MERGE/done" ] && [ -f "$RB_MERGE/git-rebase-todo" ]; then
  DONE=$(grep -c . "$RB_MERGE/done" 2>/dev/null || true); DONE=${DONE:-0}
  LEFT=$(grep -cE '^(pick|p|reword|r|edit|e|squash|s|fixup|f) ' "$RB_MERGE/git-rebase-todo" 2>/dev/null || true); LEFT=${LEFT:-0}
  echo " Progress: $DONE applied, $LEFT remaining"
fi

echo
echo " Conflicted files:"
FILES=$(git diff --name-only --diff-filter=U || true)
if [ -z "$FILES" ]; then
  echo "   (none — you may be ready to run: git rebase --continue)"
  exit 0
fi

while IFS= read -r f; do
  [ -z "$f" ] && continue
  HUNKS=$(grep -c '^<<<<<<<' "$f" 2>/dev/null || true)
  echo "   - $f   ($HUNKS conflict hunk(s))"
done <<< "$FILES"

echo
echo " To inspect a file's three versions:"
echo "   git show :1:<file>   # common ancestor (base)"
echo "   git show :2:<file>   # ours  (the new base / target)"
echo "   git show :3:<file>   # theirs (the commit being replayed)"
echo
echo " After resolving:  git add <file> && git rebase --continue"
echo "============================================================"
