#!/usr/bin/env bash
#
# Payload eval for the review-publish skill.
#
# Runs the skill body (frontmatter stripped, via `claude -p --append-system-prompt-file`)
# against 5 fixture reports, stops at the dry run, and grades the publish-N.json the
# skill wrote. Same pattern as agents/evals/dtk-review-verifier/run.sh.
#
# Usage:
#   ./run.sh                      # current skill, 3 runs x 5 cases
#   ./run.sh --baseline           # the pre-change snapshot (baseline/SKILL.md + baseline/post-review.sh)
#   ./run.sh --runs 1 --case a,c  # a quick smoke run
#   ./run.sh --model sonnet --jobs 5 --keep
#
# Exit code is 0 only when every run passes every check.
#
# This eval never posts to GitHub. Five independent guards, any one of which is enough:
#   1. post-review.sh inside the run directory is a wrapper that always appends --dry-run,
#      and the dry-run branch exits before the only call that submits a review.
#   2. `gh` on PATH is evals/bin/gh: it answers `pr view` / `pr diff` from fixtures and
#      exits 1 on everything else.
#   3. GH_TOKEN / GITHUB_TOKEN are set to a dead value, so even a real gh could not authenticate.
#   4. The claude run gets an explicit tool allowlist and permission-mode dontAsk: no bare gh,
#      no MCP servers.
#   5. The run directory is a throwaway under mktemp, outside any git repo.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CASES="$SCRIPT_DIR/cases.json"

SKILL="$SCRIPT_DIR/../SKILL.md"
BASELINE=0
MODEL=""
ONLY=""
RUNS=3
JOBS=5
KEEP=0
TIMEOUT=900

while [ $# -gt 0 ]; do
    case "$1" in
        --baseline) BASELINE=1; SKILL="$SCRIPT_DIR/baseline/SKILL.md"; shift ;;
        --skill)    SKILL="$2"; shift 2 ;;
        --model)    MODEL="$2"; shift 2 ;;
        --case)     ONLY="$2"; shift 2 ;;
        --runs)     RUNS="$2"; shift 2 ;;
        --jobs)     JOBS="$2"; shift 2 ;;
        --timeout)  TIMEOUT="$2"; shift 2 ;;
        --keep)     KEEP=1; shift ;;
        -h|--help)  sed -n '2,32p' "$0"; exit 0 ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done

for bin in jq claude python3; do
    command -v "$bin" >/dev/null || { echo "missing dependency: $bin" >&2; exit 2; }
done
[ -f "$CASES" ] || { echo "missing $CASES" >&2; exit 2; }
[ -f "$SKILL" ] || { echo "missing skill: $SKILL" >&2; exit 2; }

WORK="$(mktemp -d -t dtk-publish-eval.XXXXXX)"
RES="$WORK/results"
mkdir -p "$RES"

cleanup() {
    if [ "$KEEP" -eq 1 ]; then
        echo; echo "kept: $WORK"
    else
        rm -rf "$WORK"
    fi
}
trap cleanup EXIT

HEAD_SHA="$(jq -r '.head_sha' "$CASES")"
BASE_BRANCH="$(jq -r '.base_branch' "$CASES")"
DIFF="$SCRIPT_DIR/$(jq -r '.diff' "$CASES")"

# Scripts the skill calls. For --baseline, the pre-change post-review.sh and no tone-lint.sh.
SCRIPTS_SRC="$WORK/scripts-src"
cp -r "$REPO_ROOT/bin/skill-scripts" "$SCRIPTS_SRC"
if [ "$BASELINE" -eq 1 ]; then
    cp "$SCRIPT_DIR/baseline/post-review.sh" "$SCRIPTS_SRC/review/post-review.sh"
    rm -f "$SCRIPTS_SRC/review/tone-lint.sh"
fi
LINT="$REPO_ROOT/bin/skill-scripts/review/tone-lint.sh"

# Skill body without the YAML frontmatter: this is what is under test.
BODY_TPL="$WORK/skill-body.md"
awk 'BEGIN{fm=0} /^---[[:space:]]*$/{fm++; next} fm>=2{print}' "$SKILL" > "$BODY_TPL"
[ -s "$BODY_TPL" ] || { echo "could not extract the skill body from $SKILL" >&2; exit 2; }

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

