---
name: learn-from-review
description: "Extracts actionable lessons from a finished code review and saves each as a file in docs/lessons/, with a lifecycle (candidate, active, retired) and an export of active lessons into REVIEW.md and .github/copilot-instructions.md so Copilot, CodeRabbit, Greptile and Claude review follow them too. Use after /dtk:review, /dtk:review-local or /dtk:review-peer, or when the user says 'save this lesson', 'learn from this review', 'remember this for future reviews', 'salva essa lição', 'aprende com essa review', 'guarda isso pras próximas reviews', or asks to promote, retire or re-export lessons. Do NOT use for architecture decisions (dtk:adr), for personal memory unrelated to code review, or for writing rules into CLAUDE.md."
---

# Extract Lessons from Code Review

Analyze the current code review session, extract actionable lessons, and persist each one as an individual file in `docs/lessons/{category}/`.

## Lifecycle

Each lesson's frontmatter carries `status` and `source` (written by `create-lesson.sh`):

| status | meaning | loaded into reviews | exported |
|---|---|---|---|
| `candidate` | learned from a teammate's PR (`source: peer`); awaits the user's approval | only with `lessons-loader.sh --include-candidates` | no |
| `active` | learned from the user's own review (`source: own`), or a promoted candidate | yes | yes |
| `retired` | proven wrong by review outcomes | never | no |

A lesson with no `status:` (written before the lifecycle) counts as `active`. To promote a candidate, change its `status: candidate` to `status: active`, then re-run the export (Step 5).

## Step 0: Resolve Scripts

```bash
SCRIPTS="bin/skill-scripts"; [ -d "$SCRIPTS" ] || SCRIPTS="${CLAUDE_PLUGIN_ROOT:-}/bin/skill-scripts"; [ -d "$SCRIPTS" ] || SCRIPTS=$(find ~/.claude/plugins -path "*/dtk/bin/skill-scripts" -maxdepth 5 2>/dev/null | head -1); echo "$SCRIPTS"
```

Use the output path as `$SCRIPTS` for all script commands below.

## Step 1: Analyze the Review

Examine the current conversation and identify lessons across these categories:

- **Security**: Vulnerabilities, injection risks, auth/authorization issues, data exposure
- **Code Patterns**: Anti-patterns found, better alternatives suggested, architectural improvements
- **QA**: Edge cases missed, validation gaps, error handling issues, test coverage blind spots
- **Performance**: N+1 queries, unnecessary loops, missing indexes, caching opportunities
- **Framework**: Framework-specific gotchas, best practices, lifecycle issues
- **Testing**: Test strategy issues, missing coverage patterns, test anti-patterns
- **Frontend**: UI/UX issues, accessibility, responsive design, component patterns

## Step 2: Format Each Lesson

For each lesson found, prepare it in this format:

```markdown
### [Short descriptive title]

**Category:** Security | Code Patterns | QA | Performance | Framework | Testing | Frontend
**Severity:** Critical | High | Medium | Low

**Rule:** [One clear, actionable sentence — what to always do or never do]

**Bad:**
```[lang]
// brief example of the wrong approach
```

**Good:**
```[lang]
// brief example of the correct approach
```

**Why:** [1-2 sentences explaining the risk or benefit]
```

## Step 3: Check for Duplicates

Before creating each lesson, check if a similar one already exists:

```bash
bash $SCRIPTS/lessons/create-lesson.sh \
  --category <category> --title "<title>" --severity <severity> --check-dup
```

- If output starts with `DUPLICATE:` — read the existing file and decide:
  - If the new version is more complete or accurate → delete the old file and create the new one
  - If they are equivalent → skip (do not create a duplicate)
- If output is `NO_DUPLICATE` → proceed to create

## Step 4: Persist Each Lesson

For each new lesson (that passed the duplicate check), create a file. Pass `--source peer` when the session was `/dtk:review-peer` (a teammate's PR), `--source own` for `/dtk:review` and `/dtk:review-local`:

```bash
echo '<lesson content in Step 2 format>' | bash $SCRIPTS/lessons/create-lesson.sh \
  --category <category> --title "<title>" --severity <severity> --source <own|peer>
```

The script will:
1. Create `docs/lessons/{category}/NNN-slug.md` with the content, under a frontmatter of `status` (`own` → `active`, `peer` → `candidate`) and `source`
2. Update `docs/lessons/index.md` with a new row in the correct category table

**Category directory mapping:**

| Category | Directory |
|----------|-----------|
| Security | `security` |
| Code Patterns | `code-patterns` |
| QA | `qa` |
| Performance | `performance` |
| Framework | `framework` |
| Testing | `testing` |
| Frontend | `frontend` |

## Step 5: Export Active Lessons

After writing the lessons, regenerate the copies other reviewers read:

```bash
node $SCRIPTS/lessons/export-lessons.mjs
```

It rewrites only the block between `<!-- dtk:lessons:start -->` and `<!-- dtk:lessons:end -->` in `REVIEW.md` and `.github/copilot-instructions.md` (creating them if absent), never text outside the markers; a second run changes nothing. Copilot reads only the first 4,000 characters of its file, so the export keeps that whole file ≤ 4,000 chars (`--copilot-cap N` to change), most severe lessons first, the rest summarized in one "…and N more" line. Do not commit these files for the user; list them in the summary.

**Retiring:** feed real review outcomes to `node $SCRIPTS/lessons/retire-lessons.mjs --outcomes <file.json>` (input shape in the script header). It lists lessons refuted or marked wrong ≥ 3 times (`--min-negative N`) with 0 accepted, and writes `status: retired` only with `--apply`; re-run the export after.

## Step 6: Summary

After creating all lessons, output:

- How many new lessons were created (with file paths)
- How many duplicates were skipped
- How many existing lessons were updated (replaced)
- Each lesson's status (`active` or `candidate`) and the export result per file
- List of created files:
  ```
  Created: docs/lessons/security/003-sql-injection-db-raw.md
  Created: docs/lessons/performance/001-eager-load-in-loops.md
  Skipped: "Mass Assignment Protection" (duplicate of security/002-mass-assignment-protection.md)
  ```

## Rules

- Only extract **concrete, actionable** lessons — no generic advice like "write clean code"
- Every rule must be specific enough that an AI or developer can follow it without ambiguity
- Prefer framework-specific guidance over language-generic tips when applicable
- If no meaningful lessons were found in the review, say so — do not fabricate lessons
- Write everything in English
- **Never write lessons to CLAUDE.md** — all lessons go to `docs/lessons/` as individual files
- Each lesson is one file — keep them focused and scannable
