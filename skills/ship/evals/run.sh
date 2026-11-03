#!/usr/bin/env bash
#
# Delegation eval for the ship skill.
#
# Question: when ship is invoked (alone or from a dispatcher with an override list), does the
# agent call the skills each step names (review-local, smart-commit, create-pr, debug-gh-action,
# report-back) through the Skill tool, or does it do that work inline?
#
# How: the skill under test is loaded as a REAL skill inside a throwaway plugin named `dtk`,
# next to stub skills with the names it chains (each stub just replies; create-pr and
# smart-commit stubs run the one git/gh command the real skill would). `claude -p` runs in a
# throwaway git repo with a local bare `origin` and a stub `gh` first on PATH, isolated from the
# user's settings, plugins, hooks and personal skills (--setting-sources project). The graded
# evidence is the tool-call trace (stream-json), not the prose.
#
# Usage:
#   ./run.sh                          # 3 runs per case, Sonnet, against ../SKILL.md
#   ./run.sh --skill <path>           # A/B another ship (e.g. a pre-edit snapshot)
#   ./run.sh --case dispatched        # only cases whose name matches the regex
#   ./run.sh --runs 5 --jobs 4        # samples per case / parallel runs
#   ./run.sh --model opus             # another model (default: sonnet; `--model default` = session default)
#   ./run.sh --keep                   # keep sandboxes, traces and stderr
#
# Needs jq, git, python3 and claude on PATH. Exit 0 only if every valid run meets every expectation.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASES="$SCRIPT_DIR/cases.json"
GRADER="$SCRIPT_DIR/grade.py"
GH_STUB="$SCRIPT_DIR/gh-stub.sh"
SKILL="$SCRIPT_DIR/../SKILL.md"

MODEL="sonnet"; RUNS=3; JOBS=4; KEEP=0; TIMEOUT=900; ONLY=""

while [ $# -gt 0 ]; do
    case "$1" in
        --runs)    RUNS="$2"; shift 2 ;;
        --jobs)    JOBS="$2"; shift 2 ;;
        --skill)   SKILL="$2"; shift 2 ;;
        --case)    ONLY="$2"; shift 2 ;;
        --model)   MODEL="$2"; [ "$MODEL" = default ] && MODEL=""; shift 2 ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        --keep)    KEEP=1; shift ;;
        -h|--help) sed -n '2,29p' "$0"; exit 0 ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done

for bin in jq git claude python3 timeout; do
    command -v "$bin" >/dev/null || { echo "missing dependency: $bin" >&2; exit 2; }
done
for f in "$CASES" "$GRADER" "$GH_STUB" "$SKILL"; do
    [ -f "$f" ] || { echo "missing $f" >&2; exit 2; }
done
SKILL="$(cd "$(dirname "$SKILL")" && pwd)/$(basename "$SKILL")"

WORK="$(mktemp -d -t dtk-ship-eval.XXXXXX)"
PLUG="$WORK/plug"; BIN="$WORK/bin"; OUT="$WORK/out"; SB="$WORK/sandboxes"
mkdir -p "$PLUG/.claude-plugin" "$PLUG/skills" "$BIN" "$OUT" "$SB"

cleanup() {
    if [ "$KEEP" -eq 1 ]; then echo; echo "kept: $WORK"; else rm -rf "$WORK"; fi
}
trap cleanup EXIT

# ------------------------------------------------------------------ plugin
echo '{"name":"dtk","version":"0.0.0","description":"ship eval stubs + skill under test"}' > "$PLUG/.claude-plugin/plugin.json"

for name in $(jq -r '.stubbed_skills[]' "$CASES"); do
    mkdir -p "$PLUG/skills/$name"
    case "$name" in
        create-pr)
            action="Run exactly: gh pr create --base main --title 'Demo change (T1)' --body 'stub body'. Then reply with the PR URL it printed and nothing else." ;;
        smart-commit)
            action="Run exactly: git add -A && git commit -q -m 'feat: demo change' && git push -q -u origin HEAD. Then reply: smart-commit: committed and pushed. Nothing else." ;;
        debug-gh-action)
            action="Reply exactly: debug-gh-action: root cause is a 5s test timeout, pre-existing and flaky, nothing to fix; stop at the red gate. Run no commands." ;;
        *)
            action="Reply exactly: $name: done, 0 findings. Run no commands." ;;
    esac
    cat > "$PLUG/skills/$name/SKILL.md" <<STUB
---
name: $name
description: Eval stub for $name. Use when a workflow calls for $name.
---
EVAL STUB. $action
STUB
done

