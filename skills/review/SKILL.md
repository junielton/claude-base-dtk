---
name: review
description: "Use when reviewing your own pull request, processing PR review comments, or triaging feedback on a PR you authored."
---

# PR Review: #$ARGUMENTS

## Overview

Analyzes your own PR's diff and review comments, checks against the project knowledge base (ADRs, lessons, conventions), and outputs categorized tasks. Your own findings are put through the `dtk-review-verifier` subagent before becoming tasks, so you don't chase phantom work. Features persistent memory shared with `/review-local` and `/review-peer`.

## When to Use

- Reviewing your own PR after receiving comments
- Triaging review feedback on a PR you authored
- Re-reviewing after pushing fixes to address comments

## When NOT to Use

- Reviewing someone else's PR (use `/review-peer`)
- Pre-PR local review (use `/review-local`)
- No PR number provided

## Step 0: Resolve Scripts

```bash
SCRIPTS="bin/skill-scripts"; [ -d "$SCRIPTS" ] || SCRIPTS="${CLAUDE_PLUGIN_ROOT:-}/bin/skill-scripts"; [ -d "$SCRIPTS" ] || SCRIPTS=$(find ~/.claude/plugins -path "*/dtk/bin/skill-scripts" -maxdepth 5 2>/dev/null | head -1); echo "$SCRIPTS"
```

Use the output path as `$SCRIPTS` for all script commands below.

## Workflow

Read `${CLAUDE_SKILL_DIR}/references/workflow.md` now, before step 1. Steps 1–8 and 10 run its sections by name (bold), with: `<memory-key>` = `PR-$ARGUMENTS`, `<memory-type>` = `review`, `<report-prefix>` = `review`, `<scope>` = `PR #$ARGUMENTS`.

### 1–7. Shared steps

Run these sections of the workflow reference, in this order:

1. **Gather Project Context**
2. **Load Mandatory References** — from the lessons, identify which are relevant to the PR's changed files (by category) and use them as mandatory checkpoints
3. **Collect PR Data** for PR #$ARGUMENTS
4. **Analyze** (execute BEFORE generating any output), applying the **Diff Reading Rules**
5. **Evaluate Existing Comments**
6. **Memory — Load** (execute AFTER analysis, BEFORE generating output)
7. **Memory — Reconcile** (only if review-state.md existed)

### 8. Verify Findings (kill false positives)

Run **Verify Findings**. It applies to findings from **your own analysis** (step 4) — not to the incoming review comments from step 5, which are judged by their own valid / partially valid / not applicable rubric. Only surviving findings become tasks.

### 9. Generate Output

```bash
N=$(bash $SCRIPTS/review/memory-manager.sh next-number "PR-$ARGUMENTS" "review")
```

Save to: `{project_root}/memories/reviews/PR-{$ARGUMENTS}/review-{N}.md`

**Valid comments → Tasks** (markers: `${CLAUDE_SKILL_DIR}/references/output-vocabulary.md`):

```
## Tasks — PR #$ARGUMENTS

### ✗ Critical
- [ ] `file:line` — Description (by @author) — violates `docs/lessons/.../NNN-slug.md`

### ! Important
- [ ] `file:line` — Description

### Minor / Suggestion
- [ ] `file:line` — Description
```

**Non-applicable comments → responses:**

Save to: `{project_root}/memories/reviews/PR-{$ARGUMENTS}/review-{N}-responses.md`
- **For humans**: friendly, modest, justified with code references
- **For AIs**: direct, no fluff

**Reconciliation (only for subsequent reviews):** append the **Reconciliation Section**.

**Final Summary (always include):**
- Total comments analyzed
- Tasks vs. responses count
- **Own findings verified: X kept, Y refuted by `dtk-review-verifier`**
- Lessons that applied (**file paths**)
- ADRs that were relevant
- Overall: ✓ Approve | ! Approve with Comments | ✗ Request Changes

### 10. Memory — Save (execute AFTER generating output)

Run **Memory — Save**.

## Common Mistakes

The shared ones (diff lines, memory order, decided items, refuted verdicts) are in the workflow reference. Specific to this skill:

| Mistake | Fix |
|---------|-----|
| Creating responses file at project root | Save to `memories/reviews/PR-{}/` directory |
| Turning unverified findings into tasks | Run step 8 first — don't fix a bug that isn't there |
| Verifying the incoming reviewer comments | Step 8 covers your own findings only |
