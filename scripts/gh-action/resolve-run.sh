#!/usr/bin/env bash
# Resolve a GitHub Actions run/job URL to its failing job(s) and download each job's logs.
#
# Usage: resolve-run.sh <github-actions-run-or-job-url>
#   URL forms accepted (query strings like ?pr=123 are ignored):
#     https://github.com/<owner>/<repo>/actions/runs/<run_id>
#     https://github.com/<owner>/<repo>/actions/runs/<run_id>/job/<job_id>
#
# Prints JSON to stdout:
#   {
#     "owner": "...", "repo": "...", "run_id": 123,
#     "jobs": [
#       { "job_id": 456, "name": "...", "conclusion": "failure",
#         "failed_step": "Build career-search", "log_path": "/tmp/.../job-456.log" }
#     ]
#   }
#
# If the URL points at a specific job, only that job is resolved. If it points at a
# whole run, every job with at least one failed step is resolved. This checks step-level
# conclusions rather than the job's own conclusion because many workflows cancel sibling
# jobs once one fails (e.g. via an explicit cancel-workflow action) — those siblings end
# up with job conclusion "cancelled" even though they never actually failed, while the
# job that triggered the cancellation shows its real failure at the step level. Falls
# back to job-level "failure" conclusions, then to all jobs, only if no step-level
# failure is found anywhere (e.g. the run failed at the workflow/orchestration level).
#
# Requires: gh (authenticated with access to the repo), jq.
# This script only handles explicit actions/runs URLs. PR links or vague references
# ("my last build failed") need to be resolved to a run URL first — see SKILL.md.

set -euo pipefail

url="${1:?Usage: resolve-run.sh <github-actions-run-or-job-url>}"
clean_url="${url%%\?*}"

if [[ "$clean_url" =~ github\.com/([^/]+)/([^/]+)/actions/runs/([0-9]+)(/job/([0-9]+))? ]]; then
  owner="${BASH_REMATCH[1]}"
  repo="${BASH_REMATCH[2]}"
  run_id="${BASH_REMATCH[3]}"
  job_id="${BASH_REMATCH[5]:-}"
else
  echo "error: could not parse a GitHub Actions run/job URL from: $url" >&2
  echo "expected form: https://github.com/<owner>/<repo>/actions/runs/<run_id>[/job/<job_id>]" >&2
  exit 1
fi

repo_slug="$owner/$repo"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/debug-gh-action.XXXXXX")"

if [[ -n "$job_id" ]]; then
  jobs_json="$(gh api "repos/$repo_slug/actions/jobs/$job_id" | jq '[.]')"
else
  all_jobs="$(gh api "repos/$repo_slug/actions/runs/$run_id/jobs" --jq '.jobs')"
  jobs_json="$(echo "$all_jobs" | jq '[.[] | select([.steps[]? | select(.conclusion=="failure")] | length > 0)]')"
  if [[ "$(echo "$jobs_json" | jq 'length')" == "0" ]]; then
    jobs_json="$(echo "$all_jobs" | jq '[.[] | select(.conclusion=="failure")]')"
  fi
  if [[ "$(echo "$jobs_json" | jq 'length')" == "0" ]]; then
    jobs_json="$all_jobs"
  fi
fi

echo "$jobs_json" | jq -r '.[].id' | while read -r jid; do
  gh api "repos/$repo_slug/actions/jobs/$jid/logs" > "$tmp_dir/job-$jid.log" 2>/dev/null || \
    echo "warning: could not fetch logs for job $jid" >&2
done

echo "$jobs_json" | jq --arg owner "$owner" --arg repo "$repo" --arg run_id "$run_id" --arg tmp_dir "$tmp_dir" '{
  owner: $owner,
  repo: $repo,
  run_id: ($run_id | tonumber),
  jobs: [ .[] | {
    job_id: .id,
    name: .name,
    conclusion: .conclusion,
    failed_step: ([.steps[]? | select(.conclusion=="failure") | .name][0] // null),
    log_path: ($tmp_dir + "/job-" + (.id | tostring) + ".log")
  } ]
}'
