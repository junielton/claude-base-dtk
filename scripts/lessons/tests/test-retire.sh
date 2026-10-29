#!/bin/bash
# AC-4: retire-lessons.mjs reads an outcomes JSON and proposes `retired` for lessons
# with >= N refuted/marked-wrong findings and 0 accepted; it writes only with --apply.
set -u
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
RETIRE="$LESSONS_SCRIPTS/retire-lessons.mjs"
LOADER="$SKILL_SCRIPTS/review/lessons-loader.sh"
P=$(make_project)
trap 'rm -rf "$P"' EXIT
git -C "$P" add -A && git -C "$P" commit -qm base
run() { (cd "$P" && node "$RETIRE" "$@"); }
SEC="$P/docs/lessons/security/001-parameterize-raw-queries.md"
QA="$P/docs/lessons/qa/001-validate-empty-payloads.md"
LEG="$P/docs/lessons/code-patterns/001-legacy-no-frontmatter.md"

# Dry run (default N=3): proposes the two lessons that qualify, writes nothing.
out=$(run --outcomes "$FIXTURES/outcomes-findings.json" 2>&1); rc=$?
assert_eq           "dry run exits 0"                        "$rc" "0"
assert_contains     "proposes active lesson (3 neg, 0 acc)"  "$out" "security/001-parameterize-raw-queries.md"
assert_contains     "proposes candidate lesson (3 neg)"      "$out" "qa/001-validate-empty-payloads.md"
assert_not_contains "keeps lesson with an accepted finding"  "$out" "code-patterns/001-legacy-no-frontmatter.md"
assert_not_contains "skips already-retired lesson"           "$out" "performance/001-cache-every-query.md"
assert_contains     "reports unmatched refs"                 "$out" "frontend/404-not-a-lesson.md"
assert_eq           "dry run writes nothing" "$(git -C "$P" status --porcelain)" ""

# Threshold: with N=4 neither qualifies (each has exactly 3 negatives).
out=$(run --outcomes "$FIXTURES/outcomes-findings.json" --min-negative 4 2>&1)
assert_not_contains "N=4: security not proposed" "$out" "security/001-parameterize-raw-queries.md"
assert_not_contains "N=4: qa not proposed"       "$out" "qa/001-validate-empty-payloads.md"

# --apply writes status: retired and nothing else; the loader stops loading it.
run --outcomes "$FIXTURES/outcomes-findings.json" --apply >/dev/null 2>&1
assert_contains "apply: security retired"  "$(head -4 "$SEC")" "status: retired"
assert_contains "apply: qa retired"        "$(head -4 "$QA")"  "status: retired"
assert_contains "apply: source kept"       "$(head -4 "$SEC")" "source: own"
assert_eq "apply: only the status line changed" \
  "$(git -C "$P" diff --numstat | awk '{a+=$1; d+=$2} END {print a" "d}')" "2 2"
assert_eq "apply: legacy untouched" "$(git -C "$P" diff --name-only -- docs/lessons/code-patterns)" ""
loaded=$(cd "$P" && HOME="$P/home" bash "$LOADER" --list --include-candidates)
assert_not_contains "apply: loader drops retired" "$loaded" "security/001-parameterize-raw-queries.md"

# Shape B (aggregated counts); a lesson with no frontmatter gains one on --apply.
git -C "$P" checkout -q -- docs
out=$(run --outcomes "$FIXTURES/outcomes-by-lesson.json" 2>&1)
assert_contains     "shape B: proposes legacy"         "$out" "code-patterns/001-legacy-no-frontmatter.md"
assert_not_contains "shape B: 1 negative not enough"   "$out" "security/001-parameterize-raw-queries.md"
run --outcomes "$FIXTURES/outcomes-by-lesson.json" --apply >/dev/null 2>&1
assert_eq       "shape B apply: frontmatter added" "$(head -3 "$LEG")" $'---\nstatus: retired\n---'
assert_contains "shape B apply: body kept" "$(cat "$LEG")" "Return early from a function"

# Bad input: unreadable / wrong shape → exit 1.
run --outcomes "$P/missing.json" >/dev/null 2>&1; rc=$?
assert_eq "missing outcomes file: exit 1" "$rc" "1"
echo '{"nope": []}' > "$P/bad.json"
run --outcomes "$P/bad.json" >/dev/null 2>&1; rc=$?
assert_eq "unknown shape: exit 1" "$rc" "1"

finish
