---
name: learn-from-review
description: Extract actionable lessons from the current code review session and persist them as categorized files in docs/lessons/
---

# Extract Lessons from Code Review

You are a knowledge extraction assistant. Your task is to analyze the current code review session and extract actionable lessons learned, then persist them as **individual files** in `docs/lessons/{category}/`.

## Step 1: Analyze the Review

Examine the current conversation and identify lessons across these categories:

- **security**: Vulnerabilities, injection risks, auth/authorization issues, data exposure
- **code-patterns**: Anti-patterns found, better alternatives suggested, architectural improvements
- **qa**: Edge cases missed, validation gaps, error handling issues, test coverage blind spots
- **performance**: N+1 queries, unnecessary loops, missing indexes, caching opportunities
- **framework**: Framework-specific gotchas, best practices, lifecycle issues
- **testing**: Test strategy issues, missing coverage, flaky tests, test architecture
- **frontend**: UI/UX issues, accessibility, component patterns, state management

## Step 2: Format Each Lesson

Each lesson becomes an **individual file** in its category folder.

### Template

```markdown
# {Short descriptive title}

**Category:** {category}
**Severity:** Critical | High | Medium | Low
**Date:** {YYYY-MM-DD}

## Rule

{One clear, actionable sentence — what to always do or never do}

## Bad

```{lang}
// brief example of the wrong approach
```

## Good

```{lang}
// brief example of the correct approach
```

## Why

{1-2 sentences explaining the risk or benefit}
```

## Step 3: Determine Next Number

```bash
CATEGORY="{category}"
LAST=$(ls docs/lessons/$CATEGORY/*.md 2>/dev/null | grep -oP '\d{3}' | sort -n | tail -1)
NEXT=$(printf "%03d" $((10#${LAST:-0} + 1)))
```

## Step 4: Save the Lesson File

Path: `docs/lessons/{category}/{NNN}-{short-slug}.md`

Examples:
- `docs/lessons/security/001-sanitize-user-input.md`
- `docs/lessons/performance/003-avoid-n-plus-one-queries.md`
- `docs/lessons/qa/002-validate-empty-states.md`

**Before saving**, check for duplicates in the category folder. If a similar rule already exists, **update the existing file** only if the new version is more complete or accurate. Do not create duplicates.

## Step 5: Update the Index

Add a row at the **top** of the table in `docs/lessons/index.md` (newest first):

```markdown
| {NNN} | [{Title}](./{category}/{NNN}-{short-slug}.md) | {category} | {Severity} | {Date} |
```

If `docs/lessons/index.md` does not exist, create it following the template from the bootstrap skill.

## Step 6: Summary

```
## /learn-from-review Summary

### Created
- 📄 `docs/lessons/security/004-prevent-sql-injection-in-filters.md` — Prevent SQL injection in dynamic filters (Critical)
- 📄 `docs/lessons/performance/002-use-eager-loading.md` — Use eager loading for related models (High)

### Updated
- ✏️ `docs/lessons/qa/001-validate-nullable-fields.md` — expanded with new edge case

### Index
- Updated `docs/lessons/index.md` with 2 new entries
```

## Rules

- Only extract **concrete, actionable** lessons — no generic advice like "write clean code"
- Every rule must be specific enough that an AI or developer can follow it without ambiguity
- Prefer framework-specific guidance over language-generic tips when applicable
- If no meaningful lessons were found in the review, say so — do not fabricate lessons
- **NEVER write lessons to CLAUDE.md** — lessons live in `docs/lessons/`
- One lesson per file — keeps diffs clean and categories organized
- 15-20 lines max per file
- Write everything in **English**
- Knowledge lives in `docs/` — permanent, version-controlled
