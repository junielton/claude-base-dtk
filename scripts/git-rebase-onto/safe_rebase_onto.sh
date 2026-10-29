#!/usr/bin/env bash
#
# safe_rebase_onto.sh — Run `git rebase --onto` with guardrails.
#
# By default this is a DRY RUN: it validates the refs, checks the working tree,
# and prints exactly which commits would be replayed and the exact command it
# would run — but changes nothing. Add --execute to actually perform the rebase,
# which first creates a timestamped backup branch so you can always get back.
#
# Usage:
#   safe_rebase_onto.sh --newbase <ref> --oldbase <ref> [--topic <ref>] [flags]
#
# Required:
#   --newbase <ref>   Where the commits should land (the new base).
#   --oldbase <ref>   The cut point: replay commits AFTER this one.
#                     (The merge-base, i.e. "<first-commit-that-is-yours>^".)
# Optional:
#   --topic <ref>     Branch to move. Default: current branch (HEAD).
#   --execute         Actually run the rebase. Without this it's a preview.
#   --rebase-merges   Preserve merge commits in the range (plain rebase
#                     linearizes them silently).
#   --update-refs     Carry along stacked branch refs that point at commits
#                     being rewritten (git >= 2.38).
#   --allow-dirty     Skip the clean-working-tree check (not recommended).
#   --no-backup       Skip creating the backup branch (not recommended).
#
# Examples:
#   safe_rebase_onto.sh --newbase origin/main --oldbase abc1234          # preview
#   safe_rebase_onto.sh --newbase origin/main --oldbase abc1234 --execute
#
set -euo pipefail

err()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
note() { printf '  %s\n' "$*"; }

command -v git >/dev/null 2>&1 || err "git not found on PATH"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || err "not inside a git work tree"

NEWBASE=""; OLDBASE=""; TOPIC=""; EXECUTE=0; ALLOW_DIRTY=0; DO_BACKUP=1
EXTRA_FLAGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --newbase) NEWBASE="${2:-}"; shift 2 ;;
    --oldbase) OLDBASE="${2:-}"; shift 2 ;;
    --topic)   TOPIC="${2:-}"; shift 2 ;;
    --execute) EXECUTE=1; shift ;;
    --rebase-merges) EXTRA_FLAGS+=("--rebase-merges"); shift ;;
    --update-refs)   EXTRA_FLAGS+=("--update-refs"); shift ;;
    --allow-dirty) ALLOW_DIRTY=1; shift ;;
    --no-backup) DO_BACKUP=0; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) err "unknown argument: $1" ;;
  esac
done

[ -n "$NEWBASE" ] || err "missing --newbase"
[ -n "$OLDBASE" ] || err "missing --oldbase"

# default topic = current branch
if [ -z "$TOPIC" ]; then
  TOPIC=$(git symbolic-ref --quiet --short HEAD) || err "detached HEAD: pass --topic explicitly"
fi

# --- validate refs ----------------------------------------------------------
for ref in "$NEWBASE" "$OLDBASE" "$TOPIC"; do
  git rev-parse --verify --quiet "$ref^{commit}" >/dev/null || err "ref not found: $ref"
done

# oldbase should be an ancestor of topic, otherwise the range is empty/odd
if ! git merge-base --is-ancestor "$OLDBASE" "$TOPIC"; then
  err "--oldbase ($OLDBASE) is not an ancestor of --topic ($TOPIC). Double-check the cut point with analyze_branches.sh."
fi

REPLAY_COUNT=$(git rev-list --count "$OLDBASE..$TOPIC")
[ "$REPLAY_COUNT" -gt 0 ] || err "nothing to replay: $OLDBASE..$TOPIC is empty. Wrong oldbase?"

echo "============================================================"
echo " REBASE --ONTO  PREVIEW"
echo "============================================================"
echo " topic    : $TOPIC ($(git rev-parse --short "$TOPIC"))"
echo " newbase  : $NEWBASE ($(git rev-parse --short "$NEWBASE"))"
echo " oldbase  : $OLDBASE ($(git rev-parse --short "$OLDBASE"))   <-- cut point"
echo
echo " Commits that will be REPLAYED onto $NEWBASE ($REPLAY_COUNT):"
git log --pretty=format:'   %h %an  %s' "$OLDBASE..$TOPIC" | awk '{print NR") "$0}'
echo
echo " Exact command:"
echo "   git rebase ${EXTRA_FLAGS[*]:-}--onto $NEWBASE $OLDBASE $TOPIC" | tr -s ' '
echo "============================================================"

# --- hazard checks (informational) -------------------------------------------
MERGES=$(git rev-list --merges --count "$OLDBASE..$TOPIC")
if [ "$MERGES" -gt 0 ] && [[ " ${EXTRA_FLAGS[*]:-} " != *" --rebase-merges "* ]]; then
  echo
  echo " WARNING: $MERGES merge commit(s) in the replay range. A plain rebase"
  echo "          linearizes them silently — consider re-running with --rebase-merges."
fi

