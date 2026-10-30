#!/usr/bin/env bash
#
# Stand-in for `gh` used by the ship eval. Never talks to GitHub.
#
# State lives in $GH_STUB_STATE (a per-run directory): every call is appended to gh.log, and
# `gh pr create` drops a `pr` marker so later `gh pr view|list|checks` behave as if the PR exists.
# $GH_STUB_CI selects what `gh pr checks` reports: "green" (default) or "red" (one failing shard).

STATE="${GH_STUB_STATE:?GH_STUB_STATE not set}"
mkdir -p "$STATE"
printf '%s\n' "gh $*" >> "$STATE/gh.log"

URL="https://github.com/acme/demo/pull/7"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo feature)"
SHA="$(git rev-parse HEAD 2>/dev/null || echo 0000000)"

# --jq / -q <expr> support, so `gh pr view --json x -q .x` behaves.
JQ=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
    case "${args[$i]}" in
        -q|--jq) JQ="${args[$((i + 1))]}" ;;
    esac
done
emit() { # emit <json>
    if [ -n "$JQ" ]; then printf '%s' "$1" | jq -r "$JQ"; else printf '%s\n' "$1"; fi
}

pr_json() {
    cat <<JSON
{"number":7,"url":"$URL","state":"OPEN","isDraft":false,"title":"Demo change (T1)","body":"stub",
 "baseRefName":"main","headRefName":"$BRANCH","headRefOid":"$SHA","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN",
 "reviews":[],"reviewRequests":[],"comments":[],"latestReviews":[],
 "statusCheckRollup":[{"name":"test (1)","status":"COMPLETED","conclusion":"$([ "${GH_STUB_CI:-green}" = red ] && echo FAILURE || echo SUCCESS)"},
                      {"name":"build","status":"COMPLETED","conclusion":"SUCCESS"}]}
JSON
}

sub="$1 ${2:-}"
case "$sub" in
    "pr create")
        touch "$STATE/pr"
        echo "$URL"
        ;;
    "pr view")
        if [ -f "$STATE/pr" ]; then emit "$(pr_json)"; else
            echo "no pull requests found for branch \"$BRANCH\"" >&2; exit 1
        fi
        ;;
    "pr list")
        if [ -f "$STATE/pr" ]; then emit "[$(pr_json)]"; else emit "[]"; fi
        ;;
    "pr checks")
        if [ ! -f "$STATE/pr" ]; then echo "no pull requests found for branch \"$BRANCH\"" >&2; exit 1; fi
        if [ "${GH_STUB_CI:-green}" = red ]; then
            printf 'test (1)\tfail\t3m35s\thttps://github.com/acme/demo/actions/runs/1/job/11\n'
            printf 'coverage\tskipping\t0\thttps://github.com/acme/demo/actions/runs/1/job/12\n'
            printf 'build\tpass\t1m30s\thttps://github.com/acme/demo/actions/runs/1/job/13\n'
            exit 1
        fi
        printf 'test (1)\tpass\t3m10s\thttps://github.com/acme/demo/actions/runs/1/job/11\n'
        printf 'build\tpass\t1m30s\thttps://github.com/acme/demo/actions/runs/1/job/13\n'
        ;;
    "pr edit"|"pr ready"|"pr comment"|"pr review")
        echo "$URL"
        ;;
    "run view")
        printf 'test (1)\tTest (shard 1/4)\t2026-10-27T18:44:35Z FAIL src/gc.test.ts > worktree:remove drops the subfolder rows too\n'
        printf 'test (1)\tTest (shard 1/4)\t2026-10-27T18:44:35Z Error: Test timed out in 5000ms.\n'
        ;;
    "run list")
        emit '[{"databaseId":1,"status":"completed","conclusion":"failure","headSha":"'"$SHA"'","name":"CI"}]'
        ;;
    "api "*)
        case "$*" in
            *requested_reviewers*)
                echo 'gh: Reviews may only be requested from collaborators (HTTP 422)' >&2; exit 1 ;;
            *) echo '{}' ;;
        esac
        ;;
    "repo view")
        emit '{"nameWithOwner":"acme/demo","name":"demo","owner":{"login":"acme"},"url":"https://github.com/acme/demo","defaultBranchRef":{"name":"main"}}'
        ;;
    "auth status")
        echo "Logged in to github.com as eval-user" ;;
    *)
        echo '{}' ;;
esac
