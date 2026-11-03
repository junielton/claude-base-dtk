---
name: ship
description: "Use to run the full PR lifecycle in one go instead of hand-chaining review-local → smart-commit → open the PR → assign reviewers → monitor CI + reviewers → resolve → capture lessons → reply. Triggers on 'ship this', 'ship isso', 'open the PR and monitor it', 'run the PR pipeline', 'faz o fluxo completo de PR', or when the user lists that same sequence of steps by hand. Safe to re-run mid-pipeline: it detects what's already committed/open and resumes instead of redoing it. It chains the other dtk skills (review-local, smart-commit, create-pr, review, learn-from-review) with sane defaults. Do NOT use for a plain commit (smart-commit), just opening a PR with no follow-through (create-pr), or landing many branches at once."
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

## Delegation contract

Ship is an orchestrator. Every step below that names a skill (`/dtk:review-local`,
`/dtk:smart-commit`, `/dtk:create-pr`, `/dtk:review`, `/dtk:debug-gh-action`,
`/dtk:learn-from-review`, `/dtk:report-back`) is executed by **calling that skill
with the Skill tool**. Doing the same work inline is not a shortcut, it is
skipping the step: reading the diff yourself instead of `review-local`,
`gh pr create` instead of `create-pr`, or reading a failing log and calling it
flaky instead of `debug-gh-action`. Those skills carry what the inline version
lacks (verifier-filtered findings, lessons checkpoints, PR template and
task-link conventions, flaky-vs-real triage), so a PR shipped without them looks
fine and quietly isn't.

- **Say the plan first.** Before step 1, print one line per step you will run
  and the skill each one calls, so a skipped skill is visible before it happens.
- **An instruction replaces a step only when it names that step.** "Skip the
  review", "open the PR with `gh` directly" and "don't notify" skip or replace
  exactly what they name. A convention or style ask ("title per CONTRIBUTING.md",
  "review the diff cold", "keep it short") is not a replacement: it is input to
  the skill, which already discovers `CONTRIBUTING.md` and the PR template at
  runtime. This holds for a dispatcher's override list too: apply what it names,
  run everything else through its skill.
- **A skill that can't be called stops the step.** If the Skill call fails or the
  skill doesn't exist, don't improvise the work: mark the step failed with the
  error and stop there, unless the user said otherwise.
- **A step may be skipped only for a stated reason**: the resume logic below
  removed it, or an instruction named it. The final report says which.

## The pipeline

1. **Review own diff** → call `/dtk:review-local` on the changes; apply the safe
   fixes it surfaces. Reading the diff yourself is not this step.
