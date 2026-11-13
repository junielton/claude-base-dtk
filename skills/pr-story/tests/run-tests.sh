#!/usr/bin/env bash
#
# Offline tests for the pr-story scripts: story-target.sh, story-cache.sh, check-story.sh,
# list-merged.sh, and check-story.sh --digest.
#
#   bash skills/pr-story/tests/run-tests.sh
#
# `gh` is replaced by a stub kept in a temp dir, so nothing here reaches GitHub.
# Exit code is 0 only when every test passes.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
TARGET="$ROOT/scripts/pr-story/story-target.sh"
CACHE="$ROOT/scripts/pr-story/story-cache.sh"
CHECK="$ROOT/scripts/pr-story/check-story.sh"
LIST="$ROOT/scripts/pr-story/list-merged.sh"
FIX="$HERE/fixtures"

command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }

TMP="$(mktemp -d -t dtk-pr-story-tests.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
report() { # name ok detail
  if [ "$2" = 1 ]; then pass=$((pass + 1)); printf 'PASS  %s\n' "$1"
  else fail=$((fail + 1)); printf 'FAIL  %s\n        %s\n' "$1" "$3"; fi
}

# Test-only gh: `gh repo view --json owner,name` answers acme/shop, or fails when STUB_REPO_FAIL=1.
# `gh pr list` records its arguments in $STUB_ARGS_FILE and prints the JSON in $STUB_LIST_FILE.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "repo" ] && [ "${2:-}" = "view" ]; then
  [ "${STUB_REPO_FAIL:-0}" = 1 ] && { echo "gh: not a git repository" >&2; exit 1; }
  echo '{"name":"shop","owner":{"id":"O_1","login":"acme"}}'
  exit 0
fi
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "list" ]; then
  [ -n "${STUB_ARGS_FILE:-}" ] && printf '%s\n' "$*" > "$STUB_ARGS_FILE"
  cat "${STUB_LIST_FILE:-/dev/null}"
  exit 0
fi
echo "stub gh: unexpected call: $*" >&2
exit 99
STUB
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"

# run_script <script> <args...>: sets OUT (stdout), ERR (stderr) and RC.
run_script() {
  local script="$1"; shift
  if [ ! -f "$script" ]; then OUT=""; ERR="$(basename "$script") does not exist"; RC=127; return; fi
  OUT="$(bash "$script" "$@" 2>"$TMP/err")"; RC=$?
  ERR="$(cat "$TMP/err")"
}

# expect <name> <want-rc> <want-stdout|-> <stderr-must-contain|-> <script> <args...>
expect() {
  local name="$1" want_rc="$2" want_out="$3" want_err="$4"; shift 4
  run_script "$@"
  local ok=1 why=""
  [ "$RC" = "$want_rc" ] || { ok=0; why="exit $RC, wanted $want_rc (stderr: $ERR)"; }
  if [ "$ok" = 1 ] && [ "$want_out" != "-" ] && [ "$OUT" != "$want_out" ]; then ok=0; why="stdout '$OUT', wanted '$want_out'"; fi
  if [ "$ok" = 1 ] && [ "$want_err" != "-" ] && ! grep -qF -- "$want_err" <<<"$ERR"; then ok=0; why="stderr '$ERR' does not contain '$want_err'"; fi
  report "$name" "$ok" "$why"
}

# expect_viol <name> <rule:> <file>: check-story.sh exits 1 and names the rule on stdout.
expect_viol() {
  run_script "$CHECK" "$3"
  local ok=1 why=""
  [ "$RC" = 1 ] || { ok=0; why="exit $RC, wanted 1 (stdout: $OUT; stderr: $ERR)"; }
  if [ "$ok" = 1 ] && ! grep -qF -- "$2" <<<"$OUT"; then ok=0; why="stdout '$OUT' does not name '$2'"; fi
  report "$1" "$ok" "$why"
}

