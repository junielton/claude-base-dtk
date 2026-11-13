#!/usr/bin/env bash
#
# List the pull requests merged in a date range, for the pr-story digest.
#
#   list-merged.sh <owner/repo> <since>
#
# <since> is YYYY-MM-DD or <N>d (N days before DTK_NOW when set, else before today, UTC).
# stdout: a JSON array, oldest merge first, of
#   {number,title,author,mergedAt,additions,deletions,changedFiles,labels,files,refs}
# where labels and files are plain string lists and refs are the PR numbers written as #<n>
# in the PR body (never the PR's own number). Prints [] and exits 0 when nothing merged.
#
# Exit 2 on bad usage, 1 when gh fails. Needs bash, jq and gh (signed in as the running user).

set -uo pipefail

usage() { echo "usage: list-merged.sh <owner/repo> <since: YYYY-MM-DD | Nd>" >&2; exit 2; }
die() { echo "list-merged: $*" >&2; exit "${2:-2}"; }

[ $# -eq 2 ] || usage
REPO="$1"; SINCE="$2"
[[ "$REPO" =~ ^[A-Za-z0-9_-][A-Za-z0-9._-]*/[A-Za-z0-9_-][A-Za-z0-9._-]*$ ]] || die "repo must read owner/repo (got '$REPO')"
command -v jq >/dev/null || die "jq is required" 1
command -v gh >/dev/null || die "gh is required" 1

# Days since 1970-01-01 for a civil date, and back. Pure arithmetic, so it behaves the same
# with GNU date and BSD date (macOS).
days_from_civil() { # y m d
  local y=$1 m=$((10#$2)) d=$((10#$3))
  [ "$m" -le 2 ] && y=$((y - 1))
  local era=$(( (y >= 0 ? y : y - 399) / 400 ))
  local yoe=$((y - era * 400))
  local mp=$(( (m + 9) % 12 ))
  local doy=$(( (153 * mp + 2) / 5 + d - 1 ))
  local doe=$(( yoe * 365 + yoe / 4 - yoe / 100 + doy ))
  echo $(( era * 146097 + doe - 719468 ))
}
civil_from_days() { # days
  local z=$(( $1 + 719468 ))
  local era=$(( (z >= 0 ? z : z - 146096) / 146097 ))
  local doe=$(( z - era * 146097 ))
  local yoe=$(( (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365 ))
  local y=$(( yoe + era * 400 ))
  local doy=$(( doe - (365 * yoe + yoe / 4 - yoe / 100) ))
  local mp=$(( (5 * doy + 2) / 153 ))
  local d=$(( doy - (153 * mp + 2) / 5 + 1 ))
  local m=$(( mp < 10 ? mp + 3 : mp - 9 ))
  [ "$m" -le 2 ] && y=$((y + 1))
  printf '%04d-%02d-%02d\n' "$y" "$m" "$d"
}

if [[ "$SINCE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  FROM="$SINCE"
elif [[ "$SINCE" =~ ^([0-9]+)d$ ]]; then
  NOW="${DTK_NOW:-$(date -u +%Y-%m-%d)}"
  [[ "$NOW" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})$ ]] || die "DTK_NOW must be YYYY-MM-DD (got '$NOW')"
  FROM="$(civil_from_days $(( $(days_from_civil "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}") - ${SINCE%d} )))"
else
  die "since must be YYYY-MM-DD or <N>d (got '$SINCE')"
fi

LIMIT=500
RAW="$(gh pr list -R "$REPO" --state merged --search "merged:>=$FROM" --limit "$LIMIT" \
  --json number,title,body,author,mergedAt,additions,deletions,changedFiles,labels,files)" \
  || die "gh pr list failed for $REPO" 1

jq -e 'type == "array"' >/dev/null 2>&1 <<<"$RAW" || die "gh returned something that is not a JSON list" 1
[ "$(jq 'length' <<<"$RAW")" -lt "$LIMIT" ] || echo "list-merged: $LIMIT PRs returned, the range may hold more; narrow --since" >&2

jq -c '
  sort_by(.mergedAt)
  | map(. as $pr | {
      number, title,
      author: (.author.login // null),
      mergedAt, additions, deletions, changedFiles,
      labels: [(.labels // [])[] | .name],
      files: [(.files // [])[] | .path],
      refs: ([ (.body // "") | scan("(?:^|[^A-Za-z0-9_/&])#([0-9]+)") | .[0] | tonumber ]
             | unique | map(select(. != $pr.number)))
    })
' <<<"$RAW"
