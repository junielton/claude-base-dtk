---
name: prd
description: "Use when starting a new feature, defining requirements, or formalizing specifications from a rough task description."
---

# PRD Generator

Transform a rough task description into a well-structured PRD through interactive refinement.

## Input

Read and analyze: `$ARGUMENTS`

If no file is provided, ask the user to describe the feature.

## Process — Interactive Refinement

**Do NOT generate immediately.** First analyze, then refine.

### Step 1: Initial Analysis

- Summary of what you understood
- Confidence level (low/medium/high)
- Gaps and ambiguities identified

### Step 2: Clarifying Questions (max 5-7, max 3 rounds)

- **Scope & Goals**: problem, beneficiaries, business value
- **User Experience**: expected flow, UI/UX
- **Edge Cases**: failures, empty states, concurrency
- **Technical Constraints**: performance, APIs, migrations
- **Dependencies**: other features/systems affected
- **Out of Scope**: what's explicitly excluded

### Step 3: Confirm

"Should I generate the PRD now, or is there anything else to add?"

## Output

### Step 4: Detect the repo's PRD convention

Before choosing a path, check whether the repo already has one:

1. Glob `docs/prds/`, `docs/prd/` and `docs/PRDs/` for `*.md` (ignore `README.md`
   and `index.md`).
2. If any PRD exists, take the most recent one (`git log -1 --format=%H -- <file>`)
   and read its first ~15 lines. Copy from it: the **file-name shape** (e.g.
   `<CARD-ID>-<slug>.md`, `<NNNN>-<slug>.md`, `PRD-<slug>.md`), the **title/header
   shape** (heading text, status line, metadata block) and the **section
   order**. Use the template below only for sections the repo's PRDs don't have.
3. Where the convention embeds an id (a card or task id such as `PROJ-123`),
   take it from `$ARGUMENTS`, the branch name or the card; if none is known, ask once.
4. **Only when no convention exists** (no PRD directory, or it is empty), use the
   dtk default: `docs/prds/PRD-{short-kebab-title}.md`.

State which rule applied in one line ("Following the repo's
`docs/prds/<CARD-ID>-<slug>.md` layout" or "No PRD convention found — using the
dtk default").

### Template (dtk default shape)

```markdown
# PRD: {Feature Title}

> **Status:** Draft
> **Author:** {Developer name if known}
> **Created:** {Date}
> **Last Updated:** {Date}

---

## 1. Overview

### 1.1 Summary
{2-3 sentences: core goal, who benefits}

### 1.2 Problem Statement
{What problem, why it matters}

---

## 2. User Stories

- As a {user}, I want {action} so that {benefit}
- ...

---

## 3. Functional Requirements

### 3.1 Acceptance Criteria

- [ ] AC1: Given {context}, When {action}, Then {result}
- [ ] AC2: ...

### 3.2 Business Rules

{Validation rules, constraints}

---

## 4. User Experience

### 4.1 User Flow
{Step-by-step interaction}

### 4.2 UI/UX Considerations
{Components, responsive behavior, accessibility}

---

## 5. Technical Approach

### 5.1 Architecture & Design
{Patterns, component structure}

### 5.2 Data Model
{Tables, columns, migrations}

### 5.3 API Contracts
{Endpoints, request/response, status codes}

### 5.4 Dependencies
{External services, packages}

---

## 6. Edge Cases & Error Handling

| Scenario | Expected Behavior |
|----------|-------------------|
| ... | ... |

---

## 7. Testing Strategy

### 7.1 Unit Tests
### 7.2 Feature/Integration Tests
### 7.3 Manual Testing Checklist
- [ ] ...

---

## 8. Out of Scope
- ...

---

## 9. Open Questions
- ...

---

## 10. References
- ...
```

## Rules

- Write in **English**
- Acceptance criteria must be **testable**
- Tailor to project's stack (check CLAUDE.md)
- Omit empty sections for simple features
- PRDs live where the repo already keeps them (default `docs/prds/`) — version-controlled, permanent
- The repo's existing layout beats the dtk default; never create a second PRD directory next to an existing one
