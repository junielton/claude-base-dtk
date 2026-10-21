# Spec: review tone, verdict and evals

Date: 2026-10-20 · Repo: `junielton/claude-base-dtk` (the `dtk` plugin) · Integration branch: `feat/review-tone`
Evidence: [`2026-10-20-review-case-study.md`](./2026-10-20-review-case-study.md), section 8.

## Problem

Across the last 50 PRs reviewed with `/dtk:review-peer` → `/dtk:review-publish`, the pipeline finds the same things a human tech lead finds and gets ~77% of its FFTs accepted. What differs is **tone and verdict**, not taxonomy:

| | pipeline (n=165 inline comments) | tech lead (n=57) |
|---|---|---|
| hedges ("might be worth", "maybe", "could be worth") | 56 | 0 |
| "feel free to ignore / fine to leave / totally optional" | 9 | 0 |
| `suggestion` blocks | 0 | 12 |
| "I'd …" | 0 | 19 |
| CR posted as `REQUEST_CHANGES` | 0 of 6 | 3 of 3 |
| CR refused by the author and merged over | 2 of 6 | 0 of 3 |

The hedging is prescribed by the user's voice skill (juni-vox: "frame suggestions as proposals: could, might be worth, feel free to ignore"), and `review-publish` carries it through. A CR under a `COMMENT` verdict is a request the author can decline, and twice they did.

Decisions NOT taken, with the evidence against them (see case study §8): no NIT tag, no wider CR (rule violations stay FFT; the only convention-based CR in 50 PRs was refused), no cap on comment volume, no "mechanism visible in code → CR" rule for the verifier.

## Changes (four, no more)

