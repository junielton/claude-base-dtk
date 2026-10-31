---
name: adr
description: "Use when making architectural choices, introducing new patterns, choosing between alternatives, or revising a previous technical decision."
---

# /adr — Architecture Decision Record

Capture significant technical decisions and persist them as **individual files** in the repo's ADR directory (default `docs/adrs/`; see Step 4).

## When to Use

- New technical approach or pattern being introduced
- Dependency/library/service chosen over alternatives
- Structural or architectural change
- Deliberate trade-off accepted
- Previous decision being revised

Not for lessons from reviews (use `/dtk:learn-from-review`). ADRs capture **what was decided and why**.

## Step 0: Resolve Scripts

```bash
# resolver idiom: docs/conventions/script-resolution.md
SCRIPTS="${CLAUDE_PLUGIN_ROOT}/scripts"; [ -d "$SCRIPTS" ] || echo "dtk: scripts dir not found: $SCRIPTS" >&2; echo "$SCRIPTS"
```

Use the output path as `$SCRIPTS` for all script commands below.

## Step 1: Identify the Decision

Use `$ARGUMENTS` as topic, or analyze current conversation for: new dependencies, schema choices, architectural patterns, API decisions, infrastructure choices, performance trade-offs.

## Step 2: Gather Context

1. **Trigger**: feature, bug, performance issue, tech debt, scaling
2. **Constraints**: timeline, budget, expertise, infrastructure
3. **Alternatives**: minimum 2 (if only one, note explicitly)
4. **Who**: developer, tech lead, team

Ask focused questions if critical context is missing (max 3-4 per ADR).

## Step 3: Assess Weight

| Weight | Criteria |
|---|---|
| **Heavy** | Hard to reverse, wide blast radius, long-term direction |
| **Medium** | Moderate to reverse, affects multiple modules |
| **Light** | Easy to reverse, single module scope |

## Step 4: Detect the Layout, Determine the Next Number

**Detect the repo's convention first.** Glob `docs/adr/`, `docs/adrs/` and
`docs/decisions/` for `*.md` (ignore `README.md` and `index.md`).

- **ADRs already exist** → follow that convention, whatever it is. Take the most
  recent file (`git log -1 --format=%H -- <file>`), read its first ~15 lines and
  copy the **directory**, the **file-name shape** (e.g. `NNNN-<slug>.md`,
  `ADR-NNN-<slug>.md`) and the **header shape** (title line, status/date
  fields, section names). Compute `{NNN}` as the highest number found in that
  directory + 1, padded to the width the existing files use. Do not run
  `next-number.sh` — it only understands the default layout.
- **No ADRs anywhere** → use the dtk default: `docs/adrs/ADR-{NNN}-{short-slug}.md`
  and the template below, with the number from the script:

  ```bash
  NEXT=$(bash $SCRIPTS/adr/next-number.sh)
  ```

State which rule applied in one line. Use `{ADR_DIR}` for the resolved directory
in Steps 5-8.

## Step 5: Create the ADR File

Path: `{ADR_DIR}/{file-name per the detected convention}` — dtk default
`docs/adrs/ADR-{NNN}-{short-slug}.md`.

### Template (dtk default; when the repo has its own header shape, use that instead and keep these sections' content)

```markdown
# ADR-{NNN}: {Short descriptive title}

**Date:** {YYYY-MM-DD}
**Status:** Accepted
**Weight:** Heavy | Medium | Light
**Triggered by:** {Feature/ticket/issue}

## Context

{2-3 sentences: situation and constraints}

## Decision

{1-2 sentences: what was decided}

## Alternatives Considered

- **{Alternative A}:** {Why rejected — 1 sentence}
- **{Alternative B}:** {Why rejected — 1 sentence}

## Consequences

- {Expected positive outcome}
- {Known trade-off or risk}
- {What to watch for}

## Revisit When

{Concrete trigger for reconsidering}
```

## Step 6: Check Conflicts

1. Read `{ADR_DIR}/index.md`. If the repo has no ADRs yet, create it with this header and skip to Step 7. If the repo already has ADRs but **no** index, do not create one — skip Step 7:

```markdown
# Architecture Decision Records

| # | Title | Weight | Status | Date |
|---|-------|--------|--------|------|
```
2. **Conflicts**: Update old ADR status to `Superseded by ADR-{NNN}`, add `**Supersedes:** [ADR-{old}](ADR-{old}-{slug}.md)` to new ADR
3. **Relations**: Add `**Related:** [ADR-{NNN}](ADR-{NNN}-{slug}.md)`
4. **Lessons**: If a lesson from `docs/lessons/` influenced this, add `**Informed by:** [{title}](../lessons/{category}/{file}.md)`

## Step 7: Update Index

Add row at **top** of `{ADR_DIR}/index.md` (newest first), if the index exists:

```markdown
| {NNN} | [{Title}](ADR-{NNN}-{slug}.md) | {Weight} | Accepted | {Date} |
```

## Step 8: Summary

```
## /adr Summary

### Created
- 📄 `docs/adrs/ADR-008-redis-per-key-ttl.md` — Redis with per-key TTL (Heavy)

### Related: ADR-004 (ISR revalidation)
### Superseded: ADR-002 → "Superseded by ADR-008"
### Informed by: `docs/lessons/performance/003-cache-invalidation.md`
```

## Rules

- At least one alternative per ADR
- Project-specific, not generic
- 15-20 lines max per file
- Never delete — supersede
- `Revisit When` is mandatory
- Write in **English**
- The repo's existing ADR layout beats the dtk default; never create a second ADR directory next to an existing one
- Knowledge lives in `docs/` — permanent, version-controlled
