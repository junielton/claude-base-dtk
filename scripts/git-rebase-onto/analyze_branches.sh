#!/usr/bin/env bash
#
# analyze_branches.sh — Find the cut point for a `git rebase --onto`.
#
# Given the branch you forked from (BASE) and your topic branch (TOPIC, default
# HEAD), this prints everything needed to decide where to cut:
#   - the graph fork point (merge-base) = the recommended "oldbase"
#   - a numbered log of the topic branch since the fork
#   - a numbered log of the base branch
#   - a contamination report (commits already present in BASE by patch-id),
#     which is what makes the naive `rev-list --count` look "dirty"
#   - a ready-to-run, copy-pasteable rebase command skeleton
#
# It DOES NOT modify the repository. Read-only. Safe to run anytime.
#
# Usage:
#   analyze_branches.sh <base-branch> [<topic-branch>] [--newbase <ref>] [--limit N]
#
# Examples:
#   analyze_branches.sh origin/feature-a
#   analyze_branches.sh feature-a my-topic --newbase origin/main --limit 40
#
set -euo pipefail

err() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || err "git not found on PATH"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || err "not inside a git work tree"

BASE=""
TOPIC="HEAD"
NEWBASE=""
LIMIT=30

# --- parse args -------------------------------------------------------------
POSITIONAL=()
while [ $# -gt 0 ]; do
  case "$1" in
    --newbase) NEWBASE="${2:-}"; shift 2 ;;
    --limit)   LIMIT="${2:-30}"; shift 2 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --*) err "unknown option: $1" ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done
set -- "${POSITIONAL[@]:-}"
BASE="${1:-}"
[ -n "${2:-}" ] && TOPIC="$2"

[ -n "$BASE" ] || err "missing <base-branch>. Usage: analyze_branches.sh <base-branch> [<topic-branch>]"

# --- validate refs ----------------------------------------------------------
git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null || err "base ref not found: $BASE"
git rev-parse --verify --quiet "$TOPIC^{commit}" >/dev/null || err "topic ref not found: $TOPIC"
if [ -n "$NEWBASE" ]; then
  git rev-parse --verify --quiet "$NEWBASE^{commit}" >/dev/null || err "newbase ref not found: $NEWBASE"
fi

TOPIC_SHA=$(git rev-parse --short "$TOPIC")
BASE_SHA=$(git rev-parse --short "$BASE")

# --- fork point (merge-base) ------------------------------------------------
MB=$(git merge-base "$TOPIC" "$BASE") || err "no common ancestor between $TOPIC and $BASE"
MB_SHORT=$(git rev-parse --short "$MB")

AHEAD=$(git rev-list --count "$BASE..$TOPIC")        # what `rev-list --count` shows
UNIQUE=$(git rev-list --count "$MB..$TOPIC")          # commits since the real fork
BEHIND=$(git rev-list --count "$TOPIC..$BASE")        # commits base has that topic doesn't
MERGES=$(git rev-list --merges --count "$MB..$TOPIC") # merges in the replay range

echo "============================================================"
echo " BRANCH ANALYSIS"
echo "============================================================"
echo " topic            : $TOPIC ($TOPIC_SHA)"
echo " base (forked from): $BASE ($BASE_SHA)"
[ -n "$NEWBASE" ] && echo " newbase (target) : $NEWBASE ($(git rev-parse --short "$NEWBASE"))"
echo " merge-base (fork): $MB_SHORT"
echo
echo " rev-list --count $BASE..$TOPIC = $AHEAD   (commits ahead of base TIP)"
echo " rev-list --count $MB..$TOPIC   = $UNIQUE   (commits since the real fork point)"
echo " base is $BEHIND commit(s) ahead of the fork point"
if [ "$AHEAD" != "$UNIQUE" ]; then
  echo
  echo " NOTE: the two counts differ. That usually means the base branch moved"
  echo "       on after you forked, and/or some commits are duplicated. The"
  echo "       contamination report below tells you which case it is."
fi
if [ "$MERGES" -gt 0 ]; then
  echo
  echo " WARNING: $MERGES merge commit(s) in the replay range. A plain rebase"
  echo "          linearizes them silently — consider --rebase-merges."
fi

# --- topic log since fork (numbered) ---------------------------------------
echo
echo "------------------------------------------------------------"
echo " TOPIC commits since fork point  (newest first)"
echo " The fork point itself (oldbase) is the line marked  <== FORK POINT"
echo "------------------------------------------------------------"
LOGRANGE="$MB~1..$TOPIC"
git rev-parse --verify --quiet "$MB~1^{commit}" >/dev/null || LOGRANGE="$TOPIC"
git log --pretty=format:'%h %ar %an %s' "$LOGRANGE" 2>/dev/null \
  | awk -v mb="$MB_SHORT" '{ mark="";
      if (NR==1) mark="   <== topic TIP (newest)";
      if (index($1, mb) == 1 || index(mb, $1) == 1) mark="   <== FORK POINT (recommended oldbase)";
      print NR") "$0 mark }' \
  | head -n "$LIMIT" || true
echo
echo " (oldbase / fork point = $MB_SHORT — its parent line, everything ABOVE it is yours)"

# --- base log (numbered) ----------------------------------------------------
echo
echo "------------------------------------------------------------"
echo " BASE commits (newest first) — compare subjects/authors with the"
echo " topic list above to spot where history starts repeating"
echo "------------------------------------------------------------"
git log --pretty=format:'%h %ar %an %s' "$BASE" \
  | awk '{print NR") "$0}' | head -n "$LIMIT" || true

