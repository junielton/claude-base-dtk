---
name: debug-gh-action
effort: medium
description: "Debug a failing GitHub Actions run end-to-end: resolve the run/job (from a pasted github.com/.../actions/runs/... or .../job/... link, or from a vague mention like \"my build failed\" / \"the pipeline is red\"), fetch its logs via the GitHub CLI, root-cause it with systematic debugging rather than guessing, apply and verify a fix the way CI would run it, then confirm before committing or pushing. Trigger whenever the user shares a GitHub Actions URL, says CI/the build/the pipeline/a workflow/an action failed or is red, asks to debug or fix a failing check on a PR, or wants help figuring out why a run didn't pass — even if they don't say \"debug\" or name this skill."
argument-hint: [GitHub Actions run/job URL, or a description like "my PR's build failed"] [optional: what you suspect changed]
---

# Debug a Failing GitHub Action

CI failures are systems problems: the error message is a symptom, and the real
cause is usually a mismatch between what CI does and what a developer's machine
does (fresh checkout vs. cached state, isolated install vs. hoisted dependencies,
missing secret/service, a real code bug). Jumping straight to a patch based on the
error text alone is how you end up "fixing" the same CI job three times. Work
through the steps below in order.

## Step 1 — Resolve the failing run and job(s)

**If the user gave a URL** matching `github.com/<owner>/<repo>/actions/runs/<run_id>`
(optionally with `/job/<job_id>` and/or a `?query=string`), run:

```bash
scripts/resolve-run.sh "<url>"
```

It prints JSON with `owner`, `repo`, `run_id`, and a `jobs` array — one entry per
failing job, each with `job_id`, `name`, `failed_step`, and `log_path` (the job's
full log, already downloaded to a temp file). If the URL pointed at a specific job,
only that job is resolved; if it pointed at the whole run, every job with
`conclusion: "failure"` is resolved (or every job, if none is marked failure —
that happens when the run failed at the workflow/orchestration level rather than
inside a job).

**If the user didn't give a URL** — "the build failed", "check my last PR", "CI is
red" — you need to find the run yourself before you can use the script:
- On a PR: `gh pr checks <number-or-current-branch> --repo <owner>/<repo>` to see
  which check is failing, then open its run URL.
- On a branch with no PR yet: `gh run list --branch <branch> --status failure -L 5
  --repo <owner>/<repo>` to find the run, then `gh run view <run_id> --repo
  <owner>/<repo>` to get its URL.
- If more than one job or run could plausibly be "the" failure (multiple failing
  checks, several recent failed runs), **ask the user which one** rather than
  guessing — a wrong guess wastes a full debugging cycle on the wrong problem.

Once you have a concrete run/job URL, feed it to `scripts/resolve-run.sh` just like
the explicit case. The script needs `gh` (authenticated with access to the repo)
and `jq`; if either is missing, fall back to the manual calls it wraps —
`gh api repos/<owner>/<repo>/actions/runs/<run_id>/jobs` to list jobs and their
step conclusions, `gh api repos/<owner>/<repo>/actions/jobs/<job_id>/logs` to fetch
one job's log.

## Step 2 — Read the log, don't just skim it

Use Read (or grep) on each `log_path`, not `cat`/`head`/`tail` — these logs run to
hundreds of lines and the useful part is a specific error a good ways in. Look for
the `##[error]` marker and the step name in `failed_step` to find the right
section, then read the full error and stack trace, not just the first line — the
real cause is often a few lines below the first thing that looks like an error
(e.g. one root failure cascading into several downstream plugin errors).

If the user gave you context ("I think this is related to the Vite migration",
"we just bumped a dependency") — use it to focus where you look, but confirm it
against what the log actually shows rather than accepting it on faith. Context can
be stale or point at the wrong layer.

## Step 3 — Find the root cause

