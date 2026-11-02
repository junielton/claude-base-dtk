---
name: review-peer
description: "Use when reviewing a teammate's pull request, providing peer feedback on someone else's PR, or when asked to review a PR you didn't author."
---

# Peer Review: PR #$ARGUMENTS

## Overview

Analyzes someone else's PR and saves a review report: an executive TL;DR of the PR and its critical facts (cost, risk, what the author declared untested), then blocking/non-blocking issues and questions for the author, each put through the `dtk-review-verifier` subagent, which tries to disprove it before it is written down. Features persistent memory shared with `/review` and `/review-local`.

This skill writes the report only. It never drafts or posts the GitHub comment: that is `/dtk:review-publish`, which reads the report, keeps only the verdict and the verified findings, applies the user's voice skill and posts after a confirmation.

## When to Use

- Reviewing a teammate's PR
- Asked to provide feedback on a PR you didn't author
- Second pair of eyes needed on a PR before merge

## When NOT to Use

- Reviewing your own PR (use `/review`)
- Pre-PR local review (use `/review-local`)
- No PR number provided

## Step 0: Resolve Scripts

```bash
# resolver idiom: docs/conventions/script-resolution.md
SCRIPTS="${CLAUDE_PLUGIN_ROOT}/scripts"; [ -d "$SCRIPTS" ] || echo "dtk: scripts dir not found: $SCRIPTS" >&2; echo "$SCRIPTS"
```

Use the output path as `$SCRIPTS` for all script commands below.

## Workflow

Read `${CLAUDE_SKILL_DIR}/../review/references/workflow.md` now, before step 1. Steps 1–8 and 10 run its sections by name, with: `<memory-key>` = `PR-$ARGUMENTS`, `<memory-type>` = `peer-review`, `<report-prefix>` = `peer-review`, `<scope>` = `PR #$ARGUMENTS`.

### 1. Gather Project Context

Run **Gather Project Context**.

### 2. Load Mandatory References

Run **Load Mandatory References**.

### 3. Collect Data (GitHub MCP)

Run **Collect PR Data** for PR #$ARGUMENTS.

### 4. Analyze (execute BEFORE generating any output)

Run **Analyze**, applying the **Diff Reading Rules**.

### 4b. Collect Critical Facts (for the TL;DR)

A bug becomes a finding. A cost, a risk or a gap is not a bug, so the buckets of step 8 never
hold it, and it is exactly what a reviewer approves past. Sources 1, 4 and 5 read the PR's
title and body, which step 3 does not fetch: get them first
(`gh pr view $ARGUMENTS --json title,body`, or the PR-details call of the GitHub MCP). Then
collect these facts, in order:

1. **Alerts the author wrote** in the PR body: `> [!CAUTION]`, `> [!WARNING]`,
   `> [!IMPORTANT]` (and a `[!NOTE]` only when it carries a risk). Carry each one over,
   compressed to one line.
2. **Cost**: CI or infra files in the diff (`.github/workflows/`, `Dockerfile`, migrations,
   cron, queues, env). A job that runs more often, a step added to every PR, a migration on a
   large table. Quote the author's own numbers when the body has them; say "not measured"
   when it does not.
3. **Risk**: a destructive or irreversible operation, a deleted or skipped test, a change to
   auth, permissions, secrets or environment, a dependency bump, a public interface changed.
4. **Claims against the diff**: a sentence in the body the diff does not support, and every
   "not run", "not tested", "did not time it" sentence, wherever it sits (an "AI Assistance"
   or "Notes" section counts; that is where they hide).
5. **Scope**: files changed outside what the title and the body describe.

Each fact cites its source: `file:line` for the diff, `body, <section name>` for the
description. A fact with no source is not written. These facts are not findings: they do not go
through the verifier and they never carry a severity. When a fact needs the author's answer
(an unproven step, a number nobody measured, a claim the diff contradicts), it ALSO becomes a
`? Question` in step 8, through the verifier like any other, and that is how it reaches
GitHub. The Question anchors on the added line the fact is about (the workflow step, the
migration, the test); a fact with no added line to anchor on stays in the TL;DR only, it is
never pinned to an unrelated line. When the verifier refutes that Question (the code already
answers it), the TL;DR line it came from is corrected or dropped, never left standing.

### 5. Evaluate Existing Comments

Run **Evaluate Existing Comments**.

### 6. Memory — Load (execute AFTER analysis, BEFORE generating output)

Run **Memory — Load**.

### 7. Memory — Reconcile (only if review-state.md existed)

Run **Memory — Reconcile**, then the peer review specifics:
- Check if feedback from previous peer reviews was implemented in new commits
- If implemented → move to Resolved with "implemented since peer-review-N"
- If not → keep as Open

### 8. Verify Findings (kill false positives)

Run **Verify Findings**. The Blocking / Non-blocking / Questions buckets map one-to-one to `blocking` / `non-blocking` / `question`; a finding moved by `suggested-severity` changes bucket before it is written to the report.

### 9. Generate Output

```bash
N=$(bash $SCRIPTS/review/memory-manager.sh next-number "PR-$ARGUMENTS" "peer-review")
```

Save to: `{project_root}/memories/reviews/PR-{$ARGUMENTS}/peer-review-{N}.md` (markers: `${CLAUDE_SKILL_DIR}/../review/references/output-vocabulary.md`)

