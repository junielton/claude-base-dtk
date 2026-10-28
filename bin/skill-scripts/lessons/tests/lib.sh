#!/bin/bash
# Shared helpers for the lessons tests. Paths resolve from this file, so the
# suite keeps working if bin/skill-scripts/ is renamed to scripts/.
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LESSONS_SCRIPTS="$(cd "$TESTS_DIR/.." && pwd)"
SKILL_SCRIPTS="$(cd "$LESSONS_SCRIPTS/.." && pwd)"
FIXTURES="$TESTS_DIR/fixtures"
FAILS=0

# A throwaway project: its own git repo with the fixture lessons in docs/lessons/,
# and HOME pointed inside it so the loader's auto-memory fallback reads nothing real.
make_project() {
  local dir
  dir=$(mktemp -d)
  git -C "$dir" init -q
  git -C "$dir" config user.email t@example.com
  git -C "$dir" config user.name test
  mkdir -p "$dir/docs"
  cp -R "$FIXTURES/lessons" "$dir/docs/lessons"
  mkdir -p "$dir/home"
  echo "$dir"
}

pass() { echo "  ok   $1"; }
fail() { echo "  FAIL $1"; FAILS=$((FAILS + 1)); }

assert_contains() { # name haystack needle
  if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1 (missing: $3)"; fi
}
assert_not_contains() {
  if [[ "$2" != *"$3"* ]]; then pass "$1"; else fail "$1 (unexpected: $3)"; fi
}
assert_eq() { # name actual expected
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 (got: $2, want: $3)"; fi
}

finish() {
  if [[ $FAILS -eq 0 ]]; then echo "PASS $(basename "$0")"; exit 0; fi
  echo "FAIL $(basename "$0"): $FAILS assertion(s)"; exit 1
}