run_one() {
    local id="$1" k="$2" pr dir body log prompt
    pr="$(jq -r --arg i "$id" '.cases[] | select(.id == $i) | .pr' "$CASES")"
    dir="$WORK/runs/$id-$k"
    log="$dir/gh.log"
    mkdir -p "$dir/bin" "$dir/memories/reviews/PR-$pr"

    cp -r "$SCRIPTS_SRC" "$dir/bin/skill-scripts"
    cp "$SCRIPT_DIR/$(jq -r --arg i "$id" '.cases[] | select(.id == $i) | .report' "$CASES")" \
        "$dir/memories/reviews/PR-$pr/peer-review-1.md"

    # Guard 1: post-review.sh always runs as a dry run.
    mv "$dir/bin/skill-scripts/review/post-review.sh" "$dir/bin/skill-scripts/review/post-review.real.sh"
    cat > "$dir/bin/skill-scripts/review/post-review.sh" <<'WRAP'
#!/usr/bin/env bash
here="$(cd "$(dirname "$0")" && pwd)"
bash "$here/post-review.real.sh" "$@" --dry-run
rc=$?
echo "exit=$rc" >> "$here/../../../post-review.calls"
exit $rc
WRAP

    body="$dir/skill-body.md"
    sed "s/\$ARGUMENTS/$pr/g" "$BODY_TPL" > "$body"

    prompt="Publish the review for PR #$pr, following the review-publish skill in your system prompt.
This is a non-interactive run in a sandbox directory (repo acme/shop, which has no git remote here) that holds memories/reviews/PR-$pr/peer-review-1.md and bin/skill-scripts/. Step 0 is already done: SCRIPTS is bin/skill-scripts, so write that literal path in your commands (the sandbox refuses shell variables, command substitution and compound commands, so run one simple command per Bash call: no ;, &&, || or pipes). Do steps 1 to 5 only: build publish-1.json, do the voice pass, and run the dry run until it is clean. Stop there: no confirmation gate, no AskUserQuestion, no steps 6, 7 or 8. Nothing is ever posted. Finish with one line."

    # Guards 2-4: stub gh first on PATH, dead tokens, explicit allowlist, no MCP servers.
    (cd "$dir" && env -u CLAUDECODE -u CLAUDE_CODE_SSE_PORT -u GH_ENTERPRISE_TOKEN \
        PATH="$SCRIPT_DIR/bin:$PATH" \
        GH_TOKEN=eval-disabled GITHUB_TOKEN=eval-disabled \
        EVAL_GH_LOG="$log" EVAL_PR="$pr" EVAL_HEAD_SHA="$HEAD_SHA" EVAL_BASE="$BASE_BRANCH" EVAL_PR_DIFF="$DIFF" \
        timeout "$TIMEOUT" claude -p "$prompt" \
            --append-system-prompt-file "$body" \
            ${MODEL:+--model "$MODEL"} \
            --strict-mcp-config \
            --permission-mode dontAsk \
            --allowed-tools Read Write Edit Glob Grep Skill \
                "Bash(bash:*)" "Bash(gh pr view:*)" "Bash(gh pr diff:*)" "Bash(gh repo view:*)" \
                "Bash(ls:*)" "Bash(find:*)" "Bash(echo:*)" "Bash(cat:*)" "Bash(mkdir:*)" "Bash(SCRIPTS=:*)" "Bash([:*)" \
        > "$dir/claude.out" 2>&1)

    python3 -I "$SCRIPT_DIR/grade.py" --cases "$CASES" --case "$id" --run-dir "$dir" --lint "$LINT" \
        > "$RES/$id-$k.json" 2> "$RES/$id-$k.err" || true
    [ -s "$RES/$id-$k.json" ] || echo "{\"case\":\"$id\",\"pass\":false,\"checks\":{}}" > "$RES/$id-$k.json"
}

echo "skill   : $SKILL$([ "$BASELINE" -eq 1 ] && echo '  (baseline snapshot + baseline post-review.sh)')"
echo "model   : ${MODEL:-<session default>}"
echo "cases   : $(wc -w <<<"$IDS") x $RUNS runs | jobs: $JOBS"
echo

running=0
for id in $IDS; do
    for k in $(seq 1 "$RUNS"); do
        run_one "$id" "$k" &
        running=$((running + 1))
        if [ "$running" -ge "$JOBS" ]; then
            wait -n 2>/dev/null || wait
            running=$((running - 1))
        fi
    done
done
wait

# -------------------------------------------------------------------- scoring
CHECKS="payload verdict lint anchors no-leak suggestion dry-run"
printf '%-4s %-34s %-6s' "ID" "CASE" "PASS"
for c in $CHECKS; do printf ' %-10s' "$c"; done
printf '\n%s\n' "-----------------------------------------------------------------------------------------------------------------"

total=0; passed=0
for id in $IDS; do
    name="$(jq -r --arg i "$id" '.cases[] | select(.id == $i) | .name' "$CASES")"
    n=$(ls "$RES"/"$id"-*.json | wc -l)
    p=$(jq -s '[.[] | select(.pass)] | length' "$RES"/"$id"-*.json)
    total=$((total + n)); passed=$((passed + p))
    printf '%-4s %-34s %-6s' "$id" "$name" "$p/$n"
    for c in $CHECKS; do
        cell=$(jq -rs --arg c "$c" '[.[] | .checks[$c] // empty] | if length == 0 then "-" else "\([.[] | select(.pass)] | length)/\(length)" end' "$RES"/"$id"-*.json)
        printf ' %-10s' "$cell"
    done
    printf '\n'
done

echo
echo "passed $passed / $total"

api_attempts=$(cat "$WORK"/runs/*/gh.log 2>/dev/null | grep -c '^gh api' || true)
echo "gh api attempts (all refused by the stub): ${api_attempts:-0}"

[ "$KEEP" -eq 1 ] && echo "run dirs: $WORK/runs  (claude.out, gh.log, publish json inside each)"

[ "$passed" -eq "$total" ]
