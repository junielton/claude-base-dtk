#!/usr/bin/env bash
#
# Labeling eval for the review-peer skill.
#
# Materializes the dtk-review-verifier fixture into a throwaway git repo (base commit +
# change commit), hands review-peer's own analysis passes, verification rules and severity
# definitions to `claude -p` as the system prompt, asks for the report in the skill's format,
# and records which bucket (blocking / non-blocking / question) each labeled finding landed in.
#
# Usage:
#   ./run.sh                      # 5 runs, default model, skills/review-peer/SKILL.md
#   ./run.sh --runs 3             # number of independent runs
#   ./run.sh --skill <path>       # A/B another SKILL.md (e.g. a pre-edit snapshot)
#   ./run.sh --model opus         # pick the model
#   ./run.sh --jobs 1             # serialize (default 5)
#   ./run.sh --keep               # keep the temp repo, prompt and raw reports
#
# Exit code is 0 only when every run matches every expectation.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASES="$SCRIPT_DIR/cases.json"
SKILL="$SCRIPT_DIR/../SKILL.md"
WORKFLOW="$SCRIPT_DIR/../../review/references/workflow.md"
FIXTURE="$SCRIPT_DIR/../../../agents/evals/dtk-review-verifier/fixture"
GRADER="$SCRIPT_DIR/grade.py"

MODEL=""
RUNS=5
JOBS=5
KEEP=0
TIMEOUT=600

while [ $# -gt 0 ]; do
    case "$1" in
        --runs)    RUNS="$2"; shift 2 ;;
        --skill)   SKILL="$2"; shift 2 ;;
        --model)   MODEL="$2"; shift 2 ;;
        --jobs)    JOBS="$2"; shift 2 ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        --keep)    KEEP=1; shift ;;
        -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done

for bin in jq git claude python3; do
    command -v "$bin" >/dev/null || { echo "missing dependency: $bin" >&2; exit 2; }
done
[ -f "$CASES" ] || { echo "missing $CASES" >&2; exit 2; }
[ -f "$SKILL" ] || { echo "missing skill: $SKILL" >&2; exit 2; }
[ -f "$WORKFLOW" ] || { echo "missing shared workflow: $WORKFLOW" >&2; exit 2; }
[ -d "$FIXTURE/before" ] && [ -d "$FIXTURE/after" ] || { echo "missing fixture: $FIXTURE" >&2; exit 2; }

WORK="$(mktemp -d -t dtk-review-peer-eval.XXXXXX)"
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

# ------------------------------------------------------------------- prompt
# What is tested is the skill's own text: step 4 (analysis passes), step 8 (verification
# rules, where the severity hint lives), the report format of step 9 and the severity
# definitions. The GitHub-collection step (3) is replaced by a local `git diff`; memory,
# lessons and publishing are out of scope.
# Steps 4 and 8 point into the shared review workflow (skills/review/references/workflow.md);
# its Analyze and Verify Findings sections are appended after them, unless the skill under
# test still carries the passes inline (a pre-extraction snapshot passed with --skill).
section() { # section <start-regex> <stop-regex> [file]
    awk -v s="$1" -v e="$2" '$0 ~ s {on=1} on && $0 ~ e {exit} on {print}' "${3:-$SKILL}"
}
INLINE=0
grep -q 'Pass 1 — Map Changes' "$SKILL" && INLINE=1
template() {
    awk '/^# Peer Review — /{on=1} /^\*\*Reconciliation/{on=0} on{l[n++]=$0}
         END{while(n>0 && (l[n-1]=="" || l[n-1]=="```")) n--; for(i=0;i<n;i++) print l[i]}' "$SKILL"
}

