---
name: review
description: "PR review (your own PR) — analyzes diffs, checks against project knowledge base (ADRs, lessons), evaluates existing comments, and outputs categorized tasks. Features persistent memory shared with review-local and review-peer. Use when reviewing your own pull request."
---

# PR Review: $ARGUMENTS

## Step 0 — Gather Project Context

```bash
# Get project context
CONTEXT=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/project-context.sh")
echo "$CONTEXT"

# List all available lessons
bash "${CLAUDE_PLUGIN_ROOT}/scripts/lessons-loader.sh" --json
```

Extract `git_owner`, `git_repo`, and `project_root` from the JSON output.

## Repository Context

- **Owner**: (from project-context output)
- **Repo**: (from project-context output)
- **PR**: #$ARGUMENTS

Use these values explicitly in ALL GitHub MCP calls. Do not attempt to discover the repository automatically.

## Mandatory References

Before analyzing, load the project's knowledge base:

1. Read `CLAUDE.md` — project conventions and architecture
2. Read `docs/adrs/index.md` — architectural decisions that may apply
3. Load all lessons:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/lessons-loader.sh" --content
```

From the lessons, identify which are relevant to the PR's changed files (by category) and use them as mandatory checkpoints.

## Data Collection (GitHub MCP)

1. Fetch the **full diff** of PR #$ARGUMENTS from `{git_owner}/{git_repo}`
2. Collect **all review comments**, grouped by author
3. Identify which files/lines each comment references

## Analysis Methodology (execute BEFORE generating any output)

### Pass 1 — Map Changes

List ALL changed files and their added lines (`+` only):

- `file.php`: lines 12, 45-52, 89

### Pass 2 — Understand Context

For each changed block: what class/method, what it's trying to accomplish.

### Pass 3 — Check Against Lessons Learned

For each change, verify if any lesson applies. **Reference the specific file path**:

Example: "⚠️ Violates `docs/lessons/security/001-sql-injection-db-raw.md` — using DB::raw with interpolation"

### Pass 4 — General Analysis

Evaluate each `+` line:

- **Logical correctness**: does the code do what it should?
- **Project standards**: follows CLAUDE.md conventions?
- **Security**: injection, mass assignment, auth gaps, data exposure
- **Performance**: N+1, missing eager loading, missing cache
- **Testability**: coverage exists or needed?
- **Side effects**: could it break something?

## Diff Reading Rules (CRITICAL)

- **`+` lines** = NEW code → ANALYZE THIS
- **`-` lines** = DELETED → IGNORE
- **No prefix** = CONTEXT → skip unless directly impacted
- **When in doubt** → assume NOT changed, skip

## Review Comments Analysis

Priority: @human (tech lead) → other humans → Copilot/AIs (only if relevant).

For each comment: locate code, evaluate as valid / partially valid / not applicable, justify.

## Memory Phase — Load (execute AFTER analysis, BEFORE generating output)

**IMPORTANT: Do NOT read memory before completing the analysis. Prevents bias.**

```bash
MEMORY=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/memory-manager.sh" init "PR-$ARGUMENTS")
echo "$MEMORY"
```

- If `is_first_review` is true → skip reconciliation
- If false → read state and reconcile

## Memory Phase — Reconcile (only if review-state.md existed)

Compare fresh findings with previous state:

- Matches **Resolved Item** → verify fix still in place
- Matches **Decision** → respect it, do NOT re-raise
- Matches **Open Item** → mark "still pending"
- Not in state → mark "new in this review"

## Output

```bash
N=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/memory-manager.sh" next-number "PR-$ARGUMENTS" "review")
```

Save to: `{project_root}/memories/reviews/PR-{$ARGUMENTS}/review-{N}.md`

### Valid comments → Tasks

```
## Tasks — PR #$ARGUMENTS

### 🔴 Critical
- [ ] `file:line` — Description (by @author) — violates `docs/lessons/.../NNN-slug.md`

### 🟡 Important
- [ ] `file:line` — Description

### 🟢 Minor / Suggestion
- [ ] `file:line` — Description
```

### Non-applicable comments → pr-review-responses.md

Create `pr-review-responses.md` at project root:
- **For humans**: friendly, modest, justified with code references
- **For AIs**: direct, no fluff

### Reconciliation (only for subsequent reviews)

```
## Reconciliation with Previous Reviews

### Resolved since last review
- `file:line` — Description (was: review-N, now: resolved)

### Still pending
- `file:line` — Description (since review-N)

### New in this review
- `file:line` — Description
```

### Final Summary (always include)

- Total comments analyzed
- Tasks vs. responses count
- Lessons that applied (**file paths**)
- ADRs that were relevant
- Overall: ✅ Approve | ⚠️ Approve with Comments | ❌ Request Changes

## Memory Phase — Save (execute AFTER generating output)

```bash
cat <<'STATE' | bash "${CLAUDE_PLUGIN_ROOT}/scripts/memory-manager.sh" save-state "PR-$ARGUMENTS"
# Review State — PR #$ARGUMENTS

## Metadata
- Identifier: PR #$ARGUMENTS
- Branch: {branch name}
- Reviews: {count} (last: YYYY-MM-DD)
- Types: review

## Decisions
## Coverage
## Open Items
## Resolved Items
## Notes
STATE
```
