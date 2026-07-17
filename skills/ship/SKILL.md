---
name: ship
description: "Use to run the full PR lifecycle in one go instead of hand-chaining review-local → smart-commit → open the PR → assign reviewers → monitor CI + reviewers → resolve → reply. Triggers on 'ship this', 'ship isso', 'open the PR and monitor it', 'run the PR pipeline', 'faz o fluxo completo de PR', or when the user lists that same sequence of steps by hand. Safe to re-run mid-pipeline: it detects what's already committed/open and resumes instead of redoing it. It chains the other dtk skills (review-local, smart-commit, create-pr, review) with sane defaults. Do NOT use for a plain commit (smart-commit), just opening a PR with no follow-through (create-pr), or landing many branches at once."
---

# Ship (PR lifecycle)

Runs the end-to-end "get this change into a reviewed PR" pipeline that you
otherwise type out step by step every time. It **orchestrates** the other dtk
skills — it doesn't reimplement them.

Default behavior is **autonomous**: run the whole chain, stop only on a genuine
ambiguity or a red gate (failing tests, merge conflict, a blocking reviewer
change request you can't resolve safely). Announce the plan in one line, then
execute.

Nothing here is project-specific: reviewers come from the repo's own CODEOWNERS,
the base branch and PR conventions are discovered at runtime, and the notifier is
auto-detected. It works in any repo with `git` + `gh`.

## The pipeline

1. **Review own diff** → run `/dtk:review-local` on the changes; apply the safe
   fixes it surfaces.
2. **Commit** → `/dtk:smart-commit` (it commits in logical groups and pushes by
   default; if it didn't push, push after).
3. **Open PR** → `/dtk:create-pr` (or the repo's own project-level `create-pr`
   skill if it ships one). It carries the PR conventions a raw `gh pr create`
   misses — standardized title, PR template, task-tracker link, base-branch
   detection. First check `gh pr view` / `gh pr list --head <branch>`: if a PR
   already exists for this branch, reuse it instead of erroring on a duplicate
   create.
4. **Assign reviewers** → the reviewer set is whatever the repo actually
   supports; never hardcode a person.
   - **CODEOWNERS (human reviewers):** check `.github/CODEOWNERS`, `CODEOWNERS`,
     or `docs/CODEOWNERS`. If one exists and matches the changed paths, GitHub
     auto-requests those owners when the PR opens — confirm with
     `gh pr view --json reviewRequests`. GitHub only auto-requests owners when
     the PR is *ready for review*; on a draft, don't read an empty
     `reviewRequests` as "no owners" — match the entries against the changed
     paths yourself, or re-check after marking ready. If no CODEOWNERS file
     exists, or none of its entries match, **don't invent a reviewer** — report
     "no human reviewer auto-assigned (CODEOWNERS doesn't cover these paths)"
     and continue. Always honor an explicit reviewer override from the user.
   - **Copilot (optional):** try `gh pr edit --add-reviewer Copilot`. Many repos
     don't have Copilot code review enabled — if the request fails, treat Copilot
     as **not available here**, note it, and move on. Don't stop the pipeline
     over it, and don't wait for a review that will never come (see step 5).
5. **Monitor CI + any assigned reviews in one loop** → poll until they resolve
   (don't block the user; check periodically via `/loop` or spaced checks):
   - **CI**: `gh pr checks <PR>` (or `gh pr view --json statusCheckRollup`).
     A red check is the "tests are red" gate. If a CI-debugging skill is
     available (e.g. `/dtk:debug-gh-action`), invoke it on the failing run in
     autonomous mode: root-cause, fix, commit + push without stopping, then hand
     back — CI re-runs on the push, so re-enter this loop. Cap it at **2 fix
     attempts per check**: if the same check is still red after two pushed fixes,
     or the debug skill reports the failure as pre-existing/flaky/needing a
     product decision, stop at the red gate and notify. If no CI-debug skill is
     available, stop at the red gate immediately and report the failing check —
     don't guess at a fix. Never proceed to triage/reply while CI is red.
   - **Mergeability**: `gh pr view --json mergeable` — a conflict with the base
     is a red gate too.
   - **Reviewers**: `gh pr view --json reviews` until the assigned reviews land.
     Only wait on reviewers that were actually assigned in step 4 — if Copilot
     wasn't available and CODEOWNERS didn't match, there's nothing to wait for,
     so go straight to step 6. If a reviewer *was* assigned but hasn't posted
     after ~15 min, don't wait forever — move on and note it never showed up.
6. **Run `/dtk:review`** on the PR to review your own diff against the project
   knowledge base and collect any reviewer comments into categorized tasks.
7. **Triage findings** → merge `/dtk:review`'s output with any reviewer
   comments into a to-do list; resolve the relevant/blocking ones, skip noise.
   Commit + push the fixes, then wait for CI to go green again on the new push
   before declaring done.
8. **Reply to reviewers** → if any reviewer left comments, answer them on GitHub
   in the *author-reply* register: English, succinct, answer the question or say
   what you changed — no commit links, no review tags. (The tag taxonomy in
   `/dtk:review-peer` is for when *you* review someone else's PR; here you're the
   author responding to feedback on your own, so it doesn't apply.) Skip this
   step entirely when no reviewer comments exist.
9. **Notify** → announce the outcome with the first available notifier, checked
   in order: `speak-notify "<msg>"`, then `say "<msg>"` (macOS), then
   `spd-say "<msg>"` (Linux speech-dispatcher), then
   `notify-send "ship" "<msg>"` (Linux desktop), then a plain printed line if
   none exist. Message like `PR ready: <repo>#<number>`. Also notify when the
   pipeline *stops* on a red gate (failing CI, conflict, blocking change
   request) — a silent pause defeats the point of running unattended.

## Final report

End the run with a checklist final report — one line per pipeline step, in
execution order, then a short summary:

```
✅ review-local: 2 safe fixes applied
✅ commit + push: 3 commits on ABC-231-fix-avatar-cache
✅ PR #142 opened → https://github.com/org/repo/pull/142
⏭️ Copilot: not enabled on this repo
✅ CODEOWNERS: @org/frontend auto-requested
✅ CI green (12 checks)
❌ review: 1 blocking comment needs a product decision (retry config)

Shipped the avatar-cache fix as PR #142; CI is green.
One blocking review comment about the retry config needs your call.
```

Line rules: **✅** ran and succeeded, **⏭️** skipped (say why), **❌** failed or
hit a red gate (one concrete reason), **⚠️** done with a caveat. Each line
carries a concrete outcome — counts, branch names, PR numbers, URLs — not just
the step name. A run that stopped early still lists the remaining steps as ⏭️ so
the reader sees what did *not* happen. Summary is at most 3 lines; if a ❌
stopped the run, the summary says exactly what decision or fix unblocks it.

## Resuming mid-pipeline

Before redoing steps 1-3, check where the branch actually stands so already-done
work isn't repeated:

- Diff already committed and pushed, no PR yet → skip straight to step 3.
- PR already open (`gh pr view --json number,url,state,reviewRequests,reviews`
  succeeds) → skip steps 2-3. If reviewers are already assigned, skip to step 5;
  otherwise run step 4 first.
- PR open, CI green, reviews already in, nothing new to triage → jump to step 6.
  If CI is red on the existing PR, deal with that first (step 5's CI gate).
- Nothing changed since the last run (no new commits, review already replied to)
  → say so and stop; there's nothing left to ship.

## Inputs / defaults

- Reviewers default to the repo's CODEOWNERS (auto-requested by GitHub when a
  CODEOWNERS file matches the changed paths) plus Copilot when the repo has it
  enabled. No hardcoded fallback reviewer — accept an explicit override arg.
- Base branch is detected by `create-pr` / `review-local` (upstream → repo
  default branch); accept an override.
- If there's no diff to ship, say so and stop.

## Guardrails

- Never force-push a shared/protected branch. Never merge to the base here —
  shipping ends at "PR reviewed and replied to", not merged.
- Stop and ask when: tests are red (and no debug skill resolved it), there's a
  conflict, or a reviewer change request needs a product decision. Everything
  else runs through.
- Respect any standing autonomy grant / stop-conditions the user set.

## Dependencies

Chains `/dtk:review-local`, `/dtk:smart-commit`, `/dtk:create-pr`, and
`/dtk:review`. Uses a CI-debugging skill (e.g. `/dtk:debug-gh-action`) at the CI
red gate **if one is installed** — degrades to stopping at the gate when it
isn't. PR creation and edits go through `create-pr` / `gh pr edit`. Reviewer
replies use a plain author-reply register (no external voice skill required).
Requires `git` and an authenticated `gh` CLI. The end-of-run notifier is
auto-detected (`speak-notify` / `say` / `spd-say` / `notify-send` / print), so no
machine-specific setup is assumed.