```
# Peer Review — PR #$ARGUMENTS

## Recommendation: ✓ Approve | ! Approve with Comments | ✗ Request Changes

**Summary:** 2-3 sentences on overall PR quality and key concerns.

## TL;DR

<one sentence: what the PR does, in words a manager and a developer read the same>

- ✗ <critical fact: the number, file or duration first, then why it matters> (<source>)
- ! <attention fact> (<source>)

---

## ✗ Blocking

### `file:line` — Short title
```language
// relevant code snippet
```
Your feedback explaining why this blocks the merge and what should change.

---

## ! Non-blocking

### `file:line` — Short title
```language
// relevant code snippet
```
Suggestion for improvement. Does not block merge.

---

## ? Questions

### `file:line` — Short title
Genuine question for the author when something is unclear.

---

## Existing Review Comments

### @author — `file:line` — summary of comment
**Verdict:** Valid | Partially valid | Not applicable
Justification with code references...

---

## Lessons Applied
- List which Lessons Learned were relevant to this review
```

**TL;DR rules.** The section is always present, right after the Summary. One sentence on
what the PR does, then 1 to 5 lines from step 4b, `✗` for a fact the reviewer must accept
before merging (irreversible, or a cost paid on every run) and `!` for attention. Over 5
candidates: `✗` lines first, then the author's own alerts, then the rest; merge `!` lines
that share a cause, and drop from the bottom. A `✗` or an author's `CAUTION`/`WARNING` is
never the one dropped. Fact first,
concrete (a number, a file, a duration, a quoted sentence), then why it matters, one line each;
the source in parentheses. With nothing critical, one line: `- Nothing critical: <why, one
clause>`. The TL;DR is the reviewer's read of the PR and never leaves the report: `/dtk:review-publish`
prints it above the gate and refuses it in the payload.

Worked example (PR `cooling-tower-depot#314`, a CI step that re-runs every shard's tests with
a wrong database password to catch stray reads):

```
## TL;DR

Seven tests read the real legacy database by accident; this binds Fakes in them and adds a CI step that runs every shard's suite a second time with a wrong password, so the next stray read fails on the PR.

- ✗ CI cost: every PR runs each shard's tests twice, about 1.5 to 6 minutes more per shard by the author's own numbers, and nobody has measured it on GitHub (`deploy.yml:97`; body, Impacted Areas)
- ! Not proven: the new step and `--shard` with `--exclude-group` were never run on GitHub; the first PR after merge is the real test (body, AI Assistance)
- ! Nothing asserts the wrong password is applied: `phpunit.xml` pins the variable with `force="true"` (`phpunit.xml:31`; raised as a Question)
```

The first line is what a teammate who reads nothing else must know. The cost line is what the
approving reviewer missed on the real PR.

**Reconciliation (only for subsequent reviews)** — append the **Reconciliation Section** after "Lessons Applied", preceded by a `---` line.

**Final Summary** (always include):
- Total comments analyzed from other reviewers
- How many resulted in agreement vs. disagreement
- **Findings verified: X kept, Y refuted by `dtk-review-verifier`**
- TL;DR lines: X, of which Y raised as Questions
- Lessons Learned that applied (list which ones)
- Your recommendation with justification

### 10. Memory — Save (execute AFTER generating output)

Run **Memory — Save**. The state is shared with `/review` and `/review-local`: merge, never overwrite.

### 11. Hand off

The review is done when the report and the state are saved. To put it on GitHub, invoke `/dtk:review-publish $ARGUMENTS`. Do not draft the comment here: the report's `TL;DR`, `Reconciliation`, `Existing Review Comments` and `Final Summary` are reviewer memory and must not leak into what the author reads.

## Tone & Perspective

Findings should be:
- **English** — the report is the source `/dtk:review-publish` quotes from
- **Constructive** — suggest improvements, don't just point out flaws
- **Humble when uncertain** — ask genuine questions instead of assuming something is wrong
- **Specific** — always reference file, line, and code snippet

## Severity Definitions

- **✗ Blocking** — must be fixed before merge (bugs, security issues, breaking changes)
- **! Non-blocking** — improvement opportunity, does not block merge
- **? Questions** — genuine clarification requests for the author

## Common Mistakes

The shared ones (diff lines, memory order, decided items, refuted verdicts, overwriting the state) are in the workflow reference. Specific to this skill:

| Mistake | Fix |
|---------|-----|
| Assuming something is wrong | Ask a question when uncertain |
| Vague feedback without code references | Always reference file, line, and snippet |
| Posting findings without verification | Run step 8 — a false positive on a teammate's PR costs credibility |
| Drafting the GitHub comment inside this skill | Save the report, then `/dtk:review-publish`; CI state and old-thread status never belong to the author's comment |
| A cost or an unproven claim left out because it is not a bug | It goes in the TL;DR (step 4b), and becomes a Question when the author must answer it |
| A TL;DR line with no number, file or quoted sentence | Cite the source; a vague line is what the reviewer already skims past |
| A `[!WARNING]` the author wrote, missing from the TL;DR | Every CAUTION/WARNING/IMPORTANT in the body is carried over, compressed to one line |