echo "== story-target.sh =="
export STUB_REPO_FAIL=0
expect "bare number resolves the repo through gh"      0 '{"owner":"acme","repo":"shop","number":15}' - "$TARGET" "15"
expect "#number resolves the repo through gh"          0 '{"owner":"acme","repo":"shop","number":15}' - "$TARGET" "#15"
expect "owner/repo#n"                                  0 '{"owner":"octo","repo":"cat","number":7}'   - "$TARGET" "octo/cat#7"
expect "PR URL with /files and ?w=1"                   0 '{"owner":"octo","repo":"cat","number":7}'   - "$TARGET" "https://github.com/octo/cat/pull/7/files?w=1"
expect "PR URL with #discussion fragment"              0 '{"owner":"octo","repo":"cat","number":7}'   - "$TARGET" "https://github.com/octo/cat/pull/7#discussion_r9"
expect "PR URL with /commits/<sha>"                    0 '{"owner":"octo","repo":"cat","number":7}'   - "$TARGET" "https://github.com/octo/cat/pull/7/commits/0123456789abcdef0123456789abcdef01234567"
expect "plain PR URL"                                  0 '{"owner":"octo","repo":"cat","number":7}'   - "$TARGET" "https://github.com/octo/cat/pull/7"
expect "dotted and dashed repo names"                  0 '{"owner":"my-org","repo":"web.app-2","number":12}' - "$TARGET" "my-org/web.app-2#12"
STUB_REPO_FAIL=1 expect "bare number outside a GitHub checkout exits 2" 2 "" "owner/repo#n" "$TARGET" "15"
expect "text that is not a PR reference exits 2"       2 "" "owner/repo#n" "$TARGET" "hello"
expect "an issue URL is not a PR reference"            2 "" "owner/repo#n" "$TARGET" "https://github.com/octo/cat/issues/7"
expect "no argument exits 2"                           2 "" "owner/repo#n" "$TARGET"

echo
echo "== story-cache.sh =="
export XDG_DATA_HOME=/tmp/x
expect "path"                                          0 "/tmp/x/dtk/stories/octo/cat/PR-7.md"    - "$CACHE" path octo cat 7
expect "path with a language"                          0 "/tmp/x/dtk/stories/octo/cat/PR-7.pt.md" - "$CACHE" path octo cat 7 pt
expect "path with lang en is the default file"         0 "/tmp/x/dtk/stories/octo/cat/PR-7.md"    - "$CACHE" path octo cat 7 en
expect "path rejects a non-numeric PR number"          2 "" - "$CACHE" path octo cat seven
expect "path rejects a language that could escape"     2 "" - "$CACHE" path octo cat 7 "../x"
expect "digest-path"                                   0 "/tmp/x/dtk/stories/octo/cat/digest-2026-11-06-2026-11-13.md"    - "$CACHE" digest-path octo cat 2026-11-06 2026-11-13
expect "digest-path with a language"                   0 "/tmp/x/dtk/stories/octo/cat/digest-2026-11-06-2026-11-13.pt.md" - "$CACHE" digest-path octo cat 2026-11-06 2026-11-13 pt
(
  unset XDG_DATA_HOME; export HOME=/home/someone
  expect "root falls back to \$HOME/.local/share"      0 "/home/someone/.local/share/dtk/stories/octo/cat/PR-7.md" - "$CACHE" path octo cat 7
)

printf -- '---\npr: octo/cat#7\nhead_sha: abc\nlang: en\n---\n\n### Title\n' > "$TMP/story.md"
printf -- '---\npr: octo/cat#7\nlang: en\n---\n\n### No sha\n' > "$TMP/no-sha.md"
expect "status: missing file"                          0 "missing" - "$CACHE" status "$TMP/nope.md" abc
expect "status: same head sha is fresh"                0 "fresh"   - "$CACHE" status "$TMP/story.md" abc
expect "status: new head sha is stale"                 0 "stale"   - "$CACHE" status "$TMP/story.md" def
expect "status: file without a head_sha is stale"      0 "stale"   - "$CACHE" status "$TMP/no-sha.md" abc
expect "unknown subcommand exits 2"                    2 "" "usage" "$CACHE" frobnicate

