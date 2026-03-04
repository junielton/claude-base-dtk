---
name: review-peer
description: "Peer PR review — reviews someone else's PR with constructive, GitHub-ready feedback. Features persistent memory shared with review/review-local. Outputs blocking/non-blocking issues and questions. Use when reviewing a teammate's pull request."
---

# Peer Review: PR #$ARGUMENTS

You are reviewing someone else's PR. Your goal is to provide constructive feedback for the author — not tasks for yourself.

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

Use these values explicitly in ALL GitHub MCP calls.

## Mandatory References

Consult the project's CLAUDE.md, specifically:

- **Code Conventions** — to validate patterns and standards
- **Architecture** — to understand where each change fits

Also load ALL lesson files:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/lessons-loader.sh" --content
```

Read every lesson — each is a mandatory checkpoint.

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

For each change, verify if any Lesson Learned applies. Mandatory and explicit in output.

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
- **Lines starting with `-`** = DELETED code → IGNORE
- **Lines with no prefix** = CONTEXT only → DO NOT report issues unless new code directly impacts it
- **When in doubt whether a line was changed** → assume NOT changed, skip it

## Tone & Perspective

You are an **external reviewer**, not the author. Your feedback should be:

- **English** — ready to post on GitHub as-is
- **Constructive** — suggest improvements, don't just point out flaws
- **Humble when uncertain** — ask genuine questions instead of assuming something is wrong
- **Specific** — always reference file, line, and code snippet

## Existing Review Comments

Priority order:

1. **Tech lead** → highest priority
2. **Other humans** → normal priority
3. **Copilot / AIs** → only if relevant

For each comment: locate code, evaluate as **valid** / **partially valid** / **not applicable**, justify with reference to actual code.

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

## Output

```bash
N=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/memory-manager.sh" next-number "PR-$ARGUMENTS" "peer-review")
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

### Reconciliation (only for subsequent reviews)

Append after "Lessons Applied":

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

### Severity Definitions

- **🔴 Blocking** — must be fixed before merge (bugs, security issues, breaking changes)
- **🟡 Non-blocking** — improvement opportunity, does not block merge
- **💬 Questions** — genuine clarification requests for the author

### Final Summary

- Total comments analyzed from other reviewers
- How many resulted in agreement vs. disagreement
- Lessons Learned that applied (list which ones)
- Your recommendation with justification

## Memory Phase — Save (execute AFTER generating output)

Update (or create) `review-state.md`. If already exists from `/review` or `/review-local`, **merge** — do not overwrite.

```bash
cat <<'STATE' | bash "${CLAUDE_PLUGIN_ROOT}/scripts/memory-manager.sh" save-state "PR-$ARGUMENTS"
# Review State — PR #$ARGUMENTS

## Metadata
- Identifier: PR #$ARGUMENTS
- Branch: {branch name from PR}
- Reviews: {count} (last: YYYY-MM-DD)
- Types: review, peer-review

## Decisions
- `file:line` — Description of decision (peer-review-N)

## Coverage
- Files analyzed: file1, file2, ...
- Key methods: Class::method(), ...

## Open Items
- [ ] `file:line` — Description (raised peer-review-N, still open peer-review-M)

## Resolved Items
- [x] `file:line` — Description (raised peer-review-N, resolved peer-review-M)

## Notes
- Observations not tied to specific code lines
STATE
```
