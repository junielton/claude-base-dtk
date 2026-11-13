#!/usr/bin/env bash
#
# Eval harness for the claim-verifier agent: does it return the right verdict AND the right
# `Basis` for claims about a public pull request?
#
# Sends the claims in cases.json, with a `Context:` block (repo, ref, clone: no), to
# `claude -p` with the agent's own instructions as the system prompt, in an empty directory
# (no clone, so every read goes through `gh`). grade.py compares each `### <id>:` block to
# the labels. The claims are about merged PR junielton/claude-base-dtk#28, so the run needs
# `gh` signed in and network access.
#
# Docs: README.markdown next to this script (not README.md: every *.md under agents/ loads
# as an agent definition).
#
# Usage:
#   ./run.sh                  # 3 runs, on the agent's frontmatter model
#   ./run.sh --runs 1         # number of independent runs (each one costs tokens)
#   ./run.sh --model opus     # override the model
#   ./run.sh --jobs 1         # parallel runs (default 1; keep it under half the cores)
#   ./run.sh --keep           # keep the raw outputs
#
# Exit code is 0 only when every run matches every label.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASES="$SCRIPT_DIR/cases.json"
AGENT="$SCRIPT_DIR/../../claim-verifier.md"
GRADER="$SCRIPT_DIR/grade.py"

MODEL=""
RUNS=3
JOBS=1
KEEP=0
TIMEOUT=600

while [ $# -gt 0 ]; do
    case "$1" in
        --runs)    RUNS="$2"; shift 2 ;;
        --model)   MODEL="$2"; shift 2 ;;
        --jobs)    JOBS="$2"; shift 2 ;;
        --agent)   AGENT="$2"; shift 2 ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        --keep)    KEEP=1; shift ;;
        -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done

for bin in jq claude python3 gh; do
    command -v "$bin" >/dev/null || { echo "missing dependency: $bin" >&2; exit 2; }
done
[ -f "$CASES" ] || { echo "missing $CASES" >&2; exit 2; }
[ -f "$AGENT" ] || { echo "missing agent definition: $AGENT" >&2; exit 2; }
gh auth status >/dev/null 2>&1 || { echo "gh is not signed in (gh auth login)" >&2; exit 2; }

# Default to the model the agent pins, so the eval measures what the skills dispatch.
if [ -z "$MODEL" ]; then
    MODEL="$(awk '/^---[[:space:]]*$/{fm++; next} fm==1 && /^model:/{sub(/^model:[[:space:]]*/, ""); sub(/[[:space:]]*#.*/, ""); print; exit}' "$AGENT")"
    [ "$MODEL" = "inherit" ] && MODEL=""
fi

WORK="$(mktemp -d -t dtk-claim-verifier-eval.XXXXXX)"
OUT="$WORK/out"
SANDBOX="$WORK/sandbox"
mkdir -p "$OUT" "$SANDBOX"

cleanup() {
    if [ "$KEEP" -eq 1 ]; then
        echo
        echo "kept: $WORK"
    else
        rm -rf "$WORK"
    fi
}
trap cleanup EXIT

# The agent's instructions minus the YAML frontmatter: this is what we are testing.
BODY="$WORK/agent-body.md"
awk 'BEGIN{fm=0} /^---[[:space:]]*$/{fm++; next} fm>=2{print}' "$AGENT" > "$BODY"
[ -s "$BODY" ] || { echo "could not extract agent body from $AGENT" >&2; exit 2; }

# The same shape the skills dispatch: a claim batch plus the optional Context block.
PAYLOAD="$WORK/payload.md"
{
    echo "Verify this batch of claims."
    echo
    echo "Context:"
    echo "repo: $(jq -r '.context.repo' "$CASES")"
    echo "ref: $(jq -r '.context.ref' "$CASES")"
    echo "clone: $(jq -r '.context.clone' "$CASES")"
    echo
    jq -r '.cases[] | "id: \(.id)\nclaim: \(.claim)\nhints: \(.hints)\n"' "$CASES"
} > "$PAYLOAD"

run_one() {
    local n="$1"
    # CLAUDECODE is unset so this nests cleanly when the harness runs inside Claude Code.
    (cd "$SANDBOX" && env -u CLAUDECODE -u CLAUDE_CODE_SSE_PORT \
        timeout "$TIMEOUT" claude -p "$(cat "$PAYLOAD")" \
            --append-system-prompt-file "$BODY" \
            ${MODEL:+--model "$MODEL"} \
            --allowed-tools Read Grep Glob "Bash(gh:*)" "Bash(git:*)" "Bash(jq:*)" "Bash(base64:*)" \
            > "$OUT/run-$n.md" 2>&1)
}

echo "agent : $AGENT"
echo "model : ${MODEL:-<session default>}"
echo "runs  : $RUNS | jobs: $JOBS | cases: $(jq '.cases | length' "$CASES")"
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

python3 -I "$GRADER" --cases "$CASES" --out "$OUT"
