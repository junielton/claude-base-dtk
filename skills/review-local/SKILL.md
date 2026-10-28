---
name: review-local
description: "Use when reviewing local changes before opening a PR, before pushing code, or when you want to check all branch changes against the base branch including uncommitted work."
---

# Local Review: $ARGUMENTS

## Overview

Reviews all changes on the current branch compared to a base branch (including uncommitted changes). Every finding is put through the `dtk-review-verifier` subagent, which tries to disprove it before it is reported. Features persistent memory that tracks what was found, resolved, and decided across multiple review rounds. Shared with `/review` and `/review-peer`.

- **Base branch**: `$ARGUMENTS` (default: auto-detected by project-context script)
- **Scope**: All changes from the current branch vs the base branch, including uncommitted changes

## When to Use

- Before opening a PR — final check
- Before pushing code to remote
- After fixing issues from a previous review round
- Want to verify branch changes against base

## When NOT to Use

- Reviewing a PR already on GitHub (use `/review` for own, `/review-peer` for others)
- No changes on the current branch

## Step 0: Resolve Scripts

```bash
# resolver idiom: docs/conventions/script-resolution.md
SCRIPTS="${CLAUDE_PLUGIN_ROOT}/scripts"; [ -d "$SCRIPTS" ] || echo "dtk: scripts dir not found: $SCRIPTS" >&2; echo "$SCRIPTS"
```

Use the output path as `$SCRIPTS` for all script commands below.

## Workflow

Read `${CLAUDE_SKILL_DIR}/../review/references/workflow.md` now, before step 1. Steps 1, 2, 4–7 and 9 run its sections by name (bold), with: `<memory-key>` = `$CURRENT_BRANCH`, `<memory-type>` = `review-local`, `<report-prefix>` = `review`, `<scope>` = `local branch <current-branch> vs <base-branch>, including uncommitted changes`.

### 1–6. Shared steps

Run these, in this order (bold names are sections of the workflow reference):

1. **Gather Project Context** with `--base-branch "$ARGUMENTS"`; also extract `current_branch` and `base_branch`
2. **Load Mandatory References**
3. Collect Data:
   1. Determine the base branch from the context script output
   2. Get the full diff: `git diff <base-branch>...HEAD` (committed changes on this branch)
   3. Get uncommitted changes: `git diff` (unstaged) and `git diff --cached` (staged)
   4. Combine all diffs for a complete picture of changes on this branch
4. **Analyze** (execute BEFORE generating any output), applying the **Diff Reading Rules**
5. **Memory — Load** (execute AFTER analysis, BEFORE generating output)
6. **Memory — Reconcile** (only if review-state.md existed)

### 7. Verify Findings (kill false positives)

Run **Verify Findings**. Tell the verifier the scope includes uncommitted work, so it compares against the working tree and not just `HEAD`.

### 8. Generate Output

```bash
N=$(bash $SCRIPTS/review/memory-manager.sh next-number "$CURRENT_BRANCH" "review")
```

Save to: `{project_root}/memories/reviews/{branch-name}/review-{N}.md`

```
## Local Review — <current-branch> vs <base-branch>

### Files Changed
- List of all changed files with line counts

### Issues Found

#### Critical
- [ ] `file:line` — Description of the issue

#### Important
- [ ] `file:line` — Description of the issue

#### Minor / Suggestion
- [ ] `file:line` — Description of the improvement
```

**Reconciliation (only for subsequent reviews):** append the **Reconciliation Section**.

**Final Summary (always include):**
- Total files analyzed
- Total issues found by severity
- **Findings verified: X kept, Y refuted by `dtk-review-verifier`**
- Lessons Learned that applied (list which ones)
- Overall assessment: Ready to commit/push | Needs fixes first

### 9. Memory — Save (execute AFTER generating output)

Run **Memory — Save**.

## Common Mistakes

The shared ones (diff lines, memory order, decided items, refuted verdicts) are in the workflow reference. Specific to this skill:

| Mistake | Fix |
|---------|-----|
| Forgetting uncommitted changes | Combine `git diff base...HEAD` + `git diff` + `git diff --cached` |
| Reporting findings without verification | Run step 7 — a false positive here becomes wasted work before the PR |
