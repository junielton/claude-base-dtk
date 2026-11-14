#!/usr/bin/env bash
#
# Paths and freshness of the per-user story cache.
#
#   story-cache.sh path <owner> <repo> <number> [lang]
#   story-cache.sh status <file> <head_sha>
#   story-cache.sh digest-path <owner> <repo> <from> <to> [lang]
#
# Cache root: ${XDG_DATA_HOME:-$HOME/.local/share}/dtk/stories/<owner>/<repo>/
#   path         prints <root>/<owner>/<repo>/PR-<n>.md, or PR-<n>.<lang>.md when lang is given
#                and is not "en".
#   status       prints missing (no file), fresh (the file's frontmatter head_sha equals
#                <head_sha>) or stale (anything else, including no head_sha). Exit 0.
#   digest-path  prints <root>/<owner>/<repo>/digest-<from>-<to>[.<lang>].md.
#
# Exit 2 on bad usage or a value that could escape the cache folder. Needs only bash and awk.

set -uo pipefail

die() { echo "story-cache: $*" >&2; exit 2; }
usage() { echo "usage: story-cache.sh path <owner> <repo> <number> [lang] | status <file> <head_sha> | digest-path <owner> <repo> <from> <to> [lang]" >&2; exit 2; }

root() { printf '%s/dtk/stories' "${XDG_DATA_HOME:-$HOME/.local/share}"; }

safe() { # label value: letters, digits, dot, dash, underscore; never a leading dot
  [[ "$2" =~ ^[A-Za-z0-9_-][A-Za-z0-9._-]*$ ]] || die "invalid $1: '$2'"
}

lang_suffix() { # lang -> ".<lang>" or nothing
  local l="${1:-}"
  [ -z "$l" ] || [ "$l" = en ] && return 0
  [[ "$l" =~ ^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$ ]] || die "invalid language: '$l'"
  printf '.%s' "$l"
}

cmd="${1:-}"; [ $# -ge 1 ] && shift
case "$cmd" in
  path)
    [ $# -ge 3 ] || usage
    safe owner "$1"; safe repo "$2"
    [[ "$3" =~ ^[0-9]+$ ]] || die "invalid PR number: '$3'"
    suffix="$(lang_suffix "${4:-}")" || exit 2
    printf '%s/%s/%s/PR-%s%s.md\n' "$(root)" "$1" "$2" "$3" "$suffix"
    ;;
  digest-path)
    [ $# -ge 4 ] || usage
    safe owner "$1"; safe repo "$2"
    [[ "$3" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "invalid from date: '$3'"
    [[ "$4" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "invalid to date: '$4'"
    suffix="$(lang_suffix "${5:-}")" || exit 2
    printf '%s/%s/%s/digest-%s-%s%s.md\n' "$(root)" "$1" "$2" "$3" "$4" "$suffix"
    ;;
  status)
    [ $# -eq 2 ] || usage
    file="$1"; want="$2"
    [ -f "$file" ] || { echo missing; exit 0; }
    have="$(awk '
      NR==1 { if ($0 != "---") exit; next }
      /^---[[:space:]]*$/ { exit }
      /^head_sha:/ { sub(/^head_sha:[[:space:]]*/, ""); gsub(/["\047[:space:]]/, ""); print; exit }
    ' "$file")"
    if [ -n "$have" ] && [ "$have" = "$want" ]; then echo fresh; else echo stale; fi
    ;;
  *) usage ;;
esac
