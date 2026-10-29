---
name: implement-mockup
description: "Use when building an approved HTML mockup 1:1 in the real app — a card or task points at a docs/design/<slug>/ mockup folder, the user says 'implementa o mockup', 'segue o mockup aprovado', 'faz igual ao mockup', or complains that an implementation drifted from what was approved. The HTML-mockup sibling of dtk:implement-design (Figma). Do NOT use when no mockup exists yet (dtk:create-mockup) or when the source is Figma."
---

# implement-mockup

Build an approved mockup in the real app, screen by screen, and prove it with
`/dtk:mockup-qa`. The contract format is
`../create-mockup/references/mockup-convention.md` (`$MK/references/…`) — read it first. The mockup folder
(`mockup.json` + `screens/` + `mockup.css` + `parts/`) is the only source of truth; your
reading of the code is never verification.

## Process

Intake → Context (two subagents) → Merge & plan → Implement per screen → mockup-qa → loop.

### 1. Intake

Resolve, asking only for what the card or conversation does not give: the mockup folder,
the dev URL where each screen renders, and the project's run/build commands.

```bash
# resolver idiom: docs/conventions/script-resolution.md
SCRIPTS="${CLAUDE_PLUGIN_ROOT}/scripts"; [ -d "$SCRIPTS" ] || echo "dtk: scripts dir not found: $SCRIPTS" >&2; echo "$SCRIPTS"
MK="${CLAUDE_PLUGIN_ROOT}/skills/create-mockup"; echo "$MK"
node $SCRIPTS/mockup/check-mockup.mjs <folder> --tokens-source <tokensFrom>
```

Errors → stop and route to `/dtk:create-mockup`. Then parse `mockup.json`:

- Screens with `status: "approved"` are your work list. Draft screens are **not**
  implemented; say which ones you are skipping and why.
- No folder / a single `spec.html` / a dirty mockup → **distill** per the convention's
  legacy section, confirm with the user ("is THIS what was approved?"), then continue.

### 2. Context — dispatch both at once

**Contract extractor** (Agent): for each approved screen, read `screens/<id>.html`,
`mockup.css` and the parts it loads. Produce per screen: the element checklist (root →
children → tokens, spacing, radius, typography, per state), the anatomy notes (which element
carries which style, which part renders what), the sample data to seed, and the reference
captures at each viewport × state (convention, "Consuming a mockup"). From `flows`, produce
the **navigation checklist**: trigger element → destination screen + state.

**Codebase explorer** (Agent): locate the targets (`screens[].targets`, verified not
trusted) and their imported children two levels down; map the project's styling idiom
(CSS vars, utilities, component library), i18n and changelog contracts; screenshot the
current state at each viewport; report which anatomy already matches and which diverges;
find the existing shared components that correspond to each `parts/` entry.

### 3. Merge & plan

**Blocking — ask the user:** a token the mockup uses is missing from the project; the
mockup's anatomy contradicts a project design rule; a flow step has no corresponding route
or action in the app; sample data cannot be reproduced where the change is anatomy-level.

**Non-blocking — note and go:** naming differences, properties the mockup leaves free, a
viewport the app does not support.

Write `docs/plans/<date>-implement-<slug>.md`: per screen, checklist + anatomy + current
state + the diff (changes / stays / deleted); the navigation checklist; the parts →
components map. This file is the implementer's map and the reviewer's blast radius.

### 4. Implement, one screen at a time

Order: parts first (shared components), then screens in flow order. For each:

- **Rebuild diverging anatomy; never tweak toward it.** Where the element tree differs,
  delete and rebuild from the screen file. Tweaking keeps hidden structure (a border where a
  child bar should be) that survives every "adjustment" and resurfaces as drift. Matching
  anatomy may be edited in place.
- Map tokens through the project's idiom (vars → utilities, etc.); never a raw value.
- States map to real conditions (loading, empty, error, dialog open); every mockup state must
  be reachable in the app, behind a fixture or dev switch when the backend cannot produce it.
- Wire the navigation checklist: each `data-goto` is a real route or action.
- Add `data-dsqa="<id>"` to the screen root and `data-dsqa-part` where the mockup has them.
- Follow the project's own contracts (design doc, i18n, changelog).

### 5. Verify — mandatory

Run `/dtk:mockup-qa` on the implemented screens (folder, dev URL, screens). It is the final
authority. ❌ / ⚠️ → fix Critical + Major, re-run; a finding that is impossible under the
framework goes to the user as a mockup-change decision, never silently accepted. ✅ →
attach the report and composites to the PR/card. **A done report without mockup-qa evidence
is not done.**

## Rules

- Never implement a draft screen; never flip a status to unblock yourself.
- Never implement from a dirty or v1 mockup without distilling first.
- Context before code; steps 2–3 are not skippable.
- Rebuild diverging anatomy; never tweak toward it.
- Flows are verified by clicking, not by reading the router.
