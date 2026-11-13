#!/usr/bin/env bash
#
# Sentence coverage for a pr-story story: proves that every sentence of the FINAL text rests
# on a claim a verifier confirmed, or is a pure transition.
#
#   story-sentences.sh list  <story>
#   story-sentences.sh check <story> <map> <verdicts>
#
# list   prints one line per sentence of the story body: "s<N>/<checksum> <sentence>".
#        A sentence ends at . ! or ? followed by the next word in any case (a login can open
#        it), except after e.g., i.e., vs., etc. and single-letter initials.
#        Frontmatter, the "### " title, the meta line and the bold section headings are not
#        sentences; the Why line, every paragraph sentence and every bullet are. The checksum
#        is cksum(1) of the sentence, so a sentence rewritten after it was mapped gets a new
#        key and must be mapped again.
#
# check  reads the map and the verdicts and prints one "<rule>: <detail>" line per problem.
#   map       one line per sentence: "<key> <ids>" where <key> is copied from `list` and <ids>
#             is "c3" or "c3,c7" (the claims that together state every fact of the sentence),
#             or "<key> transition" for a sentence with no fact, no number, no attribution.
#   verdicts  one line per claim that came back from a verifier: "<id> <verdict> [<basis>]",
#             like "c3 confirmed primary" or "c7 weak author-only". Lines starting # are notes.
#   Rules:
#     unmapped          a sentence of the story has no map line
#     stale-map         a map line names a sentence the story no longer has (it was rewritten)
#     bad-map           a map line that is not "<key> <ids|transition>"
#     bad-verdicts      a verdicts line that is not "<id> <confirmed|wrong|weak> [basis]"
#     not-a-transition  a sentence marked transition holds a number, a link, inline code, an
#                       attribution verb, the PR author's name, or more than 15 words
#     no-verdict        a mapped claim id has no verdict
#     unproven          a mapped claim is wrong, or weak for a reason other than author-only
#     unattributed      a sentence resting on a weak author-only claim does not name the author
#
# Exit 0 when every sentence is covered. Exit 1 with violations. Exit 2 on bad usage or an
# unreadable file. Needs bash, awk, sed and cksum (bash 3.2 is enough).

set -uo pipefail

usage() { echo "usage: story-sentences.sh list <story> | check <story> <map> <verdicts>" >&2; exit 2; }
readable() { [ -f "$1" ] && [ -r "$1" ] || { echo "story-sentences: cannot read $1" >&2; exit 2; }; }

# body <story>: the story without its frontmatter, carriage returns removed.
body() {
  local close
  if [ "$(head -n 1 "$1" | tr -d '\r')" = "---" ]; then
    close="$(awk 'NR > 1 && /^---[[:space:]]*$/ { print NR; exit }' "$1")"
    if [ -n "$close" ]; then sed -n "$((close + 1)),\$p" "$1" | tr -d '\r'; return; fi
  fi
  tr -d '\r' < "$1"
}

# sentences <story>: one sentence per line, markup kept (links, code, bold inside a sentence).
sentences() {
  body "$1" | awk -v q="'" '
    function emit(s) {
      sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s)
      if (s != "") print s
    }
    BEGIN {
      # A sentence ends at . ! or ? (plus closing quotes or parens) followed by blanks and the
      # next word, whatever its case: a login such as "octocat says" starts lowercase.
      re = "[.!?][)\"" q "]*[ \t]+[A-Za-z0-9\"(`*[" q "]"
      n = split("e.g i.e vs etc cf approx al fig no nr", a, " ")
      for (i = 1; i <= n; i++) abbr[a[i]] = 1
    }
    /^[ \t]*$/ { next }
    /^### / { next }
    /^\*\*[^*]+\*\*[ \t]*$/ { next }
    /^\*[^* ]/ && index($0, "[PR #") { next }
    {
      line = $0
      sub(/^[ \t]*[-*+][ \t]+/, "", line)
      sub(/^\*\*Why:\*\*[ \t]*/, "", line)
      acc = ""
      while (match(line, re)) {
        at = RSTART; cut = RSTART + RLENGTH - 1
        pre = substr(line, 1, at - 1); w = ""
        if (match(pre, /[A-Za-z]+(\.[A-Za-z]+)*$/)) w = tolower(substr(pre, RSTART))
        # "e.g." or an initial ("J. Doe") does not end a sentence.
        if (substr(line, at, 1) == "." && ((w in abbr) || length(w) == 1)) {
          acc = acc substr(line, 1, cut - 1); line = substr(line, cut); continue
        }
        emit(acc substr(line, 1, cut - 1)); acc = ""
        line = substr(line, cut)
      }
      emit(acc line)
    }'
}

