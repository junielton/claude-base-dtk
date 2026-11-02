# Reviewer Alerts and Review TL;DR Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `create-pr` writes GitHub alerts for what the reviewer must weigh, and `review-peer` → `review-publish` show an executive TL;DR with the critical facts above the approval gate.

**Architecture:** Three SKILL.md edits (prose contracts the model follows), one new lint rule in `scripts/review/tone-lint.sh` so the TL;DR can never reach GitHub, and a small informational line in the `review-peer` eval grader. No new scripts, no shared-workflow change.

**Tech Stack:** Markdown skills, bash + jq (`tone-lint.sh`, `run-tests.sh`), python3 (`grade.py`).

**Spec:** `docs/specs/2026-11-02-pr-alerts-and-review-tldr.md`

## Global Constraints

- Report glyphs are the frozen report-back set: `✗` `!` `?` `✓` `-` `⚑`, one space after, no emoji (`skills/review/references/output-vocabulary.md`).
- Section names in reports are matched by word (`TL;DR`, `Recommendation`, `Blocking`…), never by marker.
- Alert syntax is GitHub's: `> [!WARNING]` on its own line, the text on the following `> ` lines. Types: `CAUTION`, `WARNING`, `IMPORTANT`, `NOTE`, `TIP`.
- At most 4 alerts per PR; a TL;DR is 1 sentence + 2 to 5 lines.
- `tone-lint.sh` rules are listed in its header comment and in `review-publish` step 5; a new rule appears in both.
- Nothing in `skills/review/references/workflow.md`, `review/SKILL.md` or `review-local/SKILL.md` changes.

## Review Focus

1. A PR body with no alerts and a diff with no CI/infra/destructive change: `review-peer` still writes the `## TL;DR` section with its "nothing critical" line, so `review-publish` never has to handle a missing section. (Task 2 template says the section is always present.)
2. A payload whose inline comment quotes the author's `> [!WARNING]` text and happens to contain "TL;DR": the lint refuses it; the fix is to drop the phrase, not the rule. (Task 1 test covers body and comment.)
3. A template with no section matching the attention regex and no Description-like section (an unusual template): alerts go at the top of the first section after the title. (Task 4 fallback.)
4. More than 4 candidate alerts: the 4 most severe stay as alerts, the rest become ordinary bullets in the same section. (Task 4 rule.)
5. An old report saved before this change (no `## TL;DR`): `review-publish` prints the gate as before and says the report has no TL;DR. (Task 3 rule.)

---

### Task 1: `tldr-leak` rule in `tone-lint.sh`

**Files:**
- Modify: `scripts/review/tone-lint.sh` (header comment, jq program)
- Create: `skills/review-publish/tests/payloads/tldr-in-comment.json`
- Modify: `skills/review-publish/tests/run-tests.sh` (two `expect_lint` lines)

**Interfaces:**
- Produces: rule name `tldr-leak`, reported as `tone-lint: tldr-leak: <where>: ...` on stderr, exit 1.

- [ ] **Step 1: Write the failing tests**

`tldr-in-comment.json` = `clean-approve.json` with one comment whose body is `FFT: TL;DR the loop re-queries, I'd eager load it.` Add to `run-tests.sh` after the `cr-as-approve` line:

```bash
expect_lint "rejects 'TL;DR' in a comment"                  "$PAY/tldr-in-comment.json"              1 "tldr-leak"
jq '.body = "TL;DR: approving." | .comments = []' "$PAY/clean-approve.json" > "$TMP/tldr-body.json"
expect_lint "rejects 'TL;DR' in the review body"            "$TMP/tldr-body.json"                    1 "tldr-leak"
```

