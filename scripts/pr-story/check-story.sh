#!/usr/bin/env bash
#
# Mechanical format gate for a pr-story story or digest. It checks shape, not truth: the
# claims are checked by claim-verifier and the links by link-finder.
#
#   check-story.sh <file>             a story of one PR
#   check-story.sh --digest <file>    a digest of the PRs merged in a range
#
# Exit 0 when clean. Exit 1 printing one "<rule>: <detail>" line per violation on stdout.
# Exit 2 on bad usage or an unreadable file.
#
# Rules:
#   frontmatter    pr: <owner>/<repo>#<n>, head_sha: (40 hex), lang:, generated_at: (ISO 8601)
#   title          exactly one "### " line, not ending in ?, ! or an ellipsis
#   meta           the first non-empty line after the title starts with * and contains [PR #
#   why            a line starting **Why:**
#   sections       **What changes for you** then **Left open**, each followed by content
#   unpinned-link  every github.com .../blob/<ref>/... or .../tree/<ref>/... has a 40-hex <ref>
#   bare-url       no http(s):// outside a Markdown link target
#
# Rules of --digest (unpinned-link and bare-url apply too):
#   frontmatter    repo: <owner>/<repo>, from: and to: (YYYY-MM-DD), lang:, generated_at: (ISO 8601),
#                  prs: [<n>, <n>, ...] (a non-empty inline list of PR numbers)
#   headlines      a **Headlines** line followed by 1 to 3 "- " bullets
#   arc            at least one "### " section other than "Also merged"
#   missing-pr     every number in prs appears in the body as a link to .../pull/<n>
#
# Needs bash, grep, sed and awk.

set -uo pipefail

MODE=story
if [ "${1:-}" = "--digest" ]; then MODE=digest; shift; fi
[ $# -eq 1 ] || { echo "usage: check-story.sh [--digest] <file>" >&2; exit 2; }
FILE="$1"
[ -f "$FILE" ] && [ -r "$FILE" ] || { echo "check-story: cannot read $FILE" >&2; exit 2; }

TMP="$(mktemp -d -t dtk-check-story.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

violations=0
violate() { # rule detail
  printf '%s: %s\n' "$1" "$2"
  violations=$((violations + 1))
}

# Split the file into frontmatter ($TMP/fm) and body ($TMP/body).
has_fm=0
if [ "$(head -n 1 "$FILE" | tr -d '\r')" = "---" ]; then
  close="$(awk 'NR > 1 && /^---[[:space:]]*$/ { print NR; exit }' "$FILE")"
  if [ -n "$close" ]; then
    has_fm=1
    sed -n "2,$((close - 1))p" "$FILE" | tr -d '\r' > "$TMP/fm"
    sed -n "$((close + 1)),\$p" "$FILE" | tr -d '\r' > "$TMP/body"
  fi
fi
if [ "$has_fm" = 0 ]; then
  : > "$TMP/fm"
  tr -d '\r' < "$FILE" > "$TMP/body"
  violate frontmatter "no YAML frontmatter (a file that starts with --- and closes with ---)"
fi

# --- frontmatter ---
valid_date() { # YYYY-MM-DD with a real month and day
  local y m d max
  [[ "$1" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})$ ]] || return 1
  y=$((10#${BASH_REMATCH[1]})); m=$((10#${BASH_REMATCH[2]})); d=$((10#${BASH_REMATCH[3]}))
  [ "$m" -ge 1 ] && [ "$m" -le 12 ] || return 1
  case "$m" in
    4|6|9|11) max=30 ;;
    2) if [ $((y % 4)) = 0 ] && { [ $((y % 100)) != 0 ] || [ $((y % 400)) = 0 ]; }; then max=29; else max=28; fi ;;
    *) max=31 ;;
  esac
  [ "$d" -ge 1 ] && [ "$d" -le "$max" ]
}
fm_value() { sed -n -E "s/^$1:[[:space:]]*(.*[^[:space:]])[[:space:]]*$/\\1/p" "$TMP/fm" | head -n 1 | sed -E "s/^[\"']//; s/[\"']$//"; }
if [ "$MODE" = story ] && [ "$has_fm" = 1 ]; then
  v="$(fm_value pr)"
  [[ "$v" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+#[0-9]+$ ]] || violate frontmatter "pr must read <owner>/<repo>#<n> (got '${v:-nothing}')"
  v="$(fm_value head_sha)"
  [[ "$v" =~ ^[0-9a-f]{40}$ ]] || violate frontmatter "head_sha must be 40 hex characters (got '${v:-nothing}')"
  v="$(fm_value lang)"
  [ -n "$v" ] || violate frontmatter "lang is missing"
  v="$(fm_value generated_at)"
  [[ "$v" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})$ ]] \
    || violate frontmatter "generated_at must be ISO 8601, like 2026-11-13T18:00:00Z (got '${v:-nothing}')"
fi

if [ "$MODE" = digest ] && [ "$has_fm" = 1 ]; then
  v="$(fm_value repo)"
  [[ "$v" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || violate frontmatter "repo must read <owner>/<repo> (got '${v:-nothing}')"
  for k in from to; do
    v="$(fm_value $k)"
    valid_date "$v" || violate frontmatter "$k must be a date like 2026-11-13 (got '${v:-nothing}')"
  done
  v="$(fm_value lang)"
  [ -n "$v" ] || violate frontmatter "lang is missing"
  v="$(fm_value generated_at)"
  [[ "$v" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})$ ]] \
    || violate frontmatter "generated_at must be ISO 8601, like 2026-11-13T18:00:00Z (got '${v:-nothing}')"
  v="$(fm_value prs)"
  PRS=""
  if [[ "$v" =~ ^\[[[:space:]]*([0-9]+([[:space:]]*,[[:space:]]*[0-9]+)*)[[:space:]]*\]$ ]]; then
    PRS="$(printf '%s' "${BASH_REMATCH[1]}" | tr -d ' ' | tr ',' '\n')"
  else
    violate frontmatter "prs must be a non-empty list of PR numbers, like [15, 22] (got '${v:-nothing}')"
  fi