# --- contamination report (patch-id equivalence) ----------------------------
echo
echo "------------------------------------------------------------"
echo " CONTAMINATION REPORT  (git cherry: '-' = already in base)"
echo "   +  hash  -> unique to topic, will be REPLAYED by the rebase"
echo "   -  hash  -> patch already exists in base (duplicate / cherry-picked)"
echo "------------------------------------------------------------"
CHERRY=$(git cherry -v "$BASE" "$TOPIC" 2>/dev/null || true)
if [ -z "$CHERRY" ]; then
  echo " (no commits — topic has nothing beyond base)"
else
  echo "$CHERRY"
fi
DUP_COUNT=$(printf '%s\n' "$CHERRY" | grep -c '^-' || true)
KEEP_COUNT=$(printf '%s\n' "$CHERRY" | grep -c '^+' || true)
echo
echo " summary: $KEEP_COUNT commit(s) to replay, $DUP_COUNT already-in-base (contaminated)"

# --- squash-merge check (git cherry is BLIND to squash merges) ---------------
# A squash merge gives the patches a new identity, so already-merged work shows
# as '+' above and the report can read "clean" falsely. Heuristic: non-merge
# commits on newbase since its fork with topic, with a PR-merge subject (#N)
# AND touching files the topic also touches, are squash suspects.
SQUASH_SUSPECTS=""
if [ -n "$NEWBASE" ]; then
  MB_NEW=$(git merge-base "$TOPIC" "$NEWBASE" 2>/dev/null || true)
  if [ -n "$MB_NEW" ]; then
    TOPIC_FILES=$(git diff --name-only "$MB" "$TOPIC" | sort -u)
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      h=${line%% *}
      overlap=$(comm -12 \
        <(printf '%s\n' "$TOPIC_FILES") \
        <(git diff-tree --no-commit-id --name-only -r "$h" | sort -u) | head -n 1)
      [ -n "$overlap" ] && SQUASH_SUSPECTS+="$line"$'\n'
    done < <(git log --no-merges --max-count=200 --pretty=format:'%h %s' "$MB_NEW..$NEWBASE" \
               | grep -E '\(#[0-9]+\)$' || true)
  fi
  echo
  echo "------------------------------------------------------------"
  echo " SQUASH-MERGE CHECK"
  echo "------------------------------------------------------------"
  if [ -n "$SQUASH_SUSPECTS" ]; then
    echo " SUSPECT squash-merged PR(s) on $NEWBASE touching the topic's files:"
    printf '%s' "$SQUASH_SUSPECTS" | sed 's/^/   /'
    echo
    echo " If one of these is an ANCESTOR PR of this stack, do NOT cut at the"
    echo " merge-base. Cut at the squashed ancestor branch's OLD TIP instead:"
    echo "   1. find it:   gh pr view <merged-pr> --json headRefName"
    echo "   2. confirm:   git merge-base --is-ancestor <tip> $TOPIC"
    echo "   3. validate:  git diff --stat <tip> $NEWBASE   (only files foreign"
    echo "                 to the topic's work may appear)"
  else
    echo " No squash suspects found on $NEWBASE overlapping the topic's files."
    echo " This heuristic can miss — if the branch is part of a PR stack, verify"
    echo " with the PR graph: gh pr view <n> --json baseRefName,headRefName,state"
  fi
fi

# --- recommendation ---------------------------------------------------------
echo
echo "============================================================"
echo " RECOMMENDATION"
echo "============================================================"
if [ -n "$SQUASH_SUSPECTS" ]; then
  echo " Squash-merge suspects found (see SQUASH-MERGE CHECK above)."
  echo " The merge-base ($MB_SHORT) may be the WRONG cut point even though the"
  echo " contamination report reads clean: if an ancestor PR was squash-merged,"
  echo " prefer that branch's old tip as oldbase, validated via the PR graph."
  CONFIDENCE="REVIEW"
elif [ "$DUP_COUNT" -eq 0 ]; then
  echo " Clean history. The fork point is unambiguous."
  echo " oldbase (cut point) = $MB_SHORT"
  CONFIDENCE="HIGH"
else
  echo " Contamination detected ($DUP_COUNT duplicate commit(s))."
  echo " The graph fork point ($MB_SHORT) is still a SAFE oldbase: rebase --onto"
  echo " replays only $MB..$TOPIC, so duplicates that sit BELOW the fork are"
  echo " excluded automatically. But if the duplicates are INTERLEAVED with your"
  echo " real commits, prefer an interactive rebase to drop them — verify with a"
  echo " human before executing."
  CONFIDENCE="REVIEW"
fi
echo
echo " confidence: $CONFIDENCE"
echo
echo " Suggested command (preview first — the safe_rebase_onto.sh script"
echo " defaults to a dry run):"
if [ -n "$NEWBASE" ]; then
  echo "   safe_rebase_onto.sh --newbase $NEWBASE --oldbase $MB_SHORT --topic $TOPIC"
else
  echo "   safe_rebase_onto.sh --newbase <TARGET_BRANCH> --oldbase $MB_SHORT --topic $TOPIC"
fi
echo
echo " Raw git equivalent:"
echo "   git rebase --onto ${NEWBASE:-<TARGET_BRANCH>} $MB_SHORT $TOPIC"
echo "============================================================"
