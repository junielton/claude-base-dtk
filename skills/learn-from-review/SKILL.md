---
name: learn-from-review
description: Extract actionable lessons from the current code review session and persist them into the project's CLAUDE.md knowledge base
---

# Extract Lessons from Code Review

You are a knowledge extraction assistant. Your task is to analyze the current code review session and extract actionable lessons learned, then persist them into the project's knowledge base.

## Step 1: Analyze the Review

Examine the current conversation and identify lessons across these categories:

- **Security**: Vulnerabilities, injection risks, auth/authorization issues, data exposure
- **Code Patterns**: Anti-patterns found, better alternatives suggested, architectural improvements
- **QA**: Edge cases missed, validation gaps, error handling issues, test coverage blind spots
- **Performance**: N+1 queries, unnecessary loops, missing indexes, caching opportunities
- **Framework**: Framework-specific gotchas, best practices, lifecycle issues

## Step 2: Format Each Lesson

For each lesson found, write it in this format:

```markdown
### [Short descriptive title]

**Category:** Security | Code Patterns | QA | Performance | Framework
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

## Step 3: Update the Knowledge Base

1. Read the file `CLAUDE.md` at the project root (create it if it doesn't exist).
2. Look for an existing `## Lessons Learned` section. If it doesn't exist, add it at the end of the file.
3. Under `## Lessons Learned`, check for each subsection: `### Security`, `### Code Patterns`, `### QA`, `### Performance`, `### Framework`.
4. For each new lesson:
   - **Check for duplicates**: If a similar rule already exists, update it only if the new version is more complete or accurate. Do not add duplicates.
   - **Append** the new lesson under the appropriate subsection.
5. Keep each lesson concise — the goal is quick reference during development, not documentation.

## Step 4: Summary

After updating, output a brief summary:

- How many new lessons were added
- How many existing lessons were updated
- List the titles of all changes made

## Rules

- Only extract **concrete, actionable** lessons — no generic advice like "write clean code"
- Every rule must be specific enough that an AI or developer can follow it without ambiguity
- Prefer framework-specific guidance over language-generic tips when applicable
- If no meaningful lessons were found in the review, say so — do not fabricate lessons
- Write everything in English
- Keep the CLAUDE.md file well-organized and scannable
