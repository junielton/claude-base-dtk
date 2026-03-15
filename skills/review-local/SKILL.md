---
name: review-local
description: "Use when reviewing local changes before opening a PR, before pushing code, or when you want to check all branch changes against the base branch including uncommitted work."
---

# Local Review: $ARGUMENTS

## Overview

Reviews all changes on the current branch compared to a base branch (including uncommitted changes). Features persistent memory that tracks what was found, resolved, and decided across multiple review rounds. Shared with `/review` and `/review-peer`.

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
SCRIPTS="bin/skill-scripts"; [ -d "$SCRIPTS" ] || SCRIPTS="${CLAUDE_PLUGIN_ROOT:-}/bin/skill-scripts"; [ -d "$SCRIPTS" ] || SCRIPTS=$(find ~/.claude/plugins -path "*/dtk/bin/skill-scripts" -maxdepth 5 2>/dev/null | head -1); echo "$SCRIPTS"
```

Use the output path as `$SCRIPTS` for all script commands below.

## Workflow

### 1. Gather Project Context

```bash
bash $SCRIPTS/review/project-context.sh --base-branch "$ARGUMENTS"
```

Extract `git_owner`, `git_repo`, `current_branch`, `base_branch`, and `project_root` from the JSON output.

### 2. Load Mandatory References

- Read `CLAUDE.md` — project conventions and architecture
- Read `docs/conventions.md` — project-specific conventions (if exists)
- Read `docs/adrs/index.md` — architectural decisions that may apply
- Load all lessons:

```bash
bash $SCRIPTS/review/lessons-loader.sh --content
```

Read every lesson — each is a mandatory checkpoint during analysis.

### 3. Collect Data

1. Determine the base branch from the context script output
2. Get the full diff: `git diff <base-branch>...HEAD` (committed changes on this branch)
3. Get uncommitted changes: `git diff` (unstaged) and `git diff --cached` (staged)
4. Combine all diffs for a complete picture of changes on this branch

### 4. Analyze (execute BEFORE generating any output)

**Pass 1 — Map Changes:** List ALL changed files and their added lines (`+` only).

**Pass 2 — Understand Context:** For each changed block: what class/method, what it's trying to accomplish.

**Pass 3 — Check Against Lessons Learned:** For each change, verify if any lesson applies. Mandatory and explicit in output.

**Pass 4 — General Analysis:** Evaluate each `+` line against:
- **Logical correctness**: does the code do what it should?
- **Project standards**: follows conventions from CLAUDE.md?
- **Security**: injection risks, mass assignment, missing auth checks, exposed data
- **Performance**: N+1 queries, missing eager loading, missing cache
- **Testability**: do the changes have test coverage? Should they?
- **Side effects**: could the change break something elsewhere?

### 5. Memory — Load (execute AFTER analysis, BEFORE generating output)

**IMPORTANT: Do NOT read memory before completing the analysis. Prevents bias.**

```bash
bash $SCRIPTS/review/memory-manager.sh init "$CURRENT_BRANCH"
```

- If `is_first_review` is true → skip reconciliation
- If false → read the state and reconcile

### 6. Memory — Reconcile (only if review-state.md existed)

**For each finding from your fresh analysis:**
- Matches **Resolved Item** → verify fix still in place; if regressed, reopen
- Matches **Decision** (e.g., "out of scope") → respect it, do NOT re-raise
- Matches **Open Item** → mark "still pending"
- Not in state → mark "new in this review"

**For each Open Item from state NOT in fresh analysis:**
- Code in that area changed → likely resolved, move to Resolved
- Code unchanged → may have been missed; keep as Open

**First review (no state):** skip this phase entirely.

### 7. Generate Output

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

**Reconciliation (only for subsequent reviews):**

```
## Reconciliation with Previous Reviews

### Resolved since last review
- `file:line` — Description (was: review-N, now: resolved)

### Still pending
- `file:line` — Description (since review-N)

### New in this review
- `file:line` — Description

### Previous decisions respected
- `file:line` — "Out of scope" (decided in review-N)
```

**Final Summary (always include):**
- Total files analyzed
- Total issues found by severity
- Lessons Learned that applied (list which ones)
- Overall assessment: Ready to commit/push | Needs fixes first

### 8. Memory — Save (execute AFTER generating output)

Get the template structure:
```bash
bash $SCRIPTS/review/memory-manager.sh template "$CURRENT_BRANCH" "review-local"
```

Fill in the template with actual data from the analysis (replace placeholders with real values), then save:
```bash
echo "<completed state content>" | bash $SCRIPTS/review/memory-manager.sh save-state "$CURRENT_BRANCH"
```

## Diff Reading Rules (CRITICAL)

- **Lines starting with `+`** = NEW code → ANALYZE THIS
- **Lines starting with `-`** = DELETED code → IGNORE (already removed)
- **Lines with no prefix** = CONTEXT only → DO NOT report issues unless new code directly impacts it
- **NEVER report issues on context lines** unless directly affected by additions
- **When in doubt whether a line was changed** → assume it was NOT changed, skip it

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Reporting issues on deleted (`-`) lines | Only analyze added (`+`) lines |
| Re-raising decided items | Check memory state — respect previous decisions |
| Reading memory before analysis | Load memory AFTER analysis to prevent bias |
| Forgetting uncommitted changes | Combine `git diff base...HEAD` + `git diff` + `git diff --cached` |
| Reviewing context lines as new code | Only report issues on `+` lines |