# Branches forked from commits INSIDE the replay range get stranded on the old
# history when topic moves. Detect them so nobody is surprised afterwards.
CHILDREN=""
OLDBASE_SHA=$(git rev-parse "$OLDBASE")
while IFS= read -r b; do
  [ "$b" = "$TOPIC" ] && continue
  case "$b" in backup/*) continue ;; esac
  bmb=$(git merge-base "$b" "$TOPIC" 2>/dev/null) || continue
  if [ "$bmb" != "$OLDBASE_SHA" ] && git merge-base --is-ancestor "$OLDBASE" "$bmb" 2>/dev/null; then
    CHILDREN+="$b"$'\n'
  fi
done < <(git branch --format='%(refname:short)')
if [ -n "$CHILDREN" ]; then
  echo
  echo " WARNING: these local branches fork from commits being rewritten and"
  echo " will be left on the OLD history after the rebase:"
  printf '%s' "$CHILDREN" | sed 's/^/   - /'
  echo " If a child's tip is itself inside the range, --update-refs (git >= 2.38)"
  echo " carries it along; otherwise move each child afterwards with its own"
  echo " rebase --onto (new parent commit, old parent commit, child)."
fi

# --- safety checks ----------------------------------------------------------
echo
echo " SAFETY CHECKS"
if [ -d "$(git rev-parse --git-path rebase-merge)" ] || [ -d "$(git rev-parse --git-path rebase-apply)" ]; then
  err "a rebase is already in progress. Finish it (git rebase --continue) or abort it (git rebase --abort) first."
fi

if [ "$ALLOW_DIRTY" -eq 0 ]; then
  if [ -n "$(git status --porcelain)" ]; then
    echo
    git status --short
    err "working tree is not clean. Commit or stash your changes first, or pass --allow-dirty if you know what you're doing."
  fi
  note "[ok] working tree is clean"
else
  note "[skip] working-tree check disabled (--allow-dirty)"
fi

# --- topic must not be behind its own remote --------------------------------
# A stale worktree is invisible to --force-with-lease: the lease only proves the
# remote has not moved since your last fetch, so rebasing a branch that is behind
# origin and force-pushing SILENTLY DISCARDS the commits you did not replay.
TOPIC_REMOTE=$(git rev-parse --abbrev-ref --symbolic-full-name "${TOPIC}@{upstream}" 2>/dev/null || true)
if [ -n "$TOPIC_REMOTE" ]; then
  BEHIND=$(git rev-list --count "${TOPIC}..${TOPIC_REMOTE}" 2>/dev/null || echo 0)
  if [ "$BEHIND" -gt 0 ]; then
    echo
    git log --oneline "${TOPIC}..${TOPIC_REMOTE}"
    echo
    err "topic '${TOPIC}' is ${BEHIND} commit(s) BEHIND ${TOPIC_REMOTE} (listed above).
       Rebasing this branch and force-pushing would DISCARD them — --force-with-lease will NOT stop it.
       Fast-forward first:  git checkout ${TOPIC} && git merge --ff-only ${TOPIC_REMOTE}
       then re-run this script."
  fi
  note "[ok] topic is in sync with ${TOPIC_REMOTE}"
else
  note "[skip] topic has no upstream — nothing to compare against"
fi

# --- stop here unless executing --------------------------------------------
if [ "$EXECUTE" -eq 0 ]; then
  echo
  echo " DRY RUN — nothing was changed."
  echo " Re-run with --execute to perform the rebase above."
  exit 0
fi

# --- backup -----------------------------------------------------------------
TS=$(date +%Y%m%d-%H%M%S)
if [ "$DO_BACKUP" -eq 1 ]; then
  BACKUP="backup/${TOPIC}-${TS}"
  git branch "$BACKUP" "$TOPIC"
  echo
  note "[ok] backup branch created: $BACKUP"
  note "     to undo this rebase later:  git checkout $TOPIC && git reset --hard $BACKUP"
else
  note "[skip] backup disabled (--no-backup). Recovery via:  git reflog"
fi

# --- execute ----------------------------------------------------------------
echo
echo " Running: git rebase ${EXTRA_FLAGS[*]:-} --onto $NEWBASE $OLDBASE $TOPIC" | tr -s ' '
echo "------------------------------------------------------------"
set +e
git rebase ${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"} --onto "$NEWBASE" "$OLDBASE" "$TOPIC"
RC=$?
set -e

echo "------------------------------------------------------------"
if [ "$RC" -eq 0 ]; then
  echo " SUCCESS — rebase complete."
  if [ "$DO_BACKUP" -eq 1 ]; then
    echo " Backup kept at: $BACKUP (delete with: git branch -D $BACKUP)"
  fi
  echo
  echo " Verify:"
  echo "   git log --oneline $NEWBASE..$TOPIC        # only your commits, nothing foreign"
  if [ "$DO_BACKUP" -eq 1 ]; then
    echo "   git range-diff $OLDBASE..$BACKUP $NEWBASE..$TOPIC   # same changes, reparented"
  fi
  if [ -n "$CHILDREN" ]; then
    echo
    echo " Stranded children (flagged in the preview) — still on the OLD history,"
    echo " move each one with its own rebase --onto:"
    printf '%s' "$CHILDREN" | sed 's/^/   - /'
  fi
  if git rev-parse --abbrev-ref --symbolic-full-name "$TOPIC@{upstream}" >/dev/null 2>&1; then
    echo
    echo " Publish (branch has an upstream):"
    echo "   git push --force-with-lease               # never plain --force"
  fi
else
  echo " REBASE PAUSED — likely a conflict. The repo is mid-rebase."
  echo
  echo " Files with conflicts:"
  git diff --name-only --diff-filter=U | sed 's/^/   /' || true
  echo
  echo " Next steps:"
  echo "   - resolve the files above, then:  git add <file> && git rebase --continue"
  echo "   - skip the current commit:        git rebase --skip"
  echo "   - abort everything:               git rebase --abort"
  if [ "$DO_BACKUP" -eq 1 ]; then
    echo "   - hard reset to before rebase:    git checkout $TOPIC && git reset --hard $BACKUP"
  fi
fi
exit "$RC"