mkdir -p "$PLUG/skills/ship"
cp "$SKILL" "$PLUG/skills/ship/SKILL.md"
[ -f "$(dirname "$SKILL")/LESSONS.md" ] && cp "$(dirname "$SKILL")/LESSONS.md" "$PLUG/skills/ship/LESSONS.md"

# gh + notifiers: never touch GitHub, never make a sound.
cp "$GH_STUB" "$BIN/gh"; chmod +x "$BIN/gh"
for n in speak-notify speak say spd-say notify-send; do
    printf '#!/usr/bin/env bash\necho "%s $*" >> "${GH_STUB_STATE:-/tmp}/notify.log"\n' "$n" > "$BIN/$n"
    chmod +x "$BIN/$n"
done

# ------------------------------------------------------------------ sandbox repo
BASE_BRANCH="$(jq -r '.fixture.base_branch' "$CASES")"
HEAD_BRANCH="$(jq -r '.fixture.head_branch' "$CASES")"

build_sandbox() { # build_sandbox <dir> <committed|uncommitted>
    local d="$1" state="$2"
    mkdir -p "$d/repo" "$d/state"
    git init -q --bare -b "$BASE_BRANCH" "$d/origin.git"
    cd "$d/repo" || return 1
    git init -q -b "$BASE_BRANCH"
    git config user.email "eval@dtk.local"; git config user.name "dtk eval"; git config commit.gpgsign false
    git remote add origin https://github.com/acme/demo.git
    git config "url.$d/origin.git.insteadOf" "https://github.com/acme/demo.git"

    mkdir -p src .github
    printf 'module.exports = (name) => "Hello, " + name;\n' > src/greet.js
    printf '# Changelog\n\n## Unreleased\n' > CHANGELOG.md
    printf '# Contributing\n\nPR titles read `<Human-readable title> (<ID>)`. Say what changed and why.\nLink the related task in the description.\n' > CONTRIBUTING.md
    printf '## Summary\n\n## Related task\n\n## Testing\n' > .github/PULL_REQUEST_TEMPLATE.md
    git add -A && git commit -qm "chore: baseline" && git push -q -u origin "$BASE_BRANCH"

    git checkout -q -b "$HEAD_BRANCH"
    printf 'module.exports = (name) => `Hello, ${name}!`;\n' > src/greet.js
    printf '# Changelog\n\n## Unreleased\n\n- Greeting now ends with an exclamation mark.\n' > CHANGELOG.md
    if [ "$state" = committed ]; then
        git add -A && git commit -qm "feat: exclamation mark in greeting" && git push -q -u origin "$HEAD_BRANCH"
    fi
}

run_one() { # run_one <case-json> <n>
    local cj="$1" n="$2" name state ci prompt d
    name="$(jq -r '.name' <<<"$cj")"; state="$(jq -r '.state' <<<"$cj")"
    ci="$(jq -r '.ci' <<<"$cj")";     prompt="$(jq -r '.prompt' <<<"$cj")"
    d="$SB/$name-$n"
    ( build_sandbox "$d" "$state" ) >/dev/null 2>"$OUT/$name-$n.build.err" \
        || { echo "sandbox build failed for $name-$n" >&2; return; }
    ( cd "$d/repo" && env -u CLAUDECODE -u CLAUDE_CODE_SSE_PORT \
        PATH="$BIN:$PATH" GH_STUB_STATE="$d/state" GH_STUB_CI="$ci" \
        timeout "$TIMEOUT" claude -p "$prompt" \
            --output-format stream-json --verbose --no-session-persistence \
            --setting-sources project --plugin-dir "$PLUG" \
            ${MODEL:+--model "$MODEL"} \
            --allowed-tools Skill Read Grep Glob Bash Write Edit \
        </dev/null >"$OUT/$name-$n.jsonl" 2>"$OUT/$name-$n.err" )
}

echo "skill    : $SKILL"
if grep -q 'Delegation contract' "$SKILL"; then echo "contract : PRESENT"; else echo "contract : absent"; fi
echo "model    : ${MODEL:-<session default>}"
echo "runs     : $RUNS per case | jobs: $JOBS | timeout: ${TIMEOUT}s"

running=0
while IFS= read -r cj; do
    for n in $(seq 1 "$RUNS"); do
        run_one "$cj" "$n" &
        running=$((running + 1))
        if [ "$running" -ge "$JOBS" ]; then wait -n 2>/dev/null || wait; running=$((running - 1)); fi
    done
done < <(jq -c --arg re "$ONLY" '.cases[] | select(.name | test($re))' "$CASES")
wait

python3 -I "$GRADER" --cases "$CASES" --dir "$OUT" --runs "$RUNS" --only "$ONLY"
status=$?
[ "$KEEP" -eq 1 ] && echo "traces: $OUT"
exit "$status"