echo
echo "== check-story.sh =="
expect "good story passes"                              0 "" - "$CHECK" "$FIX/good.md"
expect "a story with nothing left open passes"          0 "" - "$CHECK" "$FIX/minimal-pr.md"
expect_viol "no Why line fails: why" "why:" "$FIX/no-why.md"
expect_viol "a title ending in ? fails: title" "title:" "$FIX/hook-title.md"
expect_viol "a /blob/main/ link fails: unpinned-link" "unpinned-link:" "$FIX/unpinned.md"
expect_viol "a bare URL fails: bare-url" "bare-url:" "$FIX/bare-url.md"
expect_viol "swapped sections fail: sections" "sections:" "$FIX/sections-swapped.md"
expect_viol "no frontmatter fails: frontmatter" "frontmatter:" "$FIX/no-frontmatter.md"
expect "a missing file exits 2"                         2 "" "check-story" "$CHECK" "$TMP/nope.md"
expect "no argument exits 2"                            2 "" "usage" "$CHECK"

# Edge cases around each rule, built from good.md.
variant() { # name sed-expression  -> $TMP/<name>.md
  sed -e "$2" "$FIX/good.md" > "$TMP/$1.md"
}
variant short-sha   's/^head_sha: .*/head_sha: add2d2d/'
variant bad-date    's/^generated_at: .*/generated_at: yesterday/'
variant no-lang     '/^lang: /d'
variant bad-pr      's/^pr: .*/pr: 28/'
variant bang-title  's/^### .*/### The skill now publishes!/'
variant dots-title  's/^### .*/### The skill now publishes…/'
variant meta-text   's/^\*Feature.*/Feature, PR 28, merged/'
variant tree-main   's#blob/2f3a3a8a4ab5a0809b7045754bffddf8ffbce2ad/skills/git-rebase-onto/SKILL.md#tree/main/skills#'
variant http-url    's#^A new step 0#See http://example.com for more. A new step 0#'
{ sed '/^\*\*Left open\*\*/,$d' "$FIX/good.md"; echo '**Left open**'; } > "$TMP/empty-open.md"
expect_viol "a head_sha that is not 40 hex fails" "frontmatter:" "$TMP/short-sha.md"
expect_viol "a generated_at that is not ISO 8601 fails" "frontmatter:" "$TMP/bad-date.md"
expect_viol "a missing lang fails" "frontmatter:" "$TMP/no-lang.md"
expect_viol "a pr that is not owner/repo#n fails" "frontmatter:" "$TMP/bad-pr.md"
expect_viol "a title ending in ! fails" "title:" "$TMP/bang-title.md"
expect_viol "a title ending in an ellipsis fails" "title:" "$TMP/dots-title.md"
expect_viol "a meta line without [PR # fails" "meta:" "$TMP/meta-text.md"
expect_viol "a /tree/main link fails" "unpinned-link:" "$TMP/tree-main.md"
expect_viol "a bare http:// URL fails" "bare-url:" "$TMP/http-url.md"
expect_viol "an empty Left open fails: sections" "sections:" "$TMP/empty-open.md"