(`$TMP` exists before the lint block; move the two lines below the `TMP=` assignment if needed.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash skills/review-publish/tests/run-tests.sh | grep -A1 "TL;DR"`
Expected: two `FAIL` lines, "exit 0, wanted 1".

- [ ] **Step 3: Implement the rule**

In the jq program add, after the `missing-tag-prefix` clause: every item (body and comments) whose text matches `(?i)tl;dr` yields `"tldr-leak: \(.where): the TL;DR stays in the transcript, never in what goes to GitHub"`. Add the rule to the header comment list.

- [ ] **Step 4: Run the whole test file**

Run: `bash skills/review-publish/tests/run-tests.sh; echo rc=$?`
Expected: every line `PASS`, `rc=0`.

- [ ] **Step 5: Commit**

```bash
git add scripts/review/tone-lint.sh skills/review-publish/tests
git commit -m "feat(review-publish): refuse a payload that carries the TL;DR"
```

### Task 2: `review-peer` — critical facts pass and the TL;DR section

**Files:**
- Modify: `skills/review-peer/SKILL.md` (Overview, step 4b, step 9 template, Final Summary, Tone, Common Mistakes)
- Modify: `skills/review-peer/evals/grade.py` (informational TL;DR line count per run)
- Modify: `skills/review-peer/evals/README.md` ("What this does not cover" note)

**Interfaces:**
- Produces: a `## TL;DR` section in `peer-review-N.md`, right after `## Recommendation` and its `**Summary:**` line, before the first `---`. Shape:

```
## TL;DR

<one sentence: what the PR does, plain words>

- ✗ <critical fact, concrete number/file first, then why it matters> (<source: file:line or "body, <section>">)
- ! <attention fact> (<source>)
```

- [ ] **Step 1: Add step 4b "Collect critical facts"** after step 4 in the Workflow. It lists the five sources from the spec §2 in order, the citation rule, the "becomes a Question too" rule, and that these facts are not findings and skip the verifier.

- [ ] **Step 2: Add the `## TL;DR` block to the step 9 template** with the shape above, the limits (1 sentence + 2 to 5 lines), the glyph meanings (`✗` irreversible or a cost the reviewer must accept; `!` attention), the audience rule (a manager and a developer read it the same), and the always-present rule with the empty form: `- Nothing critical: <why, one clause>`.

- [ ] **Step 3: Worked example.** Under the template add the PR #314 TL;DR from the spec's evidence (doubled CI time with the author's numbers at `deploy.yml:97`; the step not run on GitHub, cited to "body, AI Assistance"; the `force="true"` doubt, marked "raised as a Question").

- [ ] **Step 4: Final Summary and Common Mistakes.** Add `- TL;DR lines: X, of which Y raised as Questions` to the Final Summary list. Add two rows: "A cost or an unproven claim left out because it is not a bug → it goes in the TL;DR, and as a Question when the author must answer" and "A TL;DR line with no number, file or quoted sentence → cite the source; a vague line is what the reviewer already skims past".

- [ ] **Step 5: `grade.py` informational line.** In `main()`'s per-run loop, after the counts line, print `run{n}: tldr: {k} lines` where `k` counts `- ` lines inside the `## TL;DR` section (0 when absent). Not graded; `ok` unchanged.

- [ ] **Step 6: Verify the grader on a sample.** Write a temp `run-1.md` with the new template (a TL;DR with 3 lines, one `###` finding under `## ! Non-blocking`), run `python3 skills/review-peer/evals/grade.py --cases skills/review-peer/evals/cases.json --dir <tmp> --runs 1`. Expected: the table prints, the run line ends with `tldr: 3 lines`, no traceback.

- [ ] **Step 7: Commit**

```bash
git add skills/review-peer
git commit -m "feat(review-peer): collect critical facts and open the report with a TL;DR"
```

### Task 3: `review-publish` — the TL;DR above the gate

**Files:**
- Modify: `skills/review-publish/SKILL.md` (Overview, step 1, step 5 rule list, step 6, Common Mistakes)

**Interfaces:**
- Consumes: the `## TL;DR` section from Task 2.

- [ ] **Step 1: Step 1 "Load the report".** Add `## TL;DR` to what is read, with the rule: it is shown to the user and never enters the payload (body, comments). Add `TL;DR` to the "never carry into the payload" list with the reason (the author wrote the body; the TL;DR is the reviewer's reading of it).

- [ ] **Step 2: Step 5.** Add `tldr-leak` to the sentence listing what the dry run refuses.

- [ ] **Step 3: Step 6.** The transcript print before `AskUserQuestion` becomes: the TL;DR verbatim under a `TL;DR` line, a blank line, then the dense draft as today. Preview boxes unchanged (the box cuts at ~5 lines; the TL;DR would hide the comments). A report with no `## TL;DR` prints `TL;DR: none in this report (saved before the section existed)`.

- [ ] **Step 4: Common Mistakes.** Add "TL;DR pasted into the review body or an inline → the lint refuses `tldr-leak`; it lives above the gate only" and "Gate printed without the TL;DR → the executive read is the point of the gate; print it first, then the draft".

- [ ] **Step 5: Run the tests**

Run: `bash skills/review-publish/tests/run-tests.sh; echo rc=$?`
Expected: `rc=0`.

- [ ] **Step 6: Commit**

```bash
git add skills/review-publish/SKILL.md
git commit -m "feat(review-publish): print the report's TL;DR above the confirmation gate"
```

### Task 4: `create-pr` — alerts for the reviewer

**Files:**
- Modify: `skills/create-pr/SKILL.md` (Step 4 new block "Alerts for the reviewer", Common Mistakes)
- Modify: `README.md` rows for `create-pr` and `review-peer`

- [ ] **Step 1: Add the block** at the end of Step 4, after "ADR links": the trigger table from spec §1, the four rules (cap and order; backed by the diff or the author; "not run" sentences always get an `IMPORTANT`; placement regex with the first-section fallback, never a new section, never inside `<details>`, template language), the GitHub syntax snippet, and the overflow rule (more than 4 candidates: the 4 most severe stay alerts, the rest become plain bullets).

- [ ] **Step 2: Worked example** from PR #314: the `WARNING` (doubled shard time, 1.5 to 6 minutes, decide whether the check is worth it on every PR) and the `IMPORTANT` (not run on GitHub: the step, `--shard` with `--exclude-group`), placed under "Impacted Areas (Where)".

- [ ] **Step 3: Common Mistakes.** Add: "A cost or a 'not tested' left as a plain bullet → it is an alert, at the top of the section"; "An alert with no number or file → the fact first, then the decision"; "A `NOTE` written to fill the block → no alert when there is nothing to flag"; "A new `## Alerts` section → inject into the template's own section".

- [ ] **Step 4: README.** `create-pr` row: add "and GitHub alerts for what the reviewer must weigh". `review-peer` row: add "opened by an executive TL;DR with the critical facts".

- [ ] **Step 5: Validate the plugin**

Run: `claude plugin validate --strict . 2>&1 | tail -5` (skip if the CLI is absent) and `grep -c '^> \[!' skills/create-pr/SKILL.md` (expected: 2 example alerts at least).

- [ ] **Step 6: Commit**

```bash
git add skills/create-pr/SKILL.md README.md
git commit -m "feat(create-pr): write GitHub alerts for what the reviewer must weigh"
```

### Task 5: Spec and plan on the branch

- [ ] **Step 1: Commit the documents**

```bash
git add docs/specs/2026-11-02-pr-alerts-and-review-tldr.md docs/plans/2026-11-02-pr-alerts-and-review-tldr.md
git commit -m "docs: spec and plan for reviewer alerts and the review TL;DR"
```
