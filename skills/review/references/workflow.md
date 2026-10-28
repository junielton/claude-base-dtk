# Review core — shared workflow

Shared by `/dtk:review`, `/dtk:review-local` and `/dtk:review-peer`. Each skill keeps its own
numbered steps and runs the sections below where its workflow names them. Before it sends you
here, the skill states the values for the placeholders in angle brackets:

- `<memory-key>` — the memory folder key (`PR-<n>` or the current branch)
- `<memory-type>` — the template type passed to `memory-manager.sh template`
- `<report-prefix>` — the report file prefix (`review`, `peer-review`)
- `<scope>` — the scope line sent to `dtk-review-verifier`

`$SCRIPTS` is the path the skill's Step 0 resolved.

## Gather Project Context

```bash
bash $SCRIPTS/review/project-context.sh
```

`/review-local` passes `--base-branch "$ARGUMENTS"` and also extracts `current_branch` and `base_branch`.

Extract `git_owner`, `git_repo`, and `project_root` from the JSON output. Use these values explicitly in ALL GitHub MCP calls.

## Load Mandatory References

- Read `CLAUDE.md` — project conventions and architecture
- Read `docs/conventions.md` — project-specific conventions (if exists)
- Read `docs/adrs/index.md` — architectural decisions that may apply
- Load all lessons:

```bash
bash $SCRIPTS/review/lessons-loader.sh --content
```

Read every lesson — each is a mandatory checkpoint during analysis.

**Stack references (optional).** The checklist in **Analyze** is stack-neutral. Stack-specific checks live in `stacks/` next to this file and are loaded only when the stack is detected:

- `composer.json` exists at the project root → read `stacks/laravel.md` from the directory you read this file from, not the project root (Eloquent, Livewire, Laravel framework checks)

Another stack gets its own `stacks/<stack>.md` with a one-line detection rule added to this list; none is mandatory, and a project with no matching file uses the neutral checklist alone.

## Collect PR Data (GitHub MCP)

Use `git_owner`/`git_repo` explicitly in ALL GitHub MCP calls.

1. Fetch the **full diff** of the PR from `{git_owner}/{git_repo}`
2. Collect **all review comments**, grouped by author
3. Identify which files/lines each comment references

## Evaluate Existing Comments

Priority order:
1. **Tech lead** → highest priority
2. **Other humans** → normal priority
3. **Copilot / AIs** → only if relevant

For each comment: locate code, evaluate as **valid** / **partially valid** / **not applicable**, justify with reference to actual code.

## Analyze (execute BEFORE generating any output)

**Pass 1 — Map Changes:** List ALL changed files and their added lines (`+` only).

**Pass 2 — Understand Context:** For each changed block: what class/method, what it's trying to accomplish.

**Pass 3 — Check Against Lessons Learned:** For each change, verify if any lesson applies. Mandatory and explicit in output. **Reference the specific file path**:
Example: "Violates `docs/lessons/security/001-sql-injection-raw-query.md` — raw SQL built by interpolating request input"

**Pass 4 — General Analysis:** Evaluate each `+` line against (plus the checks of any stack reference loaded above):
- **Logical correctness**: does the code do what it should?
- **Project standards**: follows conventions from CLAUDE.md?
- **Security**: injection risks, input used before it is validated, unfiltered input written to models or records (mass assignment), missing auth checks, exposed data
- **Performance**: queries or remote calls inside loops (N+1), related data not fetched in one batch, missing cache
- **Testability**: do the changes have test coverage? Should they?
- **Side effects**: could the change break something elsewhere?

## Memory — Load (execute AFTER analysis, BEFORE generating output)

**IMPORTANT: Do NOT read memory before completing the analysis. Prevents bias.**

```bash
bash $SCRIPTS/review/memory-manager.sh init "<memory-key>"
```

- If `is_first_review` is true → skip reconciliation
- If false → read the state and reconcile

## Memory — Reconcile (only if review-state.md existed)

**For each finding from your fresh analysis:**
- Matches **Resolved Item** → verify fix still in place; if regressed, reopen
- Matches **Decision** (e.g., "out of scope") → respect it, do NOT re-raise
- Matches **Open Item** → mark "still pending"
- Not in state → mark "new in this review"

**For each Open Item from state NOT in fresh analysis:**
- Code in that area changed → likely resolved, move to Resolved
- Code unchanged → may have been missed; keep as Open

**First review (no state):** skip this phase entirely.

## Verify Findings (kill false positives)

**Execute AFTER reconciliation, BEFORE generating output.** Verifying last avoids spending subagents on findings that memory already resolved or decided.

For each candidate finding, dispatch the `dtk-review-verifier` subagent (Task tool, `subagent_type: dtk-review-verifier`) with:

```
severity:  blocking | non-blocking | question
location:  file:line
claim:     <the one-line assertion you want to report>
reasoning: <why you believe it>
scope:     <scope>
```

In `/review` and `/review-local`, map your buckets to the severities the verifier expects (`/review-peer` states its own one-to-one mapping): Critical → `blocking`, Important → `non-blocking`, Minor/Suggestion → `non-blocking`.

Rules:

- **Dispatch all verifications in one batch** — they are independent, so issue the Task calls in a single turn.
- **Drop every finding returned as `refuted`.** Do not re-argue the verdict.
- If it returns `suggested-severity`, move the finding to that bucket before reporting it.
- You are the orchestrator; the verifier cannot spawn its own subagents.

Only surviving findings reach the output. Record the verified/refuted counts for the Final Summary.

## Reconciliation Section (only for subsequent reviews)

```
## Reconciliation with Previous Reviews

### Resolved since last review
- `file:line` — Description (was: <report-prefix>-N, now: resolved)

### Still pending
- `file:line` — Description (since <report-prefix>-N)

### New in this review
- `file:line` — Description

### Previous decisions respected
- `file:line` — "Out of scope" (decided in review-N)
```

## Memory — Save (execute AFTER generating output)

Get the template structure:
```bash
bash $SCRIPTS/review/memory-manager.sh template "<memory-key>" "<memory-type>"
```

Fill in the template with actual data from the analysis (replace placeholders with real values). If `review-state.md` already exists from `/review` or `/review-local`, **merge** — do not overwrite. Then save:
```bash
echo "<completed state content>" | bash $SCRIPTS/review/memory-manager.sh save-state "<memory-key>"
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
| Reviewing context lines as new code | Only report issues on `+` lines |
| Re-raising decided items | Check memory state — respect previous decisions |
| Reading memory before analysis | Load memory AFTER analysis to prevent bias |
| Missing lesson references | Always reference specific `docs/lessons/` file paths |
| Overwriting shared review-state.md | Merge with existing state, never overwrite |
| Re-arguing a `refuted` verdict | Drop it. The verifier read the actual code |