echo
echo "== check-story.sh --digest =="
# expect_dviol <name> <rule:> <file>: check-story.sh --digest exits 1 and names the rule.
expect_dviol() {
  run_script "$CHECK" --digest "$3"
  local ok=1 why=""
  [ "$RC" = 1 ] || { ok=0; why="exit $RC, wanted 1 (stdout: $OUT; stderr: $ERR)"; }
  if [ "$ok" = 1 ] && ! grep -qF -- "$2" <<<"$OUT"; then ok=0; why="stdout '$OUT' does not name '$2'"; fi
  report "$1" "$ok" "$why"
}
dvariant() { sed -e "$2" "$FIX/digest-good.md" > "$TMP/$1.md"; } # name sed-expression
expect "a good digest passes"                           0 "" - "$CHECK" --digest "$FIX/digest-good.md"
dvariant d-leap-ok       's#^from: .*#from: 2028-02-29#'
expect "a leap day is a date: 2028-02-29 passes"       0 "" - "$CHECK" --digest "$TMP/d-leap-ok.md"
expect_dviol "four headlines fail: headlines" "headlines:" "$FIX/digest-four-headlines.md"
expect_dviol "a PR in prs with no link in the body fails: missing-pr" "missing-pr:" "$FIX/digest-missing-pr.md"
dvariant no-headlines    '/^- /d'
dvariant no-arc          's/^### Checkout retries failed payment calls/### Also merged/; /^### Retry limit decision/d'
dvariant d-unpinned      's#blob/2f3a3a8a4ab5a0809b7045754bffddf8ffbce2ad/src#blob/main/src#'
dvariant d-bare          's|^\[#30\](https://github.com/acme/shop/pull/30)|See http://example.com for [#30](https://github.com/acme/shop/pull/30)|'
dvariant d-no-repo       '/^repo: /d'
dvariant d-bad-repo      's#^repo: .*#repo: shop#'
dvariant d-bad-from      's#^from: .*#from: last week#'
dvariant d-bad-to        's#^to: .*#to: 2026-13-45x#'
dvariant d-feb-31        's#^from: .*#from: 2026-02-31#'
dvariant d-no-lang       '/^lang: /d'
dvariant d-bad-date      's/^generated_at: .*/generated_at: today/'
dvariant d-no-prs        '/^prs: /d'
dvariant d-empty-prs     's/^prs: .*/prs: []/'
dvariant d-bad-prs       's/^prs: .*/prs: [15, abc]/'
dvariant d-prefix-link 's#(https://github.com/acme/shop/pull/22)#(https://github.com/acme/shop/pull/220)#'
expect_dviol "no headlines fail: headlines" "headlines:" "$TMP/no-headlines.md"
expect_dviol "an Also merged section alone is not an arc: arc" "arc:" "$TMP/no-arc.md"
expect_dviol "a /blob/main/ link fails: unpinned-link" "unpinned-link:" "$TMP/d-unpinned.md"
expect_dviol "a bare URL fails: bare-url" "bare-url:" "$TMP/d-bare.md"
expect_dviol "a missing repo fails: frontmatter" "frontmatter:" "$TMP/d-no-repo.md"
expect_dviol "a repo that is not owner/repo fails: frontmatter" "frontmatter:" "$TMP/d-bad-repo.md"
expect_dviol "a from that is not a date fails: frontmatter" "frontmatter:" "$TMP/d-bad-from.md"
expect_dviol "a to that is not a date fails: frontmatter" "frontmatter:" "$TMP/d-bad-to.md"
expect_dviol "a from of 2026-02-31 fails: frontmatter" "frontmatter:" "$TMP/d-feb-31.md"
expect_dviol "a missing lang fails: frontmatter" "frontmatter:" "$TMP/d-no-lang.md"
expect_dviol "a generated_at that is not ISO 8601 fails: frontmatter" "frontmatter:" "$TMP/d-bad-date.md"
expect_dviol "a missing prs fails: frontmatter" "frontmatter:" "$TMP/d-no-prs.md"
expect_dviol "an empty prs fails: frontmatter" "frontmatter:" "$TMP/d-empty-prs.md"
expect_dviol "a prs entry that is not a number fails: frontmatter" "frontmatter:" "$TMP/d-bad-prs.md"
expect_dviol "a link to /pull/220 does not count for #22: missing-pr" "missing-pr:" "$TMP/d-prefix-link.md"
expect_viol "a story file is not a digest: plain mode still demands a story title" "title:" "$FIX/digest-good.md"
expect "--digest without a file exits 2"                2 "" "usage" "$CHECK" --digest
expect "--digest with a missing file exits 2"           2 "" "check-story" "$CHECK" --digest "$TMP/nope.md"

