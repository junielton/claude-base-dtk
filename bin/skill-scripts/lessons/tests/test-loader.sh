#!/bin/bash
# AC-2: lessons-loader.sh loads only `active` lessons by default (a lesson with no
# `status:` counts as active); --include-candidates adds candidates; retired never loads.
set -u
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
LOADER="$SKILL_SCRIPTS/review/lessons-loader.sh"
P=$(make_project)
trap 'rm -rf "$P"' EXIT
run() { (cd "$P" && HOME="$P/home" bash "$LOADER" "$@"); }

out=$(run --list)
assert_contains     "default list has active"            "$out" "security/001-parameterize-raw-queries.md"
assert_contains     "default list has legacy (no status)" "$out" "code-patterns/001-legacy-no-frontmatter.md"
assert_not_contains "default list skips candidate"       "$out" "qa/001-validate-empty-payloads.md"
assert_not_contains "default list skips retired"         "$out" "performance/001-cache-every-query.md"

out=$(run --list --include-candidates)
assert_contains     "--include-candidates has candidate" "$out" "qa/001-validate-empty-payloads.md"
assert_contains     "--include-candidates has active"    "$out" "security/001-parameterize-raw-queries.md"
assert_not_contains "--include-candidates skips retired" "$out" "performance/001-cache-every-query.md"

out=$(run --content)
assert_contains     "content has active rule"     "$out" "Never interpolate request input"
assert_not_contains "content skips candidate"     "$out" "Reject an empty request body"
assert_not_contains "content skips retired"       "$out" "Wrap every repository read"

out=$(run --json)
assert_contains "json counts only active" "$out" '"count": 2,'

out=$(run --category qa --content)
assert_contains "category qa default: nothing" "$out" "No lessons found."
out=$(run --include-candidates --category qa --content)
assert_contains "category qa with candidates" "$out" "Reject an empty request body"

finish
