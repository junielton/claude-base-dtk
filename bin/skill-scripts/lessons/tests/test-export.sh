#!/bin/bash
# AC-3: export-lessons.mjs regenerates the dtk:lessons block in REVIEW.md and
# .github/copilot-instructions.md from active lessons: creates missing files, never
# touches text outside the markers, is idempotent, caps the copilot file at 4,000 chars.
set -u
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
EXPORT="$LESSONS_SCRIPTS/export-lessons.mjs"
P=$(make_project)
trap 'rm -rf "$P"' EXIT
run() { (cd "$P" && node "$EXPORT" "$@"); }
chars() { python3 -c 'import sys; print(len(open(sys.argv[1], encoding="utf-8").read()))' "$1"; }
START='<!-- dtk:lessons:start -->'
END='<!-- dtk:lessons:end -->'

# 1. Fresh repo: both files created from active lessons only.
run >/dev/null; rc=$?
assert_eq "fresh run exits 0" "$rc" "0"
R="$P/REVIEW.md"; C="$P/.github/copilot-instructions.md"
for f in "$R" "$C"; do
  n=$(basename "$f")
  body=$(cat "$f" 2>/dev/null)
  assert_contains     "$n created with start marker" "$body" "$START"
  assert_contains     "$n has end marker"            "$body" "$END"
  assert_contains     "$n has active lesson"         "$body" "Parameterize raw queries"
  assert_contains     "$n has legacy lesson"         "$body" "Return early on guard clauses"
  assert_not_contains "$n skips candidate"           "$body" "Validate empty payloads"
  assert_not_contains "$n skips retired"             "$body" "Cache every query"
done

# 2. Idempotent: a second run leaves no diff.
git -C "$P" add -A && git -C "$P" commit -qm base
run >/dev/null
assert_eq "second run: git diff --stat empty" "$(git -C "$P" diff --stat)" ""
assert_eq "second run: no untracked files"    "$(git -C "$P" status --porcelain)" ""

# 3. Text outside the markers is kept byte-for-byte; a stale block is replaced.
printf '# Review rules\n\nHand-written intro.\n\n%s\nstale line\n%s\n\nHand-written outro.\n' "$START" "$END" > "$R"
run >/dev/null
body=$(cat "$R")
assert_contains     "outside: intro kept"     "$body" $'# Review rules\n\nHand-written intro.\n\n'"$START"
assert_contains     "outside: outro kept"     "$body" "$END"$'\n\nHand-written outro.'
assert_not_contains "stale block replaced"    "$body" "stale line"
assert_contains     "block regenerated"       "$body" "Parameterize raw queries"
before=$(cat "$R"); run >/dev/null
assert_eq "outside-text run is idempotent" "$(cat "$R")" "$before"

# 4. An existing file without markers gets the block appended; its text stays a prefix.
printf 'Use tabs.\nPrefer composition.\n' > "$C"
run >/dev/null
assert_eq "no markers: original text is the prefix" "$(head -2 "$C")" $'Use tabs.\nPrefer composition.'
assert_contains "no markers: block appended" "$(cat "$C")" "$START"

# 5. Cap: many long active lessons → copilot file stays <= 4000 chars, REVIEW.md has all.
for i in $(seq -w 2 61); do
  printf -- '---\nstatus: active\nsource: own\n---\n### Lesson number %s\n\n**Severity:** Medium\n\n**Rule:** %s\n' \
    "$i" "Always do the very specific thing number $i that a reviewer must check on every pull request touching this area." \
    > "$P/docs/lessons/security/0$i-lesson-$i.md"
done
run >/dev/null
assert_eq "cap: copilot file <= 4000 chars" "$(( $(chars "$C") <= 4000 ))" "1"
assert_contains "cap: copilot points at the rest" "$(cat "$C")" "more in"
assert_contains "cap: highest severity kept first" "$(cat "$C")" "Parameterize raw queries"
assert_eq "REVIEW.md lists all 62 active" "$(grep -c '^- ' "$R")" "62"
assert_eq "cap: outside text still a prefix" "$(head -2 "$C")" $'Use tabs.\nPrefer composition.'

# 6. A smaller cap is honoured.
run --copilot-cap 1500 >/dev/null
assert_eq "custom cap honoured" "$(( $(chars "$C") <= 1500 ))" "1"

# 7. Malformed markers: refuse, write nothing.
printf 'intro\n%s\nno end marker\n' "$START" > "$R"
before=$(cat "$R")
run >/dev/null 2>&1; rc=$?
assert_eq "malformed markers: exit 2"      "$rc" "2"
assert_eq "malformed markers: file intact" "$(cat "$R")" "$before"

finish
