---
name: adr
description: "Use when making architectural choices, introducing new patterns, choosing between alternatives, or revising a previous technical decision."
---

# /adr — Architecture Decision Record

Capture significant technical decisions and persist them as **individual files** in `docs/adrs/`.

## When to Use

- New technical approach or pattern being introduced
- Dependency/library/service chosen over alternatives
- Structural or architectural change
- Deliberate trade-off accepted
- Previous decision being revised

Not for lessons from reviews (use `/dtk:learn-from-review`). ADRs capture **what was decided and why**.

## Step 0: Resolve Scripts

```bash
SCRIPTS="bin/skill-scripts"; [ -d "$SCRIPTS" ] || SCRIPTS="${CLAUDE_PLUGIN_ROOT:-}/bin/skill-scripts"; [ -d "$SCRIPTS" ] || SCRIPTS=$(find ~/.claude/plugins -path "*/dtk/bin/skill-scripts" -maxdepth 5 2>/dev/null | head -1); echo "$SCRIPTS"
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

## Step 4: Determine Next Number

```bash
NEXT=$(bash $SCRIPTS/adr/next-number.sh)
```

## Step 5: Create the ADR File

Path: `docs/adrs/ADR-{NNN}-{short-slug}.md`

### Template

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

1. Read `docs/adrs/index.md`. If it doesn't exist yet (first ADR in the project), create it with this header and skip to Step 7:

```markdown
# Architecture Decision Records

| # | Title | Weight | Status | Date |
|---|-------|--------|--------|------|
```
2. **Conflicts**: Update old ADR status to `Superseded by ADR-{NNN}`, add `**Supersedes:** [ADR-{old}](ADR-{old}-{slug}.md)` to new ADR
3. **Relations**: Add `**Related:** [ADR-{NNN}](ADR-{NNN}-{slug}.md)`
4. **Lessons**: If a lesson from `docs/lessons/` influenced this, add `**Informed by:** [{title}](../lessons/{category}/{file}.md)`

## Step 7: Update Index

Add row at **top** of `docs/adrs/index.md` (newest first):

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
- Knowledge lives in `docs/` — permanent, version-controlled
