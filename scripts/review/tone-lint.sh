#!/bin/bash
#
# Tone lint for a /dtk:review-publish payload. Runs on the exact JSON that would go to GitHub,
# so it holds after the voice pass: the voice skill shapes words, it never adds hedges.
#
# Rules (every violation is reported, one line each on stderr):
#   banned-phrase             a hedge in `body` or any `comments[].body`, case-insensitive
#   missing-tag-prefix        an inline body that does not start with `Q: `, `CR: ` or `FFT: `
#   too-many-sentences        an inline body over two sentences (code spans and ``` fences do not count)
#   cr-needs-request-changes  a `CR:` comment under an event other than REQUEST_CHANGES
#
# Usage:
#   bash scripts/review/tone-lint.sh --payload <file.json>
#
# Exit: 0 clean, 1 violations, 2 usage error.

set -uo pipefail

PAYLOAD=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --payload) PAYLOAD="${2:-}"; shift 2 ;;
    *) echo "usage: tone-lint.sh --payload <file.json>" >&2; exit 2 ;;
  esac
done

[[ -f "$PAYLOAD" ]] || { echo "payload not found: $PAYLOAD" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }
jq -e . "$PAYLOAD" >/dev/null 2>&1 || { echo "payload is not valid JSON: $PAYLOAD" >&2; exit 2; }

# Keep in sync with the banned list in skills/review-publish/SKILL.md step 3.
BANNED='["might be worth","maybe","could be worth","feel free to ignore","totally optional","take it or leave it","fine to leave","not a big deal","just a thought"]'

VIOLATIONS=$(jq -r --argjson banned "$BANNED" '
  def items:
    [{where: "review body", text: (.body // ""), inline: false, tag: ""}]
    + [(.comments // []) | to_entries[]
       | {where: "comment \(.key + 1) (\(.value.path // "?"):\(.value.line // "?"))",
          text: (.value.body // ""), inline: true, tag: (.value.tag // "")}];

  # Prose only: fenced blocks, inline code and common abbreviations carry no sentence ends.
  def sentence_count:
    sub("^(Q|CR|FFT): "; "")
    | gsub("(?s)```.*?```"; " ")
    | gsub("`[^`]*`"; "x")
    | gsub("(?i)\\b(e\\.g|i\\.e|etc|vs)\\."; "x")
    | gsub("^\\s+|\\s+$"; "")
    | if . == "" then 0 else [split("(?<=[.!?])\\s+"; null)[] | select(test("\\S"))] | length end;

  . as $p
  | (items[] as $i | $banned[] as $phrase
     | select($i.text | ascii_downcase | contains($phrase))
     | "banned-phrase: \($i.where): \"\($phrase)\""),
    (items[] | select(.inline) | select(.text | test("^(Q|CR|FFT): ") | not)
     | "missing-tag-prefix: \(.where): body must start with \"Q: \", \"CR: \" or \"FFT: \""),
    (items[] | select(.inline) | select((.text | sentence_count) > 2)
     | "too-many-sentences: \(.where): \(.text | sentence_count) sentences, the limit is 2"),
    (if ($p.event // "") != "REQUEST_CHANGES"
     then items[] | select(.inline and ((.text | test("^CR: ")) or .tag == "CR"))
          | "cr-needs-request-changes: \(.where): a CR posts as REQUEST_CHANGES, the event is \($p.event // "missing")"
     else empty end)
' "$PAYLOAD")

if [[ -n "$VIOLATIONS" ]]; then
  while IFS= read -r line; do echo "tone-lint: $line" >&2; done <<<"$VIOLATIONS"
  exit 1
fi