1. A CR finding posts the review as `REQUEST_CHANGES`. No CR → `APPROVE`. The inline carries the content, the verdict carries the block.
2. No hedge in any GitHub body. Banned, case-insensitive: `might be worth`, `maybe`, `could be worth`, `feel free to ignore`, `totally optional`, `take it or leave it`, `fine to leave`, `not a big deal`, `just a thought`. The ask is direct ("I'd …", "worth …", "this needs …"); the humility lives in the *reason* and in the tag (FFT already says non-blocking).
3. A finding whose fix is a local patch ships a ` ```suggestion ` block with the patch.
4. `review-peer` step 8 loses the sentence "Send the severity you actually intend to post: the verifier demands proof for `blocking`, but only checks the factual premise for `non-blocking` / `question`." It leaks the verifier's rubric into the reviewer's labeling choice.

Change 2 and 3 must hold **after** the voice pass: the voice skill shapes words, never adds hedges; whatever it adds, the lint rejects.

## Units

### U1 — `review-publish`: verdict, tone lint, suggestion blocks, payload eval

Files: `skills/review-publish/SKILL.md`, `bin/skill-scripts/review/post-review.sh`, new `bin/skill-scripts/review/tone-lint.sh`, new `skills/review-publish/evals/` (cases, fixtures, `run.sh`, `grade.py` or `grade.sh`, `README.md`).

Method, as steps (the repo ships no CLAUDE.md; this is the method for this unit): the first commit on the branch is the eval suite failing against the current skill, with the failing counts in `evals/README.md`; the implementation commits follow; the last commit updates the README with the new counts. `git log` must show that order.

- [ ] AC-1 — `tone-lint.sh --payload <json>` exits non-zero and names the offending comment/phrase for each banned phrase in `body` or any `comments[].body`; exits 0 on a clean payload; also fails a comment body that does not start with `Q: `, `CR: ` or `FFT: `, a comment over two sentences, and `event: COMMENT` or `APPROVE` when any comment is tagged `CR:` — verify: test (a fixture dir with ≥ 6 payloads, a shell test that runs them) — source: spec §Changes 1–2
- [ ] AC-2 — `post-review.sh --dry-run` and the real post both call `tone-lint.sh` and refuse the payload when it fails; the refusal text names the rule — verify: test — source: spec §Changes
- [ ] AC-3 — `review-publish/SKILL.md`: step 2 maps "any 🔴" → `REQUEST_CHANGES`; step 3 bans the hedge list and requires the `suggestion` block when the fix is a local patch; step 4's voice brief says the voice pass never adds hedges and that the lint runs after it; the Common Mistakes table has rows for a hedged CR and a CR posted as COMMENT — verify: review — source: spec §Changes 1–3
- [ ] AC-4 — `skills/review-publish/evals/run.sh` runs the skill body (frontmatter stripped, via `claude -p --append-system-prompt-file`, same pattern as `agents/evals/dtk-review-verifier/run.sh`) against 5 fixture reports and stops at the dry run; the grader reads the produced `publish-N.json`. Fixtures: (a) 1 CR + 2 FFT, (b) only FFT + Q, (c) zero findings, (d) a report with `Existing Review Comments`, `Reconciliation` and CI notes that must not leak, (e) a finding marked `not checked` that must be dropped — verify: test — source: spec §Evals layer 1
- [ ] AC-5 — grader assertions per case: verdict correct; lint passes; the set of `path:line` in the payload equals the set of verified findings in the report (nothing dropped, nothing invented); no sentence from the banned sections appears in any body; case (a)'s CR carries a `suggestion` block — verify: test — source: spec §Evals layer 1
- [ ] AC-6 — `evals/README.md` records, for the current skill (snapshot before edits) and the new one, pass counts over 3 runs per case (15 runs each), plus how to run — verify: review — source: spec §Evals layer 1
- [ ] AC-7 — the eval does not post to GitHub under any outcome (no `gh api` with a review payload is reachable from `run.sh`) — verify: review — source: spec §Evals

Scope: only the files above. Do not touch `review-peer`, the verifier, `voice-resolver.sh`, or any skill outside `review-publish`.

### U2 — `review-peer`: labeling eval, delete the step-8 hint

Files: `skills/review-peer/SKILL.md`, new `skills/review-peer/evals/` (`run.sh`, `cases.json`, `README.md`). Reuses `agents/evals/dtk-review-verifier/fixture/` read-only — do not edit the fixture.

Method: first commit is the eval with the baseline numbers for the current skill; second commit deletes the hint; third commit records the new numbers.

- [ ] AC-1 — `run.sh` materializes the verifier fixture as a repo (base + change commit, copy the mechanism from the verifier's `run.sh`), injects `review-peer`'s analysis passes (step 4) and severity definitions as the system prompt with the GitHub-collection step replaced by `git diff main...feature/orders-invoices`, asks for the report in the skill's own format, and parses the 🔴 / 🟡 / 💬 sections — verify: test — source: spec §Evals layer 2
- [ ] AC-2 — labeled expectations: SQL injection in `UserController` → 🔴; the added-loop N+1 in `OrderController::index` → 🟡 (amended 2026-10-20 by the operator: the first version said 🔴, inherited from the verifier eval, which only tests that the verifier keeps a finding *submitted* as blocking; under the Severity Definitions an N+1 returns the correct result and is an improvement, consistent with CR = demonstrable wrong result); the `MoneyFormatter` duplication in `InvoiceController` → 🟡; the pre-existing N+1 in `ReportBuilder` → absent; "missing authorization in `show()`" → absent or 💬 (the middleware exists). Grader reports per finding which bucket it landed in — verify: test — source: verifier eval README, case study §8
- [ ] AC-3 — `README.md` records bucket outcomes over 5 runs for the skill with the hint and 5 without, and states plainly whether the deletion moved anything — verify: review — source: spec §Evals layer 2
- [ ] AC-4 — `SKILL.md` step 8 no longer contains the "Send the severity you actually intend to post…" sentence; nothing else in the skill changes — verify: review — source: spec §Changes 4

Scope: only the files above.

### U3 — review outcomes script

Files: new `bin/skill-scripts/review/outcomes.py` (python3 stdlib + `gh`), new `docs/review-outcomes.md`.

- [ ] AC-1 — `outcomes.py owner/repo --limit 50 [--since YYYY-MM-DD] [--reviewer login]` fetches PRs via `gh api graphql` (reviews, review threads with comments, commits) and prints: comments per tag (Q/CR/FFT/NIT/untagged) per reviewer; hedge count and `suggestion` count per reviewer (same regex as `tone-lint.sh`, read from it or duplicated with a comment pointing there); review verdicts per reviewer; for each tag, acceptance by the author's reply text (accepted markers: "good catch", "done", "fixed", "added", a 7-hex sha; declined: "keeping", "intended", "not for this PR", "already"), with open PRs excluded from "no reply" — verify: test (run on `bythepixel/transwest-web --limit 50`) — source: case study §8
- [ ] AC-2 — the run on `bythepixel/transwest-web --limit 50 --reviewer junielton` reproduces the 2026-10-20 baseline within ±2: hedge 56, optional 9, suggestion 0, CR as REQUEST_CHANGES 0/6 — verify: test — source: case study §8 table
- [ ] AC-3 — `docs/review-outcomes.md` records that baseline for both repos and says when to rerun (after ~10 reviews on the new skill) — verify: review — source: spec §Evals layer 3
- [ ] AC-4 — no token or secret in the script or docs; it relies on `gh auth` — verify: review

Scope: only the files above.

### U4 — juni-vox review tone (repo `~/.claude/skills`, no remote, no PR)

File: `juni-vox/SKILL.md`, the "In inline code comments…" paragraph and the PR-review taxonomy section only.

- [ ] AC-1 — the paragraph no longer prescribes "could", "might be worth", "feel free to ignore"; it says: state the ask directly ("I'd … because …"), put the humility in the reason, never mark a finding optional (the FFT tag already says non-blocking), ship a `suggestion` block when the fix is a local patch, and a CR names what unblocks it — verify: review — source: spec §Changes 2–3
- [ ] AC-2 — the examples in that section match the new rule (no hedged example survives) — verify: review
- [ ] AC-3 — nothing else in juni-vox changes (voice, email/Slack/WhatsApp sections, the "never cite local environment state" rule) — verify: review (`git diff --stat` shows one file, the hunk is inside those two sections)
- [ ] AC-4 — the change is a single commit on branch `review-tone` in a worktree; the live `~/.claude/skills` checkout is not modified — verify: test (`git log main..review-tone` = 1, `git -C ~/.claude/skills status` unchanged)

## Evals (three layers)

1. **Payload eval** (U1): programmatic, runs the skill up to the dry run, grades the JSON. 5 cases × 3 runs.
2. **Labeling eval** (U2): same fixture as the verifier eval, grades which bucket known findings land in, with vs without the hint.
3. **Outcomes script** (U3): the production metric, rerun after ~10 real reviews. Baseline recorded 2026-10-20.

## Done

`feat/review-tone` carries U1–U3 merged, both eval suites green with READMEs recording baseline vs new, `tone-lint.sh` wired into `post-review.sh`; a PR `feat/review-tone → main` is open with the Delivery Report as body; U4 is one commit on `review-tone` in `~/.claude/skills`. Merging to `main` (which bumps the plugin to 1.12.0 via CI) is the operator's.
