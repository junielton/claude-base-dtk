---
name: review-peer
description: "Use when reviewing a teammate's pull request, providing peer feedback on someone else's PR, or when asked to review a PR you didn't author."
---

# Peer Review: PR #$ARGUMENTS

## Overview

Reviews someone else's PR with constructive, GitHub-ready feedback. Provides blocking/non-blocking issues and questions for the author. Features persistent memory shared with `/review` and `/review-local`.

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

Read every lesson — each is a mandatory checkpoint.

### 3. Collect Data (GitHub MCP)

Use `git_owner`/`git_repo` explicitly in ALL GitHub MCP calls.

1. Fetch the **full diff** of PR #$ARGUMENTS
2. Collect **all review comments**, grouped by author
3. Identify which files/lines each comment references

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

### 5. Evaluate Existing Comments

Priority order:
1. **Tech lead** → highest priority
2. **Other humans** → normal priority
3. **Copilot / AIs** → only if relevant

For each comment: locate code, evaluate as **valid** / **partially valid** / **not applicable**, justify with reference to actual code.

### 6. Memory — Load (execute AFTER analysis, BEFORE generating output)

**IMPORTANT: Do NOT read memory before completing the analysis. Prevents bias.**

```bash
bash $SCRIPTS/review/memory-manager.sh init "PR-$ARGUMENTS"
```

- If `is_first_review` is true → skip reconciliation
- If false → read state and reconcile

### 7. Memory — Reconcile (only if review-state.md existed)

**For each finding from your fresh analysis:**
- Matches **Resolved Item** → verify fix still in place; if regressed, reopen
- Matches **Decision** → respect it, do NOT re-raise
- Matches **Open Item** → mark "still pending"
- Not in state → mark "new in this review"

**For each Open Item from state NOT in fresh analysis:**
- Code in that area changed → likely resolved
- Code unchanged → keep as Open

**Peer review specifics:**
- Check if feedback from previous peer reviews was implemented in new commits
- If implemented → move to Resolved with "implemented since peer-review-N"
- If not → keep as Open

### 8. Generate Output

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

**Reconciliation (only for subsequent reviews)** — append after "Lessons Applied":

```
---

## Reconciliation with Previous Reviews

### Resolved since last review
- `file:line` — Description (was: peer-review-N, now: resolved)

### Still pending
- `file:line` — Description (since peer-review-N)

### New in this review
- `file:line` — Description

### Previous decisions respected
- `file:line` — "Out of scope" (decided in review-N)
```

**Final Summary** (always include):
- Total comments analyzed from other reviewers
- How many resulted in agreement vs. disagreement
- Lessons Learned that applied (list which ones)
- Your recommendation with justification

### 9. Memory — Save (execute AFTER generating output)

Update (or create) `review-state.md`. If already exists from `/review` or `/review-local`, **merge** — do not overwrite.

Get the template structure:
```bash
bash $SCRIPTS/review/memory-manager.sh template "PR-$ARGUMENTS" "peer-review"
```

Fill in the template with actual data from the analysis (replace placeholders with real values). If `review-state.md` already exists from `/review` or `/review-local`, **merge** — do not overwrite. Then save:
```bash
echo "<completed state content>" | bash $SCRIPTS/review/memory-manager.sh save-state "PR-$ARGUMENTS"
```

## Diff Reading Rules (CRITICAL)

- **Lines starting with `+`** = NEW code → ANALYZE THIS
- **Lines starting with `-`** = DELETED code → IGNORE
- **Lines with no prefix** = CONTEXT only → DO NOT report issues unless new code directly impacts it
- **When in doubt whether a line was changed** → assume NOT changed, skip it

## Tone & Perspective

Feedback should be:
- **English** — ready to post on GitHub as-is
- **Constructive** — suggest improvements, don't just point out flaws
- **Humble when uncertain** — ask genuine questions instead of assuming something is wrong
- **Specific** — always reference file, line, and code snippet

## Severity Definitions

- **🔴 Blocking** — must be fixed before merge (bugs, security issues, breaking changes)
- **🟡 Non-blocking** — improvement opportunity, does not block merge
- **💬 Questions** — genuine clarification requests for the author

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Reporting issues on deleted (`-`) lines | Only analyze added (`+`) lines |
| Re-raising decided items | Check memory state — respect previous decisions |
| Assuming something is wrong | Ask a question when uncertain |
| Vague feedback without code references | Always reference file, line, and snippet |
| Overwriting shared review-state.md | Merge with existing state, never overwrite |
