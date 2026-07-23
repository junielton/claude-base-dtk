#!/usr/bin/env bash
#
# Eval harness for the dtk-review-verifier agent.
#
# Materializes the Laravel fixture into a throwaway git repo (base commit + change
# commit), runs the agent's own instructions against each labeled finding, and
# compares the returned verdict to the expected one.
#
# Usage:
#   ./run.sh                      # all cases, default model
#   ./run.sh --model opus         # pick the model
#   ./run.sh --case 4,6           # only these case ids
#   ./run.sh --jobs 1             # serialize (default 4)
#   ./run.sh --keep               # keep the temp repo and raw outputs for inspection
#
# Exit code is 0 only when every case matches its label.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASES="$SCRIPT_DIR/cases.json"
FIXTURE="$SCRIPT_DIR/fixture"
AGENT="$SCRIPT_DIR/../../dtk-review-verifier.md"

MODEL=""
ONLY=""
JOBS=4
KEEP=0
TIMEOUT=240

while [ $# -gt 0 ]; do
    case "$1" in
        --model)   MODEL="$2"; shift 2 ;;
        --case)    ONLY="$2"; shift 2 ;;
        --jobs)    JOBS="$2"; shift 2 ;;
        --agent)   AGENT="$2"; shift 2 ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        --keep)    KEEP=1; shift ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done

for bin in jq git claude; do
    command -v "$bin" >/dev/null || { echo "missing dependency: $bin" >&2; exit 2; }
done
[ -f "$CASES" ] || { echo "missing $CASES" >&2; exit 2; }
[ -f "$AGENT" ] || { echo "missing agent definition: $AGENT" >&2; exit 2; }

WORK="$(mktemp -d -t dtk-verifier-eval.XXXXXX)"
REPO="$WORK/repo"
OUT="$WORK/out"
mkdir -p "$REPO" "$OUT"

cleanup() {
    if [ "$KEEP" -eq 1 ]; then
        echo
        echo "kept: $WORK"
    else
        rm -rf "$WORK"
    fi
}
trap cleanup EXIT

# ---------------------------------------------------------------- agent body
# The agent's instructions minus the YAML frontmatter — this is what we are testing.
BODY="$WORK/agent-body.md"
awk 'BEGIN{fm=0} /^---[[:space:]]*$/{fm++; next} fm>=2{print}' "$AGENT" > "$BODY"
[ -s "$BODY" ] || { echo "could not extract agent body from $AGENT" >&2; exit 2; }

# --------------------------------------------------------------- fixture repo
BASE_BRANCH="$(jq -r '.fixture.base_branch' "$CASES")"
HEAD_BRANCH="$(jq -r '.fixture.head_branch' "$CASES")"
SCOPE="$(jq -r '.fixture.scope' "$CASES")"

build_repo() {
    cd "$REPO" || exit 2
    git init -q -b "$BASE_BRANCH"
    git config user.email "eval@dtk.local"
    git config user.name "dtk eval"
    git config commit.gpgsign false

    cp -r "$FIXTURE/before/." .
    git add -A
    git commit -qm "baseline: orders, legacy report, money helper, event router"

    git checkout -q -b "$HEAD_BRANCH"
    git rm -rq --cached . >/dev/null
    find . -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
    cp -r "$FIXTURE/after/." .
    git add -A
    git commit -qm "feat: order listing, invoice endpoints, user search"
}

build_repo || { echo "failed to build fixture repo" >&2; exit 2; }

# ------------------------------------------------------------------ run cases
IDS="$(jq -r '.cases[].id' "$CASES")"
if [ -n "$ONLY" ]; then
    WANT=",${ONLY//[[:space:]]/},"
    FILTERED=""
    for id in $IDS; do
        case "$WANT" in *",$id,"*) FILTERED="$FILTERED $id" ;; esac
    done
    IDS="$FILTERED"
fi
[ -n "${IDS// /}" ] || { echo "no cases selected" >&2; exit 2; }