fi

if [ "$MODE" = story ]; then
  # --- title ---
  titles="$(grep -c '^### ' "$TMP/body" || true)"
  title_line=""
  if [ "$titles" != 1 ]; then
    violate title "expected exactly one '### ' title line, found $titles"
  fi
  if [ "$titles" -ge 1 ]; then
    title_line="$(grep -n -m 1 '^### ' "$TMP/body" | cut -d: -f1)"
    title_text="$(sed -n "${title_line}p" "$TMP/body" | sed -E 's/^### //; s/[[:space:]]+$//')"
    case "$title_text" in
      *'?'|*'!'|*'…'|*'...') violate title "must state what changed, not tease it (ends in '${title_text: -1}'): $title_text" ;;
    esac
  fi

  # --- meta ---
  if [ -n "$title_line" ]; then
    meta="$(sed -n "$((title_line + 1)),\$p" "$TMP/body" | grep -m 1 -v '^[[:space:]]*$' || true)"
    case "$meta" in
      '*'*'[PR #'*) ;;
      *) violate meta "the first non-empty line after the title must start with * and contain [PR # (got '${meta:-nothing}')" ;;
    esac
  else
    violate meta "no title, so no meta line to check"
  fi

  # --- why ---
  grep -q '^\*\*Why:\*\*' "$TMP/body" || violate why "no line starting with **Why:**"

  # --- sections ---
  # Content of a section = the non-empty lines after its header up to the next bold-only line.
  section_info() { # header -> "<line> <content-lines>" or "" when absent
    awk -v h="$1" '
      $0 == h { if (!found) { found = 1; line = NR; next } }
      found && /^\*\*[^*]+\*\*[[:space:]]*$/ { stop = 1 }
      found && !stop && $0 !~ /^[[:space:]]*$/ { n++ }
      END { if (found) print line, n + 0 }
    ' "$TMP/body"
  }
  w="$(section_info '**What changes for you**')"
  o="$(section_info '**Left open**')"
  if [ -z "$w" ]; then violate sections "missing **What changes for you**"; fi
  if [ -z "$o" ]; then violate sections "missing **Left open**"; fi
  if [ -n "$w" ] && [ -n "$o" ]; then
    [ "${w%% *}" -lt "${o%% *}" ] || violate sections "**What changes for you** must come before **Left open**"
  fi
  if [ -n "$w" ] && [ "${w##* }" = 0 ]; then violate sections "**What changes for you** has no content"; fi
  if [ -n "$o" ] && [ "${o##* }" = 0 ]; then violate sections "**Left open** has no content (write 'Nothing.' when nothing is open)"; fi

fi

if [ "$MODE" = digest ]; then
  # --- headlines ---
  if ! grep -q '^\*\*Headlines\*\*[[:space:]]*$' "$TMP/body"; then
    violate headlines "missing the **Headlines** line"
  else
    n="$(awk '
      /^\*\*Headlines\*\*[[:space:]]*$/ { if (!found) { found = 1; next } }
      found && /^(#|\*\*)/ { stop = 1 }
      found && !stop && /^- / { n++ }
      END { print n + 0 }
    ' "$TMP/body")"
    { [ "$n" -ge 1 ] && [ "$n" -le 3 ]; } || violate headlines "expected 1 to 3 bullets under **Headlines**, found $n"
  fi

  # --- arc ---
  arcs="$(grep '^### ' "$TMP/body" | sed -E 's/^### //; s/[[:space:]]+$//' | grep -vc -i '^also merged$' || true)"
  [ "$arcs" -ge 1 ] || violate arc "expected at least one '### ' section other than 'Also merged'"

  # --- missing-pr ---
  grep -oE '\]\([^)]*\)' "$TMP/body" > "$TMP/targets" || true
  for n in $PRS; do
    grep -qE "/pull/$n([^0-9]|\$)" "$TMP/targets" || violate missing-pr "#$n is in prs but has no link to its pull request in the body"
  done
fi

# --- unpinned-link ---
grep -oE 'github\.com/[^/[:space:])]+/[^/[:space:])]+/(blob|tree)/[^/[:space:])#?]+' "$TMP/body" 2>/dev/null \
  | sort -u | while IFS= read -r link; do
      ref="${link##*/}"
      [[ "$ref" =~ ^[0-9a-f]{40}$ ]] || echo "$link"
    done > "$TMP/unpinned"
while IFS= read -r link; do
  [ -n "$link" ] && violate unpinned-link "$link is not pinned to a 40-character commit sha"
done < "$TMP/unpinned"

# --- bare-url ---
sed -E 's/\]\([^)]*\)/]()/g' "$TMP/body" | grep -nE 'https?://' | head -n 5 > "$TMP/bare" || true
while IFS= read -r hit; do
  [ -n "$hit" ] && violate bare-url "URL outside a Markdown link: $(printf '%s' "$hit" | cut -c1-100)"
done < "$TMP/bare"

[ "$violations" = 0 ]
