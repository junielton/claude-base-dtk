---
name: review-local
description: "Local code review — reviews all changes on current branch vs base branch (including uncommitted). Features persistent memory: tracks what was found, resolved, and decided across multiple review rounds. Use before opening a PR or pushing code."
---

# Local Review: $ARGUMENTS

Review all changes on the current branch compared to a base branch.

- **Base branch**: `$ARGUMENTS` (default: auto-detected by project-context script)
- **Scope**: All changes from the current branch vs the base branch, including uncommitted changes

## Step 0 — Gather Project Context

Run the shared scripts to get project identity and lessons:

```bash
# Get project context (owner, repo, branch, base branch)
CONTEXT=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/project-context.sh" --base-branch "$ARGUMENTS")
echo "$CONTEXT"

# List all available lessons
bash "${CLAUDE_PLUGIN_ROOT}/scripts/lessons-loader.sh" --json
```

Extract `git_owner`, `git_repo`, `current_branch`, `base_branch`, and `project_root` from the JSON output.

## Mandatory References

Consult the project's CLAUDE.md, specifically:

- **Code Conventions** — to validate patterns and standards
- **Architecture** — to understand where each change fits

Also load ALL lesson files using the lessons-loader script:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/lessons-loader.sh" --content
```

Read every lesson — each is a mandatory checkpoint during analysis.

## Data Collection

1. Determine the base branch from the context script output
2. Get the full diff: `git diff <base-branch>...HEAD` (committed changes on this branch)
3. Get uncommitted changes: `git diff` (unstaged) and `git diff --cached` (staged)
4. Combine all diffs for a complete picture of changes on this branch

## Analysis Methodology (execute BEFORE generating any output)

### Pass 1 — Map Changes

List ALL changed files and their added lines (`+` only). Format:

- `file.php`: lines 12, 45-52, 89

### Pass 2 — Understand Context

For each changed block, identify:

- What class/method it belongs to
- What it's trying to accomplish

### Pass 3 — Check Against Lessons Learned

For each change, verify if any Lesson Learned applies.
This is mandatory and must be explicit in the output.

### Pass 4 — General Analysis

Evaluate each `+` line against:

- **Logical correctness**: does the code do what it should?
- **Project standards**: follows conventions from CLAUDE.md?
- **Security**: injection risks, mass assignment, missing auth checks, exposed data
- **Performance**: N+1 queries, missing eager loading, missing cache
- **Testability**: do the changes have test coverage? Should they?
- **Side effects**: could the change break something elsewhere?

## Diff Reading Rules (CRITICAL)

- **Lines starting with `+`** = NEW code → ANALYZE THIS
- **Lines starting with `-`** = DELETED code → IGNORE (already removed)
- **Lines with no prefix** = CONTEXT only → DO NOT report issues unless new code directly impacts it
- **NEVER report issues on context lines** unless directly affected by additions
- **When in doubt whether a line was changed** → assume it was NOT changed, skip it

## Memory Phase — Load (execute AFTER analysis, BEFORE generating output)

**IMPORTANT: Do NOT read memory before completing the analysis above. This prevents bias from previous reviews.**

**All review output files are saved in the project root's `memories/reviews/` directory.**

```bash
# Initialize memory for this branch
MEMORY=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/memory-manager.sh" init "$CURRENT_BRANCH")
echo "$MEMORY"
```

- If `is_first_review` is true → skip reconciliation
- If `is_first_review` is false → read the state from stderr output and reconcile

## Memory Phase — Reconcile (only if review-state.md existed)

Compare your fresh findings with the state from previous reviews:

**For each finding from your fresh analysis:**

- If it matches a **Resolved Item** in state → verify the fix is still in place; if code regressed, reopen it
- If it matches a **Decision** (e.g., "out of scope") → respect the decision, do NOT re-raise
- If it matches an **Open Item** → mark as "still pending"
- If it's not in the state at all → mark as "new in this review"

**For each Open Item from the state NOT found in your fresh analysis:**

- If the code in that area changed → likely resolved, move to Resolved
- If the code is unchanged → may have been missed; keep as Open

**First review (no state):** skip this phase entirely.

## Output

```bash
# Get next review number
N=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/memory-manager.sh" next-number "$CURRENT_BRANCH" "review")
```

Save the output to: `{project_root}/memories/reviews/{branch-name}/review-{N}.md`

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

### Reconciliation with Previous Reviews (only for subsequent reviews)

If this is a subsequent review, append:

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

### Always Include: Final Summary

- Total files analyzed
- Total issues found by severity
- Lessons Learned that applied (list which ones)
- Overall assessment: Ready to commit/push | Needs fixes first

## Memory Phase — Save (execute AFTER generating output)

Update (or create) `review-state.md`:

```bash
cat <<'STATE' | bash "${CLAUDE_PLUGIN_ROOT}/scripts/memory-manager.sh" save-state "$CURRENT_BRANCH"
# Review State — {branch-name}

## Metadata
- Identifier: {branch-name}
- Branch: {branch-name}
- Reviews: {count} (last: YYYY-MM-DD)
- Types: review

## Decisions
- `file:line` — Description of decision (review-N)

## Coverage
- Files analyzed: file1, file2, ...
- Key methods: Class::method(), ...

## Open Items
- [ ] `file:line` — Description (raised review-N, still open review-M)

## Resolved Items
- [x] `file:line` — Description (raised review-N, resolved review-M)

## Notes
- Observations not tied to specific code lines
STATE
```
