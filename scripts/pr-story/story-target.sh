#!/usr/bin/env bash
#
# Resolve a pull request reference to {"owner","repo","number"}.
#
#   story-target.sh <arg>
#
# <arg> is one of: 15, #15, <owner>/<repo>#15, or a PR URL
# https://github.com/<owner>/<repo>/pull/15 with any suffix (/files, /commits/<sha>, #..., ?...).
# A bare number takes the repo of the current directory through `gh repo view`.
#
# stdout: {"owner":"<o>","repo":"<r>","number":<n>}, exit 0.
# Exit 2 with a message naming owner/repo#n when the input is not a PR reference or the repo
# cannot be determined. Needs bash, jq and (for a bare number) gh.

set -uo pipefail

die() { echo "story-target: $*" >&2; exit 2; }

emit() { # owner repo number
  jq -cn --arg o "$1" --arg r "$2" --argjson n "$3" '{owner:$o, repo:$r, number:$n}'
}

[ $# -ge 1 ] || die "missing PR reference; pass a number, owner/repo#n or a PR URL"
arg="${1#"${1%%[![:space:]]*}"}"; arg="${arg%"${arg##*[![:space:]]}"}"

name='[A-Za-z0-9._-]+'
if [[ "$arg" =~ ^https?://github\.com/($name)/($name)/pull/([0-9]+)([/?#].*)?$ ]]; then
  emit "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
elif [[ "$arg" =~ ^($name)/($name)#([0-9]+)$ ]]; then
  emit "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
elif [[ "$arg" =~ ^#?([0-9]+)$ ]]; then
  num="${BASH_REMATCH[1]}"
  repo_json="$(gh repo view --json owner,name 2>/dev/null)" \
    || die "cannot tell which repository PR $num belongs to (not inside a GitHub checkout); pass owner/repo#n"
  owner="$(jq -r '.owner.login // empty' <<<"$repo_json")"
  repo="$(jq -r '.name // empty' <<<"$repo_json")"
  [ -n "$owner" ] && [ -n "$repo" ] \
    || die "cannot tell which repository PR $num belongs to; pass owner/repo#n"
  emit "$owner" "$repo" "$num"
else
  die "'$arg' is not a pull request reference; pass a number, owner/repo#n or a github.com PR URL"
fi
