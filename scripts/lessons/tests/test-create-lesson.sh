#!/bin/bash
# AC-1: create-lesson.sh stamps `status` + `source` frontmatter: own → active,
# peer → candidate; the duplicate check still reads the title under frontmatter.
set -u
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
CREATE="$LESSONS_SCRIPTS/create-lesson.sh"
P=$(make_project)
trap 'rm -rf "$P"' EXIT
body() { printf '### %s\n\n**Rule:** %s\n' "$1" "$2"; }

f=$(cd "$P" && body "Own lesson" "Do the own thing." | bash "$CREATE" --category qa --title "Own lesson" --severity High --source own)
head=$(head -4 "$f")
assert_contains "own: frontmatter opens"  "$(head -1 "$f")" "---"
assert_contains "own: status active"      "$head" "status: active"
assert_contains "own: source own"         "$head" "source: own"
assert_contains "own: body kept"          "$(cat "$f")" "Do the own thing."

f=$(cd "$P" && body "Peer lesson" "Do the peer thing." | bash "$CREATE" --category qa --title "Peer lesson" --severity Low --source peer)
head=$(head -4 "$f")
assert_contains "peer: status candidate" "$head" "status: candidate"
assert_contains "peer: source peer"      "$head" "source: peer"

f=$(cd "$P" && body "Default lesson" "Default." | bash "$CREATE" --category qa --title "Default lesson" --severity Low)
assert_contains "no --source: active/own" "$(head -4 "$f")" "status: active"
assert_contains "no --source: own"        "$(head -4 "$f")" "source: own"

out=$(cd "$P" && bash "$CREATE" --category security --title "Parameterize raw queries" --severity High --check-dup)
assert_contains "dup check sees title under frontmatter" "$out" "DUPLICATE:"

out=$(cd "$P" && echo x | bash "$CREATE" --category qa --title "Bad" --severity Low --source someone 2>&1); rc=$?
assert_eq "bad --source rejected" "$rc" "1"

finish
