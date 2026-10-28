#!/bin/bash
#
# Validates and posts a review payload built by /dtk:review-publish.
# Runs tone-lint.sh first (dry run and real post alike) and refuses a payload that hedges,
# lacks a tag, runs long, or posts a CR as anything but REQUEST_CHANGES.
# Checks the head SHA (full, current), and that every inline line is an added line
# in the PR diff, because GitHub rejects the whole review with a 422 otherwise.
#
# Usage:
#   bash bin/skill-scripts/review/post-review.sh --payload <file.json> [--dry-run]

set -euo pipefail

PAYLOAD=""
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
  case $1 in
    --payload) PAYLOAD="$2"; shift 2 ;;
    --dry-run) DRY_RUN="true"; shift ;;
    *) shift ;;
  esac
done

[[ -f "$PAYLOAD" ]] || { echo "payload not found: $PAYLOAD" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
command -v gh >/dev/null || { echo "gh is required" >&2; exit 1; }

PR=$(jq -r '.pr' "$PAYLOAD")
REPO=$(jq -r '.repo' "$PAYLOAD")
EVENT=$(jq -r '.event' "$PAYLOAD")
COMMIT=$(jq -r '.commit_id // ""' "$PAYLOAD")
BODY=$(jq -r '.body // ""' "$PAYLOAD")
COUNT=$(jq '.comments | length' "$PAYLOAD")

case "$EVENT" in
  APPROVE|COMMENT|REQUEST_CHANGES) ;;
  *) echo "event must be APPROVE, COMMENT or REQUEST_CHANGES, got: $EVENT" >&2; exit 1 ;;
esac

LINT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tone-lint.sh"
[[ -f "$LINT" ]] || { echo "tone-lint.sh not found next to post-review.sh: $LINT" >&2; exit 1; }
if ! bash "$LINT" --payload "$PAYLOAD"; then
  echo "refused by tone-lint (rule named above): fix the payload and run again. Nothing was posted." >&2
  exit 1
fi

HEAD=$(gh pr view "$PR" --repo "$REPO" --json headRefOid --jq .headRefOid)

if [[ -z "$COMMIT" ]]; then
  COMMIT="$HEAD"
fi

if [[ ${#COMMIT} -ne 40 ]]; then
  echo "commit_id must be the full 40-char SHA, got ${#COMMIT} chars: $COMMIT" >&2
  exit 1
fi

if [[ "$COMMIT" != "$HEAD" ]]; then
  echo "head drift: payload commit_id $COMMIT, PR head is now $HEAD. Re-anchor or re-review." >&2
  exit 1
fi

if [[ "$EVENT" == "APPROVE" && -z "$BODY" && "$COUNT" -eq 0 ]]; then
  echo "an APPROVE with no body and no comments posts nothing visible; give it a body" >&2
  exit 1
fi

pr_diff() {
  local base
  base=$(gh pr view "$PR" --repo "$REPO" --json baseRefName --jq .baseRefName)
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1 && git remote get-url origin 2>/dev/null | grep -q "$REPO"; then
    git cat-file -e "$COMMIT^{commit}" 2>/dev/null || git fetch -q origin "$COMMIT"
    git fetch -q origin "$base"
    git --no-pager diff --no-ext-diff --no-color "$(git merge-base "origin/$base" "$COMMIT")" "$COMMIT"
    return
  fi
  gh pr diff "$PR" --repo "$REPO"
}

ADDED=$(pr_diff | awk '
  /^\+\+\+ / { file = substr($0, 7); next }
  /^@@ / { match($0, /\+[0-9]+/); line = substr($0, RSTART + 1, RLENGTH - 1) + 0; next }
  /^\+/ { print file ":" line; line++; next }
  /^ / { line++; next }
  /^-/ { next }
')

BAD=0
while IFS=$'\t' read -r path line; do
  if ! grep -qxF "${path}:${line}" <<<"$ADDED"; then
    echo "not an added line in the PR diff: ${path}:${line}" >&2
    BAD=1
  fi
done < <(jq -r '.comments[] | [.path, (.line|tostring)] | @tsv' "$PAYLOAD")

[[ "$BAD" -eq 0 ]] || exit 1

REQUEST=$(jq '{
  commit_id: .commit_id,
  event: .event,
  body: (.body // ""),
  comments: [.comments[] | {path: .path, line: .line, side: "RIGHT", body: .body}]
} | .commit_id = (.commit_id // "'"$COMMIT"'")' "$PAYLOAD")

if [[ "$DRY_RUN" == "true" ]]; then
  echo "dry run ok: $EVENT on $REPO#$PR at ${COMMIT:0:7}, $COUNT inline comment(s)"
  echo "$REQUEST"
  exit 0
fi

echo "$REQUEST" | gh api -X POST "repos/${REPO}/pulls/${PR}/reviews" --input - --jq '"posted: " + .state + " " + .html_url'