PROMPT="$WORK/system-prompt.md"
{
    cat <<'HDR'
You are executing the review-peer skill against a local branch instead of a GitHub PR.
The workflow steps below are the skill's own. Step 3 (GitHub collection) is replaced by:
`git diff main...feature/orders-invoices` — its output is in the user message (the nested
session cannot reliably run git itself); read any file you need for context.
There are no existing review comments, no lessons, and no memory state; skip steps 1-2, 5-7
and 10-11. The dtk-review-verifier subagent is not available in this run: do not dispatch it.
Write the report as it would read once step 8 is done, and print it as your final answer
(do not save it to a file).

HDR
    section '^### 4[.] ' '^### 5[.] '
    echo
    [ "$INLINE" -eq 1 ] || { section '^## Analyze' '^## Memory' "$WORKFLOW"; echo; }
    section '^### 8[.] ' '^### 9[.] '
    echo
    [ "$INLINE" -eq 1 ] || { section '^## Verify Findings' '^## Reconciliation' "$WORKFLOW"; echo; }
    section '^## Severity Definitions' '^## Common'
    echo
    echo "### Report format"
    echo
    template
} | sed 's/PR #\$ARGUMENTS/feature\/orders-invoices/g; s/PR-\$ARGUMENTS/feature-orders-invoices/g; s/<scope>/feature\/orders-invoices/g' > "$PROMPT"
[ -s "$PROMPT" ] || { echo "could not build prompt from $SKILL" >&2; exit 2; }

# --------------------------------------------------------------- fixture repo
BASE_BRANCH="$(jq -r '.fixture.base_branch' "$CASES")"
HEAD_BRANCH="$(jq -r '.fixture.head_branch' "$CASES")"

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

# ------------------------------------------------------------------ run
# The diff is collected here, not by the model: a nested `claude -p` can have its Bash git
# calls denied (hooks that rewrite commands defeat the allowlist), and a reviewer that falls
# back to reading whole files is no longer reviewing a diff.
DIFF="$(cd "$REPO" && git diff "$BASE_BRANCH...$HEAD_BRANCH")"
[ -n "$DIFF" ] || { echo "empty diff" >&2; exit 2; }
USER_PROMPT="Review the local branch $HEAD_BRANCH against $BASE_BRANCH. Follow the workflow in your instructions and output the review report. Output of \`git diff $BASE_BRANCH...$HEAD_BRANCH\`:

$DIFF"

run_one() {
    local n="$1" raw
    # CLAUDECODE is unset so this nests cleanly when the harness itself runs inside Claude Code.
    raw="$(cd "$REPO" && env -u CLAUDECODE -u CLAUDE_CODE_SSE_PORT \
        timeout "$TIMEOUT" claude -p "$USER_PROMPT" \
            --append-system-prompt-file "$PROMPT" \
            ${MODEL:+--model "$MODEL"} \
            --allowed-tools Read Grep Glob \
                "Bash(git diff:*)" "Bash(git log:*)" "Bash(git show:*)" "Bash(git status:*)" \
            2>&1)"
    printf '%s\n' "$raw" > "$OUT/run-$n.md"
}

echo "skill   : $SKILL"
if grep -qF 'Send the severity you actually intend to post' "$SKILL"; then
    echo "hint    : PRESENT (step-8 severity sentence)"
else
    echo "hint    : absent"
fi
echo "model   : ${MODEL:-<session default>}"
echo "fixture : $REPO ($HEAD_BRANCH vs $BASE_BRANCH)"
echo "runs    : $RUNS | jobs: $JOBS"
echo

running=0
for n in $(seq 1 "$RUNS"); do
    run_one "$n" &
    running=$((running + 1))
    if [ "$running" -ge "$JOBS" ]; then
        wait -n 2>/dev/null || wait
        running=$((running - 1))
    fi
done
wait

# ------------------------------------------------------------------ grading
python3 -I "$GRADER" --cases "$CASES" --dir "$OUT" --runs "$RUNS"
status=$?

if [ "$KEEP" -eq 1 ]; then
    echo "raw reports: $OUT"
fi
exit "$status"
