---
name: review-peer
description: "Use when reviewing a teammate's pull request, providing peer feedback on someone else's PR, or when asked to review a PR you didn't author."
---

# Peer Review: PR #$ARGUMENTS

## Overview

Analyzes someone else's PR and saves a review report: blocking/non-blocking issues and questions for the author, each put through the `dtk-review-verifier` subagent, which tries to disprove it before it is written down. Features persistent memory shared with `/review` and `/review-local`.

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
SCRIPTS="bin/skill-scripts"; [ -d "$SCRIPTS" ] || SCRIPTS="${CLAUDE_PLUGIN_ROOT:-}/bin/skill-scripts"; [ -d "$SCRIPTS" ] || SCRIPTS=$(find ~/.claude/plugins -path "*/dtk/bin/skill-scripts" -maxdepth 5 2>/dev/null | head -1); echo "$SCRIPTS"
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

Save to: `{project_root}/memories/reviews/PR-{$ARGUMENTS}/peer-review-{N}.md`

```
# Peer Review — PR #$ARGUMENTS

## Recommendation: ✅ Approve | ⚠️ Approve with Comments | ❌ Request Changes

**Summary:** 2-3 sentences on overall PR quality and key concerns.

---

## 🔴 Blocking

### `file:line` — Short title
```language
// relevant code snippet
```
Your feedback explaining why this blocks the merge and what should change.

---

## 🟡 Non-blocking

### `file:line` — Short title
```language
// relevant code snippet
```
Suggestion for improvement. Does not block merge.

---

## 💬 Questions

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

**Reconciliation (only for subsequent reviews)** — append the **Reconciliation Section** after "Lessons Applied", preceded by a `---` line.

**Final Summary** (always include):
- Total comments analyzed from other reviewers
- How many resulted in agreement vs. disagreement
- **Findings verified: X kept, Y refuted by `dtk-review-verifier`**
- Lessons Learned that applied (list which ones)
- Your recommendation with justification

### 10. Memory — Save (execute AFTER generating output)

Run **Memory — Save**. The state is shared with `/review` and `/review-local`: merge, never overwrite.

### 11. Hand off

The review is done when the report and the state are saved. To put it on GitHub, invoke `/dtk:review-publish $ARGUMENTS`. Do not draft the comment here: the report's `Reconciliation`, `Existing Review Comments` and `Final Summary` are reviewer memory and must not leak into what the author reads.

## Tone & Perspective

Findings should be:
- **English** — the report is the source `/dtk:review-publish` quotes from
- **Constructive** — suggest improvements, don't just point out flaws
- **Humble when uncertain** — ask genuine questions instead of assuming something is wrong
- **Specific** — always reference file, line, and code snippet

## Severity Definitions

- **🔴 Blocking** — must be fixed before merge (bugs, security issues, breaking changes)
- **🟡 Non-blocking** — improvement opportunity, does not block merge
- **💬 Questions** — genuine clarification requests for the author

## Common Mistakes

The shared ones (diff lines, memory order, decided items, refuted verdicts, overwriting the state) are in the workflow reference. Specific to this skill:

| Mistake | Fix |
|---------|-----|
| Assuming something is wrong | Ask a question when uncertain |
| Vague feedback without code references | Always reference file, line, and snippet |
| Posting findings without verification | Run step 8 — a false positive on a teammate's PR costs credibility |
| Drafting the GitHub comment inside this skill | Save the report, then `/dtk:review-publish`; CI state and old-thread status never belong to the author's comment |