run_case() {
    local id="$1"
    local c severity location claim reasoning payload raw verdict suggested

    c="$(jq -c --argjson i "$id" '.cases[] | select(.id == $i)' "$CASES")"
    severity="$(jq -r '.severity' <<<"$c")"
    location="$(jq -r '.location' <<<"$c")"
    claim="$(jq -r '.claim' <<<"$c")"
    reasoning="$(jq -r '.reasoning' <<<"$c")"

    payload="Verify this single code-review finding.

severity:  $severity
location:  $location
claim:     $claim
reasoning: $reasoning
scope:     $SCOPE"

    # CLAUDECODE is unset so this nests cleanly when the harness itself runs inside Claude Code.
    raw="$(cd "$REPO" && env -u CLAUDECODE -u CLAUDE_CODE_SSE_PORT \
        timeout "$TIMEOUT" claude -p "$payload" \
            --append-system-prompt-file "$BODY" \
            ${MODEL:+--model "$MODEL"} \
            --allowed-tools Read Grep Glob \
                "Bash(git diff:*)" "Bash(git log:*)" "Bash(git show:*)" "Bash(git status:*)" \
            2>&1)"

    printf '%s\n' "$raw" > "$OUT/case-$id.txt"

    verdict="$(grep -oiE 'verdict:[[:space:]]*(real|refuted)' <<<"$raw" | head -1 \
        | sed -E 's/.*:[[:space:]]*//' | tr '[:upper:]' '[:lower:]')"
    suggested="$(grep -oiE 'suggested-severity:[[:space:]]*(blocking|non-blocking|question)' <<<"$raw" \
        | head -1 | sed -E 's/.*:[[:space:]]*//' | tr '[:upper:]' '[:lower:]')"

    printf '%s\t%s\t%s\n' "$id" "${verdict:-PARSE_ERROR}" "${suggested:-}" > "$OUT/case-$id.tsv"
}

echo "agent   : $AGENT"
echo "model   : ${MODEL:-<session default>}"
echo "fixture : $REPO ($HEAD_BRANCH vs $BASE_BRANCH)"
echo "cases   : $(wc -w <<<"$IDS") | jobs: $JOBS"
echo

running=0
for id in $IDS; do
    run_case "$id" &
    running=$((running + 1))
    if [ "$running" -ge "$JOBS" ]; then
        wait -n 2>/dev/null || wait
        running=$((running - 1))
    fi
done
wait

# -------------------------------------------------------------------- scoring
pass=0; fail=0
printf '%-4s %-46s %-9s %-9s %s\n' "ID" "CASE" "EXPECT" "GOT" "RESULT"
printf '%s\n' "--------------------------------------------------------------------------------------"

for id in $IDS; do
    c="$(jq -c --argjson i "$id" '.cases[] | select(.id == $i)' "$CASES")"
    name="$(jq -r '.name' <<<"$c")"
    expect="$(jq -r '.expect' <<<"$c")"
    want_sev="$(jq -r '.expect_suggested_severity // ""' <<<"$c")"

    if [ -f "$OUT/case-$id.tsv" ]; then
        IFS=$'\t' read -r _ got got_sev < "$OUT/case-$id.tsv"
    else
        got="NO_OUTPUT"; got_sev=""
    fi

    result="PASS"
    if [ "$got" != "$expect" ]; then
        result="FAIL"
    elif [ -n "$want_sev" ] && [ "$got_sev" != "$want_sev" ]; then
        result="FAIL (severity: wanted $want_sev, got ${got_sev:-none})"
    fi

    [ "${result:0:4}" = "PASS" ] && pass=$((pass + 1)) || fail=$((fail + 1))
    printf '%-4s %-46s %-9s %-9s %s\n' "$id" "$name" "$expect" "$got" "$result"
done

echo
echo "passed $pass / $((pass + fail))"

# The asymmetry that matters: a false negative (a real finding refuted) silently
# deletes review value, so report it separately from over-eager keeps.
fn=0; fp=0
for id in $IDS; do
    c="$(jq -c --argjson i "$id" '.cases[] | select(.id == $i)' "$CASES")"
    expect="$(jq -r '.expect' <<<"$c")"
    [ -f "$OUT/case-$id.tsv" ] && IFS=$'\t' read -r _ got _ < "$OUT/case-$id.tsv" || got="NO_OUTPUT"
    [ "$expect" = "real" ] && [ "$got" = "refuted" ] && fn=$((fn + 1))
    [ "$expect" = "refuted" ] && [ "$got" = "real" ] && fp=$((fp + 1))
done
echo "over-pruning (real wrongly refuted) : $fn"
echo "under-pruning (false positive kept) : $fp"

if [ "$KEEP" -eq 1 ]; then
    echo "raw agent output: $OUT"
fi

[ "$fail" -eq 0 ]
