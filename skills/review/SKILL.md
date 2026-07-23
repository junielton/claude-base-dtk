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

### 1. Gather Project Context

```bash
bash $SCRIPTS/review/project-context.sh
```

Extract `git_owner`, `git_repo`, and `project_root` from the JSON output. Use these values explicitly in ALL GitHub MCP calls.

### 2. Load Mandatory References

- Read `CLAUDE.md` — project conventions and architecture
- Read `docs/conventions.md` — project-specific conventions (if exists)
- Read `docs/adrs/index.md` — architectural decisions that may apply
- Load all lessons:

```bash
bash $SCRIPTS/review/lessons-loader.sh --content
```

From the lessons, identify which are relevant to the PR's changed files (by category) and use them as mandatory checkpoints.

### 3. Collect Data (GitHub MCP)

1. Fetch the **full diff** of PR #$ARGUMENTS from `{git_owner}/{git_repo}`
2. Collect **all review comments**, grouped by author
3. Identify which files/lines each comment references

### 4. Analyze (execute BEFORE generating any output)

**Pass 1 — Map Changes:** List ALL changed files and their added lines (`+` only).

**Pass 2 — Understand Context:** For each changed block: what class/method, what it's trying to accomplish.

**Pass 3 — Check Against Lessons Learned:** For each change, verify if any lesson applies. **Reference the specific file path**:
Example: "Violates `docs/lessons/security/001-sql-injection-db-raw.md` — using DB::raw with interpolation"

**Pass 4 — General Analysis:** Evaluate each `+` line:
- **Logical correctness**: does the code do what it should?
- **Project standards**: follows CLAUDE.md conventions?
- **Security**: injection, mass assignment, auth gaps, data exposure
- **Performance**: N+1, missing eager loading, missing cache
- **Testability**: coverage exists or needed?
- **Side effects**: could it break something?

### 5. Evaluate Review Comments

Priority: @human (tech lead) → other humans → Copilot/AIs (only if relevant).

For each comment: locate code, evaluate as valid / partially valid / not applicable, justify.

### 6. Memory — Load (execute AFTER analysis, BEFORE generating output)

**IMPORTANT: Do NOT read memory before completing the analysis. Prevents bias.**

```bash
bash $SCRIPTS/review/memory-manager.sh init "PR-$ARGUMENTS"
```

- If `is_first_review` is true → skip reconciliation
- If false → read state and reconcile

### 7. Memory — Reconcile (only if review-state.md existed)

- Matches **Resolved Item** → verify fix still in place
- Matches **Decision** → respect it, do NOT re-raise
- Matches **Open Item** → mark "still pending"
- Not in state → mark "new in this review"

### 8. Verify Findings (kill false positives)

**Execute AFTER reconciliation, BEFORE generating output.** Applies to findings from **your own analysis** (step 4) — not to the incoming review comments from step 5, which are judged by their own valid / partially valid / not applicable rubric.

For each candidate finding, dispatch the `dtk-review-verifier` subagent (Task tool, `subagent_type: dtk-review-verifier`) with:

```
severity:  blocking | non-blocking | question
location:  file:line
claim:     <the one-line assertion you want to turn into a task>
reasoning: <why you believe it>
scope:     PR #$ARGUMENTS
```

Map your buckets to the severities the verifier expects: 🔴 Critical → `blocking`, 🟡 Important → `non-blocking`, 🟢 Minor/Suggestion → `non-blocking`.

Rules:

- **Dispatch all verifications in one batch** — they are independent, so issue the Task calls in a single turn.
- **Drop every finding returned as `refuted`.** Do not re-argue the verdict.
- If it returns `suggested-severity`, move the finding to that bucket before writing it as a task.
- You are the orchestrator; the verifier cannot spawn its own subagents.

Only surviving findings become tasks. Record the verified/refuted counts for the Final Summary.

### 9. Generate Output

```bash
N=$(bash $SCRIPTS/review/memory-manager.sh next-number "PR-$ARGUMENTS" "review")
```

Save to: `{project_root}/memories/reviews/PR-{$ARGUMENTS}/review-{N}.md`

**Valid comments → Tasks:**

```
## Tasks — PR #$ARGUMENTS

### 🔴 Critical
- [ ] `file:line` — Description (by @author) — violates `docs/lessons/.../NNN-slug.md`

### 🟡 Important
- [ ] `file:line` — Description

### 🟢 Minor / Suggestion
- [ ] `file:line` — Description
```

**Non-applicable comments → responses:**

Save to: `{project_root}/memories/reviews/PR-{$ARGUMENTS}/review-{N}-responses.md`
- **For humans**: friendly, modest, justified with code references
- **For AIs**: direct, no fluff

**Reconciliation (only for subsequent reviews):**

```
## Reconciliation with Previous Reviews

### Resolved since last review
- `file:line` — Description (was: review-N, now: resolved)

### Still pending
- `file:line` — Description (since review-N)

### New in this review
- `file:line` — Description
```

**Final Summary (always include):**
- Total comments analyzed
- Tasks vs. responses count
- **Own findings verified: X kept, Y refuted by `dtk-review-verifier`**
- Lessons that applied (**file paths**)
- ADRs that were relevant
- Overall: ✅ Approve | ⚠️ Approve with Comments | ❌ Request Changes

### 10. Memory — Save (execute AFTER generating output)

Get the template structure:
```bash
bash $SCRIPTS/review/memory-manager.sh template "PR-$ARGUMENTS" "review"
```

Fill in the template with actual data from the analysis (replace placeholders with real values), then save:
```bash
echo "<completed state content>" | bash $SCRIPTS/review/memory-manager.sh save-state "PR-$ARGUMENTS"
```

## Diff Reading Rules (CRITICAL)

- **`+` lines** = NEW code → ANALYZE THIS
- **`-` lines** = DELETED → IGNORE
- **No prefix** = CONTEXT → skip unless directly impacted
- **When in doubt** → assume NOT changed, skip

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Reporting issues on deleted (`-`) lines | Only analyze added (`+`) lines |
| Re-raising decided items | Check memory state — respect previous decisions |
| Reading memory before analysis | Load memory AFTER analysis to prevent bias |
| Missing lesson references | Always reference specific `docs/lessons/` file paths |
| Creating responses file at project root | Save to `memories/reviews/PR-{}/` directory |
| Turning unverified findings into tasks | Run step 8 first — don't fix a bug that isn't there |
| Verifying the incoming reviewer comments | Step 8 covers your own findings only |