2. **Commit** → `/dtk:smart-commit` (it commits in logical groups and pushes by
   default; if it didn't push, push after).
3. **Open PR** → call the repo's own project-level `create-pr` skill if it ships
   one, otherwise `/dtk:create-pr`. Never a raw `gh pr create`: the skill carries
   the PR conventions it misses (standardized title, PR template, task-tracker
   link, base-branch detection). First check `gh pr view` / `gh pr list --head <branch>`: if a PR
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
   - **Copilot (optional):** request it via REST, with the `[bot]` suffix:
     ```
     gh api repos/{owner}/{repo}/pulls/{number}/requested_reviewers \
       -f "reviewers[]=copilot-pull-request-reviewer[bot]"
     ```
     Never `gh pr edit --add-reviewer Copilot` — that goes through GraphQL, which
     fails to resolve the Copilot bot login ("Could not resolve user") even in
     repos where Copilot review works fine. The REST call is idempotent and
     doubles as the availability check, so no separate detection step is needed:
     where Copilot code review is auto-enabled it has usually already attached
     itself (visible in `gh pr view --json reviews` as author
     `copilot-pull-request-reviewer`, never in `reviewRequests`) and the call is a
     silent no-op; where it isn't, this call is what actually requests it. Only a
     real REST failure (422 "Reviews may only be requested from collaborators")
     means Copilot is genuinely unavailable here — that, and only that, is worth
     reporting as "Copilot not available". Don't stop the pipeline over it, and
     don't wait for a review that will never come (see step 5).
5. **Monitor CI + any assigned reviews in one loop** → poll until they resolve
   (don't block the user; check periodically via `/loop` or spaced checks):
   - **CI**: `gh pr checks <PR>` (or `gh pr view --json statusCheckRollup`).
     A red check is the "tests are red" gate: call `/dtk:debug-gh-action` on
     the failing run. Don't call a failure flaky or unrelated from the log
     yourself: that verdict comes from the skill's report. It runs in pipeline mode here (its autonomous-caller
     exception): root-cause, fix, commit + push without stopping to ask, then
     hand back — CI re-runs on the push, so re-enter this loop. Cap it at
     **2 fix attempts per check**: if the same check is still red after two
     pushed fixes, or `/dtk:debug-gh-action` reports the failure as
     pre-existing/flaky/needing a product decision, stop at the red gate and
     notify. Never proceed to triage/reply while CI is red.
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
   Commit the fixes, run step 8, then push once (fixes + any lessons commit) so
   CI runs a single time, and wait for it to go green again before declaring
   done.
8. **Capture lessons** → turn what this run exposed into `docs/lessons/`, so
   the next review catches it. This runs in the same session as the reviews, so
   `/dtk:learn-from-review` already sees the findings; ship's job is to hand it
   only the candidates that clear the gate below.
   - **Candidates** (nothing else qualifies):
     - a finding from `/dtk:review-local` or `/dtk:review` that survived
       `dtk-review-verifier`, was fixed, and did **not** cite a `docs/lessons/`
       file. A finding that cites one is already documented.
     - the root cause of a CI fix made at the red gate in step 5.
     - a correction the user made to your approach during this run.
     - a reviewer comment (Copilot or human) that you accepted and fixed in
       step 7. Reviewer comments are not run through `dtk-review-verifier`, so
       one you declined or ignored never qualifies.
   - **Gate:** a candidate becomes a lesson when it is High/Critical, or it is
     an accepted-and-fixed reviewer comment, or its pattern is already listed in
     `docs/lessons-candidates.md`. Anything else gets a one-line entry appended
     to that file (date, category, pattern, `file:line`) and the run moves on; a
     second occurrence promotes it, and promoting removes its entry. The list
     lives outside `docs/lessons/` on purpose: the lessons loader reads every
     `*.md` under it and would treat the list as a lesson.
   - **Write:** run `/dtk:learn-from-review` on the candidates that passed,
     with the Bad/Good examples taken from this branch's real diff. Its
     `--check-dup` step skips duplicates. Never write to `CLAUDE.md`. Commit as
     a separate docs-only commit (`docs(lessons): <summary>`), not mixed into
     the feature or fix commits, so it can be dropped in review.
   - **Nothing passes the gate** (the common case) → report the step as
     skipped and continue. Don't fabricate lessons to fill the step.
9. **Reply to reviewers** → if any reviewer left comments, answer them on GitHub
   in the *author-reply* register: English, succinct, answer the question or say
   what you changed — no commit links, no review tags. (The tag taxonomy in
   `/dtk:review-peer` is for when *you* review someone else's PR; here you're the
   author responding to feedback on your own, so it doesn't apply.) Skip this
   step entirely when no reviewer comments exist.
10. **Notify** → announce the outcome with the first available notifier, checked
   in order: `say "<msg>"` (macOS), then
   `spd-say "<msg>"` (Linux speech-dispatcher), then
   `notify-send "ship" "<msg>"` (Linux desktop), then a plain printed line if
   none exist. Message like `PR ready: <repo>#<number>`. Also notify when the
   pipeline *stops* on a red gate (failing CI, conflict, blocking change
   request) — a silent pause defeats the point of running unattended.

## Final report

Call `/dtk:report-back` with the Skill tool (not a hand-written report) for the
final report: one row per pipeline step above (steps the resume logic or an
instruction skipped are reported as skipped; a red gate gets one concrete
reason). Each completed delegated step names the skill call that produced it
(`review-local — 0 findings`). A step done without its skill is never reported
as completed: report it as failed or skipped, with the reason. Follow that
skill's format rather than improvising one here.

## Resuming mid-pipeline

Before redoing steps 1-3, check where the branch actually stands so already-done
work isn't repeated:

- Diff already committed and pushed, no PR yet → skip straight to step 3.
- PR already open (`gh pr view --json number,url,state,reviewRequests,reviews`
  succeeds) → skip steps 2-3. If reviewers are already assigned, skip to step 5;
  otherwise run step 4 first.
- PR open, CI green, reviews already in, nothing new to triage → jump to step 6.
  If CI is red on the existing PR, deal with that first (step 5's CI gate).
- Reviews that landed after the previous run (typically a human's, since step 5
  only waits on reviewers for ~15 min) are new input: triage them in steps 6-7,
  and step 8 treats the ones you accept and fix as lesson candidates. That is how
  human feedback reaches `docs/lessons/` without ship waiting hours for it.
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
- Lessons are docs-only and in their own commit. Never write them to
  `CLAUDE.md`, and never invent one when no candidate clears the step 8 gate.

## Dependencies

Chains `/dtk:review-local`, `/dtk:smart-commit`, `/dtk:create-pr`, `/dtk:review`,
`/dtk:debug-gh-action` (at the CI red gate), `/dtk:learn-from-review` (step 8,
only for candidates that clear the gate), and `/dtk:report-back` (final report). PR creation and edits go through `create-pr` / `gh pr edit`. Reviewer
replies use a plain author-reply register (no external voice skill required).
Requires `git` and an authenticated `gh` CLI. The end-of-run notifier is
auto-detected (`say` / `spd-say` / `notify-send` / print), so no
machine-specific setup is assumed.
