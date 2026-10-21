#!/usr/bin/env bash
#
# Tests for tone-lint.sh and for its wiring in post-review.sh.
#
#   bash skills/review-publish/tests/run-tests.sh
#
# Part 1 runs tone-lint.sh over the payloads in payloads/ plus one generated payload per banned
# phrase. Part 2 runs post-review.sh (dry run and real post) against a stub `gh` kept in a temp dir.
# The real-post stub accepts `gh api` and records it, so nothing here ever reaches GitHub.
# Exit code is 0 only when every test passes.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
LINT="$ROOT/bin/skill-scripts/review/tone-lint.sh"
POST="$ROOT/bin/skill-scripts/review/post-review.sh"
PAY="$HERE/payloads"
EVALS="$HERE/../evals"

command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }

TMP="$(mktemp -d -t dtk-lint-tests.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
report() { # name ok detail
  if [ "$2" = 1 ]; then pass=$((pass + 1)); printf 'PASS  %s\n' "$1"
  else fail=$((fail + 1)); printf 'FAIL  %s\n        %s\n' "$1" "$3"; fi
}

# expect_lint <name> <payload> <want-rc> [text the output must name]
expect_lint() {
  local out rc ok=1 why=""
  if [ -f "$LINT" ]; then out="$(bash "$LINT" --payload "$2" 2>&1)"; rc=$?
  else out="tone-lint.sh does not exist"; rc=127; fi
  [ "$rc" = "$3" ] || { ok=0; why="exit $rc, wanted $3: $out"; }
  if [ "$ok" = 1 ] && [ -n "${4:-}" ] && ! grep -qiF -- "$4" <<<"$out"; then ok=0; why="output does not name '$4': $out"; fi
  report "$1" "$ok" "$why"
}

echo "== tone-lint.sh =="
expect_lint "clean: approve with a FFT and a Q"            "$PAY/clean-approve.json"                0
expect_lint "clean: CR as REQUEST_CHANGES with a suggestion" "$PAY/clean-request-changes.json"      0
expect_lint "clean: LGTM with no comments"                  "$PAY/clean-no-comments.json"            0
expect_lint "clean: a suggestion fence is not counted as sentences" "$PAY/suggestion-fence-not-counted.json" 0
expect_lint "rejects 'might be worth' in a comment"         "$PAY/hedge-might-be-worth.json"         1 "might be worth"
expect_lint "rejects 'maybe' in the review body"            "$PAY/hedge-in-review-body.json"         1 "maybe"
expect_lint "rejects 'feel free to ignore' on a CR"         "$PAY/hedge-optional-on-cr.json"         1 "feel free to ignore"
expect_lint "rejects a comment with no Q:/CR:/FFT: prefix"  "$PAY/missing-tag-prefix.json"           1 "missing-tag-prefix"
expect_lint "rejects a comment over two sentences"          "$PAY/three-sentences.json"              1 "too-many-sentences"
expect_lint "rejects a CR under COMMENT"                    "$PAY/cr-as-comment.json"                1 "cr-needs-request-changes"
expect_lint "rejects a CR under APPROVE"                    "$PAY/cr-as-approve.json"                1 "cr-needs-request-changes"

# One generated payload per banned phrase, in the body and in a comment, upper-cased to prove case-insensitivity.
PHRASES=("might be worth" "maybe" "could be worth" "feel free to ignore" "totally optional" "take it or leave it" "fine to leave" "not a big deal" "just a thought")
for phrase in "${PHRASES[@]}"; do
  up="$(tr '[:lower:]' '[:upper:]' <<<"$phrase")"
  jq --arg t "FFT: I'd clamp it, $up." '.comments = [{path:"resources/js/cart.js", line:8, tag:"FFT", body:$t}]' "$PAY/clean-approve.json" > "$TMP/c.json"
  expect_lint "rejects '$phrase' in a comment (upper case)" "$TMP/c.json" 1 "$phrase"
  jq --arg t "Approving, $phrase." '.body = $t | .comments = []' "$PAY/clean-approve.json" > "$TMP/b.json"
  expect_lint "rejects '$phrase' in the review body" "$TMP/b.json" 1 "$phrase"
done

echo
echo "== post-review.sh wires the lint in =="
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Test-only gh: reads come from the eval fixtures, `gh api` is recorded and answered locally.
if [ "${1:-}" = "api" ]; then
  echo "gh $*" >> "$STUB_LOG"; cat >/dev/null
  echo "posted: COMMENTED https://github.com/acme/shop/pull/101#pullrequestreview-1"
  exit 0
fi
exec "$EVALS_GH" "$@"
STUB
chmod +x "$TMP/bin/gh"

post() { # <payload> [--dry-run]; output in $POUT, exit code in $PRC
  : > "$TMP/stub.log"
  POUT="$(cd "$TMP" && PATH="$TMP/bin:$PATH" STUB_LOG="$TMP/stub.log" EVALS_GH="$EVALS/bin/gh" \
    EVAL_GH_LOG="$TMP/stub.log" EVAL_PR=101 EVAL_BASE=main \
    EVAL_HEAD_SHA="$(jq -r .head_sha "$EVALS/cases.json")" EVAL_PR_DIFF="$EVALS/fixtures/pr.diff" \
    bash "$POST" --payload "$1" "${@:2}" 2>&1)"; PRC=$?
}
posted() { grep -q '^gh api' "$TMP/stub.log"; }

# expect_refused <name> <payload> <rule> [--dry-run]
expect_refused() {
  local ok=1 why=""
  post "$2" "${@:4}"
  [ "$PRC" = 1 ] || { ok=0; why="exit $PRC, wanted 1: $POUT"; }
  if [ "$ok" = 1 ] && ! grep -qiF -- "$3" <<<"$POUT"; then ok=0; why="refusal does not name '$3': $POUT"; fi
  if [ "$ok" = 1 ] && posted; then ok=0; why="a review was posted"; fi
  report "$1" "$ok" "$why"
}

expect_refused "dry run refuses a hedged payload, naming the phrase" "$PAY/hedge-might-be-worth.json" "might be worth" --dry-run
expect_refused "dry run refuses a CR under COMMENT, naming the rule"  "$PAY/cr-as-comment.json" "cr-needs-request-changes" --dry-run
expect_refused "real post refuses a hedged payload"                   "$PAY/hedge-might-be-worth.json" "might be worth"
expect_refused "real post refuses a CR under COMMENT"                 "$PAY/cr-as-comment.json" "cr-needs-request-changes"
expect_refused "real post refuses a missing tag prefix"               "$PAY/missing-tag-prefix.json" "missing-tag-prefix"

post "$PAY/clean-request-changes.json" --dry-run
if [ "$PRC" = 0 ] && grep -q "dry run ok: REQUEST_CHANGES" <<<"$POUT" && ! posted; then report "dry run accepts a clean REQUEST_CHANGES payload" 1 ""
else report "dry run accepts a clean REQUEST_CHANGES payload" 0 "exit $PRC: $POUT"; fi

post "$PAY/clean-request-changes.json"
if [ "$PRC" = 0 ] && posted; then report "real post goes through for a clean payload" 1 ""
else report "real post goes through for a clean payload" 0 "exit $PRC, posted=$(posted && echo yes || echo no): $POUT"; fi

echo
echo "passed $pass / $((pass + fail))"
[ "$fail" -eq 0 ]