echo
echo "== list-merged.sh =="
export STUB_ARGS_FILE="$TMP/gh-args"
cat > "$TMP/list.json" <<'JSON'
[
  {"number":22,"title":"fix: the retry loop","body":"Follow-up to #15 and also #15 again. See acme/shop#99.","author":{"login":"ana"},"mergedAt":"2026-11-12T10:00:00Z","additions":5,"deletions":1,"changedFiles":1,"labels":[{"name":"bug"}],"files":[{"path":"src/retry.sh"}]},
  {"number":15,"title":"feat: retry loop","body":null,"author":{"login":"bo"},"mergedAt":"2026-11-08T09:30:00Z","additions":80,"deletions":2,"changedFiles":2,"labels":[],"files":[{"path":"src/retry.sh"},{"path":"README.md"}]}
]
JSON
echo '[]' > "$TMP/empty.json"
export STUB_LIST_FILE="$TMP/list.json"
DTK_NOW=2026-11-13 run_script "$LIST" acme/shop 7d
list_out="$OUT"; list_rc=$RC
ok=1; why=""
grep -qF -- 'merged:>=2026-11-06' "$STUB_ARGS_FILE" 2>/dev/null || { ok=0; why="gh pr list was called with: $(cat "$STUB_ARGS_FILE" 2>/dev/null) (stderr: $ERR)"; }
[ "$list_rc" = 0 ] || { ok=0; why="exit $list_rc (stderr: $ERR)"; }
report "7d with DTK_NOW=2026-11-13 queries merged:>=2026-11-06" "$ok" "$why"

got="$(jq -c '[.[].number]' <<<"$list_out" 2>/dev/null)"
report "output is sorted oldest merge first" "$([ "$got" = "[15,22]" ] && echo 1 || echo 0)" "numbers '$got', wanted [15,22]"

got="$(jq -c '.[] | select(.number == 22) | .refs' <<<"$list_out" 2>/dev/null)"
report "a body 'follow-up to #15' yields refs [15]" "$([ "$got" = "[15]" ] && echo 1 || echo 0)" "refs '$got', wanted [15]"

got="$(jq -c '.[] | select(.number == 15) | .refs' <<<"$list_out" 2>/dev/null)"
report "a null body yields no refs" "$([ "$got" = "[]" ] && echo 1 || echo 0)" "refs '$got', wanted []"

got="$(jq -c '.[] | select(.number == 22) | [.author, .labels, .files, .additions, .deletions, .changedFiles, .mergedAt]' <<<"$list_out" 2>/dev/null)"
want='["ana",["bug"],["src/retry.sh"],5,1,1,"2026-11-12T10:00:00Z"]'
report "fields are flattened (author, labels, files)" "$([ "$got" = "$want" ] && echo 1 || echo 0)" "got '$got', wanted '$want'"

STUB_LIST_FILE="$TMP/empty.json" expect "an empty range prints [] and exits 0" 0 "[]" - "$LIST" acme/shop 2026-11-06
STUB_LIST_FILE="$TMP/empty.json" run_script "$LIST" acme/shop 2026-11-06
grep -qF -- 'merged:>=2026-11-06' "$STUB_ARGS_FILE" 2>/dev/null; report "a YYYY-MM-DD since is used as given" "$([ $? = 0 ] && echo 1 || echo 0)" "gh pr list was called with: $(cat "$STUB_ARGS_FILE" 2>/dev/null)"
DTK_NOW=2026-03-02 STUB_LIST_FILE="$TMP/empty.json" run_script "$LIST" acme/shop 5d
grep -qF -- 'merged:>=2026-02-25' "$STUB_ARGS_FILE" 2>/dev/null; report "relative dates cross a month boundary (5d before 2026-03-02)" "$([ $? = 0 ] && echo 1 || echo 0)" "gh pr list was called with: $(cat "$STUB_ARGS_FILE" 2>/dev/null)"
expect "a since that is not a date or Nd exits 2" 2 "" "since" "$LIST" acme/shop yesterday
expect "a repo that is not owner/repo exits 2" 2 "" "owner/repo" "$LIST" shop 7d
expect "no argument exits 2" 2 "" "usage" "$LIST"

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
