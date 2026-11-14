#!/usr/bin/env bash
#
# Eval harness for the pr-story skill: does it produce a story that passes the format gate,
# whose links resolve, whose claims survive a fresh verifier and whose author-only claims are
# attributed?
#
# For each case in cases.json it runs `/dtk:pr-story <PR>` headless (`claude -p`, plugin loaded
# from this checkout) in an empty directory with its own XDG_DATA_HOME, so the cache starts
# empty and nothing touches the user's real cache. grade.py then reads the cache file.
# The cases are merged PRs of a public repo, so the run needs `gh` signed in and network access.
#
# Usage:
#   ./run.sh                  # 3 runs per case, default model
#   ./run.sh --runs 1         # number of independent runs per case (each one costs tokens)
#   ./run.sh --case small     # only one case (small | large)
#   ./run.sh --model opus     # override the model
#   ./run.sh --jobs 1         # parallel runs (default 1; keep it under half the cores)
#   ./run.sh --keep           # keep the work folder (stories, transcripts, grader output)
#
# Docs: README.md next to this script. Exit code is 0 only when every run passes every check.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CASES="$SCRIPT_DIR/cases.json"
GRADER="$SCRIPT_DIR/grade.py"

MODEL=""
RUNS=3
JOBS=1
KEEP=0
ONLY=""
TIMEOUT=1500

while [ $# -gt 0 ]; do
    case "$1" in
        --runs)    RUNS="$2"; shift 2 ;;
        --case)    ONLY="$2"; shift 2 ;;
        --model)   MODEL="$2"; shift 2 ;;
        --jobs)    JOBS="$2"; shift 2 ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        --keep)    KEEP=1; shift ;;
        -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done

for bin in jq claude python3 gh git; do
    command -v "$bin" >/dev/null || { echo "missing dependency: $bin" >&2; exit 2; }
done
[ -f "$CASES" ] || { echo "missing $CASES" >&2; exit 2; }
gh auth status >/dev/null 2>&1 || { echo "gh is not signed in (gh auth login)" >&2; exit 2; }

half=$(( $(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2) / 2 ))
[ "$half" -ge 1 ] || half=1
[ "$JOBS" -le "$half" ] || { echo "--jobs $JOBS exceeds half the cores ($half)" >&2; exit 2; }

WORK="$(mktemp -d -t dtk-pr-story-eval.XXXXXX)"
cleanup() {
    if [ "$KEEP" -eq 1 ]; then echo; echo "kept: $WORK"; else rm -rf "$WORK"; fi
}
trap cleanup EXIT

IDS="$(jq -r --arg only "$ONLY" '.cases[] | select($only == "" or .id == $only) | .id' "$CASES")"
[ -n "$IDS" ] || { echo "no case matches '$ONLY'" >&2; exit 2; }

run_one() { # case-id run-number
    local id="$1" n="$2" dir pr
    dir="$WORK/$id/run-$n"
    mkdir -p "$dir/data" "$dir/sandbox"
    pr="$(jq -r --arg id "$id" '.cases[] | select(.id == $id) | .pr' "$CASES")"
    # CLAUDECODE is unset so this nests cleanly when the harness runs inside Claude Code.
    (cd "$dir/sandbox" && env -u CLAUDECODE -u CLAUDE_CODE_SSE_PORT XDG_DATA_HOME="$dir/data" \
        timeout "$TIMEOUT" claude -p "/dtk:pr-story $pr" \
            --plugin-dir "$ROOT" \
            ${MODEL:+--model "$MODEL"} \
            --allowed-tools Bash Read Grep Glob Agent Write \
            --output-format stream-json --verbose \
            > "$dir/transcript.jsonl" 2> "$dir/stderr.txt")
}

echo "plugin: $ROOT"
echo "model : ${MODEL:-<session default>}"
echo "runs  : $RUNS per case | jobs: $JOBS | cases: $(echo $IDS | tr '\n' ' ')"
echo

running=0
for id in $IDS; do
    for n in $(seq 1 "$RUNS"); do
        run_one "$id" "$n" &
        running=$((running + 1))
        if [ "$running" -ge "$JOBS" ]; then
            wait -n 2>/dev/null || wait
            running=$((running - 1))
        fi
    done
done
wait

python3 -I "$GRADER" --cases "$CASES" --work "$WORK" --root "$ROOT" ${MODEL:+--model "$MODEL"} --only "$ONLY"
