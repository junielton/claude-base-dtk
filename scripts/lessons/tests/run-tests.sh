#!/bin/bash
# Runs every lessons test (offline, built-ins only).
#   bash bin/skill-scripts/lessons/tests/run-tests.sh
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUS=0
for t in "$DIR"/test-*.sh; do
  echo "== $(basename "$t")"
  bash "$t" || STATUS=1
done
[[ $STATUS -eq 0 ]] && echo "ALL PASS" || echo "SOME FAILED"
exit $STATUS