If a systematic-debugging skill is installed (e.g. `superpowers:systematic-debugging`),
invoke it before proposing any fix — don't inline your own version of that process.
Its root-cause-investigation phase is the part that's easy to skip under the
implicit time pressure of "CI is red, just fix it," and skipping it is exactly how
symptom-patches happen. If no such skill is available, run the same discipline
inline: form 2-3 concrete hypotheses for the failure, find evidence in the log/diff
that confirms or rules out each one, and only propose a fix once you can point to
the specific line/config/dependency that causes the symptom — don't patch the
first plausible-looking thing.

A few angles that are specific to CI and worth checking even when a general
debugging skill doesn't call them out by name:
- **Environment mismatch.** CI usually runs a clean checkout and a clean
  dependency install in an isolated directory. A developer's machine often has
  stale or hoisted state that masks a real gap — e.g. Node/Python resolving a
  module from a parent directory's cache, a lockfile that's out of sync with
  `package.json`/`composer.json`, or a config file nobody's touched in months that
  only gets exercised by the tool CI happens to invoke. If something "works
  locally" but fails in CI, that gap *is* the root cause, not a red herring.
- **Recent changes.** `git log`/`git diff` around the failing area, especially
  changes to build tooling, dependency manifests, or CI config itself — CI
  failures right after a migration or dependency bump are usually caused by the
  migration/bump, not coincidence.
- **Deterministic vs. flaky.** Re-running the same job (`gh run rerun
  <run_id> --repo <owner>/<repo>`) or reproducing locally tells you whether this
  reproduces every time or is timing/environment dependent. Don't build a
  deterministic fix for a flaky problem, or wave away a deterministic one as
  "probably just flaky."
- **Pre-existing vs. introduced.** Check whether the same job is also red on the
  base branch (`gh run list --branch <base> --workflow <name> -L 3`). If it's
  failing there too, this branch didn't break it — report that instead of
  patching someone else's failure into this diff. This matters most when an
  orchestrating skill (e.g. `/dtk:ship`) invoked you: a pre-existing failure is
  the caller's "stop and ask" case, not something to fix inline.

## Step 4 — Verify the fix the way CI would run it

A fix that only "works on my machine" hasn't been verified — it's just moved the
gap somewhere you can't see it. Before trusting a fix, try to reproduce CI's
isolation locally: temporarily rename/move aside cached dependency or vendor
directories (`node_modules`, `vendor`, build caches) that could be hiding the same
gap CI hit, do a clean install, and run the exact command CI runs — then restore
what you moved aside afterward. If full CI parity isn't reproducible locally
(needs a service container, a secret, a specific runner OS), say so plainly rather
than claiming confidence you don't have.

## Step 5 — Never commit or push silently

Once the fix is verified, show the user the diff and a short root-cause summary,
then ask how they want to proceed — commit and push, commit only, or leave the
change staged/unstaged for them to handle. This isn't optional caution: a push
triggers CI for everyone watching that branch/PR, and the user may want to fold
the fix into other in-progress work, review it first, or handle the commit message
themselves. Follow the repo's own git safety norms (CLAUDE.md, existing commit
conventions) for message format and scope.

**Exception — invoked from an autonomous pipeline.** When another skill running
autonomously (e.g. `/dtk:ship`'s CI gate) or a standing autonomy grant invoked this
skill, don't stop to ask: commit and push the verified fix following the caller's
conventions, state the root cause + diff summary in the report, and hand control
back so the caller's monitor loop can confirm CI goes green. The ask-first rule
above is for when the user drove this skill directly. Either way, the failure must
be *ours* — a pre-existing or flaky failure, or a fix needing a product decision,
goes back to the user/caller as a blocker, never as a silent patch.

After any push, watch the new run (`gh pr checks --watch` or `gh run watch`) and
confirm the previously failing job actually went green before calling it fixed.

## Reference

`scripts/resolve-run.sh` — see the comment header in the script for its exact
input/output contract. It only handles explicit `actions/runs/...` URLs; PR links
and vague "my build failed" requests need to be resolved to a run URL first (Step
1) before the script is useful.