list() {
  local n=0 s sum
  while IFS= read -r s; do
    n=$((n + 1))
    sum="$(printf '%s' "$s" | cksum | cut -d' ' -f1)"
    printf 's%d/%s %s\n' "$n" "$sum" "$s"
  done < <(sentences "$1")
}

# author <story>: the third " · " field of the meta line (the PR author), or nothing.
author() {
  body "$1" | awk '/^\*[^* ]/ && index($0, "[PR #") { print; exit }' \
    | awk -F ' · ' '{ a = $3; gsub(/^[ \t*]+|[ \t*]+$/, "", a); print a }'
}

check() {
  local story="$1" map="$2" verdicts="$3" tmp rc
  tmp="$(mktemp -t dtk-story-sentences.XXXXXX)" || exit 2
  list "$story" > "$tmp"
  # One awk pass over three files: the sentence list, the verdicts, then the map.
  awk -v who="$(author "$story")" '
    function trim(s) { gsub(/\r/, "", s); sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function short(s) { return length(s) <= 100 ? s : substr(s, 1, 100) "…" }
    function violate(rule, detail) { print rule ": " detail; bad++ }
    function attributed(t) {
      t = " " tolower(t) " "
      return t ~ /[^a-z](says|said|say|according to|writes|wrote|reports|reported|states|stated|claims|claimed|notes|noted|mentions|mentioned|confirms)[^a-z]/
    }
    function names_author(t) { return who != "" && index(tolower(t), tolower(who)) > 0 }

    FILENAME == ARGV[1] {
      k = $0; sub(/ .*/, "", k); t = $0; sub(/^[^ ]+ /, "", t)
      order[++n] = k; sentence[k] = t
      next
    }
    FILENAME == ARGV[2] {
      line = trim($0)
      if (line == "" || line ~ /^#/) next
      if (line ~ /^c[0-9]+[ \t]+(confirmed|wrong|weak)([ \t]+[a-z-]+)?$/) {
        split(line, f, /[ \t]+/); verdict[f[1]] = f[2]; basis[f[1]] = f[3]
      } else violate("bad-verdicts", short(line))
      next
    }
    {
      line = trim($0)
      if (line == "" || line ~ /^#/) next
      if (line ~ /^s[0-9]+\/[0-9]+[ \t]+(transition|c[0-9]+(,c[0-9]+)*)$/) {
        split(line, f, /[ \t]+/)
        if (f[1] in sentence) mapped[f[1]] = f[2]
        else violate("stale-map", f[1] " is not a sentence of the story (rewritten or removed): map it again from list")
      } else violate("bad-map", short(line) " (want <key> c1[,c2...] or <key> transition)")
    }
    END {
      for (i = 1; i <= n; i++) {
        k = order[i]; t = sentence[k]
        if (!(k in mapped)) { violate("unmapped", k " " short(t)); continue }
        if (mapped[k] == "transition") {
          why = ""
          if (t ~ /[0-9]/) why = "holds a number"
          else if (index(t, "](") || index(t, "http")) why = "holds a link"
          else if (index(t, "`")) why = "holds inline code"
          else if (attributed(t)) why = "is attributed"
          else if (names_author(t)) why = "names the author"
          else if (split(t, w, /[ \t]+/) > 15) why = "has " length(w) " words"
          if (why != "") violate("not-a-transition", k " " why ": " short(t))
          continue
        }
        m = split(mapped[k], ids, ",")
        for (j = 1; j <= m; j++) {
          id = ids[j]
          if (!(id in verdict)) violate("no-verdict", k " " id ": send the claim to a verifier")
          else if (verdict[id] == "confirmed") { }
          else if (verdict[id] == "weak" && basis[id] == "author-only") {
            if (!(who != "" ? names_author(t) : attributed(t)))
              violate("unattributed", k " " id " rests on the author" "\047" "s word only: name " (who != "" ? who : "the author") " in the sentence")
          } else
            violate("unproven", k " " id " (" verdict[id] (basis[id] != "" ? " " basis[id] : "") "): verify the corrected sentence as a new claim")
        }
      }
      exit bad > 0
    }' "$tmp" "$verdicts" "$map"
  rc=$?
  rm -f "$tmp"
  return "$rc"
}

case "${1:-}" in
  list)  [ $# -eq 2 ] || usage; readable "$2"; list "$2" ;;
  check) [ $# -eq 4 ] || usage; readable "$2"; readable "$3"; readable "$4"; check "$2" "$3" "$4" ;;
  *) usage ;;
esac
