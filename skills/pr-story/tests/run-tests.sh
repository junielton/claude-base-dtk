#!/usr/bin/env bash
#
# Offline tests for the pr-story scripts: story-target.sh, story-cache.sh, check-story.sh.
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
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "repo" ] && [ "${2:-}" = "view" ]; then
  [ "${STUB_REPO_FAIL:-0}" = 1 ] && { echo "gh: not a git repository" >&2; exit 1; }
  echo '{"name":"shop","owner":{"id":"O_1","login":"acme"}}'
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
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
