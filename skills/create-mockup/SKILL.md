---
name: create-mockup
description: "Use when the user wants to SEE a UI proposal before it is built — a mockup, a redesign, a new screen or a whole journey of screens, a 'me mostra como ficaria', 'cria um mockup', 'desenha essa tela', 'quero aprovar antes', or a card that needs an approved visual contract. Also when an existing mockup is a single giant HTML the user cannot navigate screen by screen. Do NOT use when Figma is the source (dtk:implement-design) or when the mockup exists and only needs building (dtk:implement-mockup)."
---

# create-mockup

Author an approved visual contract as **one file per screen**, flows that click through,
and a thin review index — so the user can study one screen alone, walk a journey like the
real app, and approve screen by screen. The format is `references/mockup-convention.md`:
read it first, every time. Templates are in `templates/`, the gate is
`scripts/check-mockup.mjs` (both resolved from `$MK`, step 4).

## Process

Immersion → Inventory (agree the map) → Build → Check → Alignment loop per screen →
Approval per screen → Handoff.

### 1. Immersion

Read the project's design contract (`design.md` or equivalent), its token source, and the
anatomy of the components the mockup touches (how existing rows, cards, tabs, dialogs are
built). Write a scratch context sheet: tokens, anatomies, spacing/radius/motion rules, voice.
Scale it to the task: a padding fix reads one component and the token file.

No token system in the project → stop and say so. A mockup over ad-hoc values promises a
fidelity nobody can verify; agree tokens first.

### 2. Inventory — before any pixel

List what the mockup is made of and show it to the user as a table **before building**:

| screen id | states | parts used | in flows |
|---|---|---|---|

plus the flows as ordered steps (`screen → via "what the user does" → screen?state`).
This is the cheapest alignment round there is: a wrong map costs minutes here and hours
after thirty screens exist. Use the convention's unit table (screen vs state vs part); a
dialog is a state, a repeated header is a part. Proceed on the user's OK or on silence
after a clear "vou seguir com esse mapa".

### 3. Build

Create `docs/design/<slug>/` (or the project's existing mockup folder):

1. `tokens.css` — copy the token layer verbatim from `tokensFrom`.
2. `mockup.js` — copy `templates/mockup.js` byte for byte.
3. `mockup.css` — shared anatomy, `var(--token)` only.
4. `parts/<name>.js` from `templates/part.js` for anything used by 2+ screens, plus
   `parts/index.html` from `templates/parts-index.html`.
5. `screens/<id>.html` from `templates/screen.html`, one per inventory row: one
   `data-dsqa` root, `<body data-states>`, state CSS, `data-goto` on every element that
   navigates in the real app, deterministic data, zero prose.
6. `mockup.json` from `templates/mockup.json`: every screen, every state, every flow.
7. `index.html` from `templates/index.html`: context + one article per screen + flows.
   Current-state screenshots go to `assets/` as images.

Design judgment (typography, hierarchy, a signature element — the frontend-design school)
applies to genuinely new UI, **inside the project's tokens**: distinctiveness comes from
composition, never from new values. Anatomy fixes have no creative axis.

### 4. Check

```bash
MK="${CLAUDE_PLUGIN_ROOT:-}/skills/create-mockup"; [ -d "$MK" ] || MK=$(ls -d ~/.claude/plugins/cache/dtk-marketplace/dtk/*/skills/create-mockup 2>/dev/null | sort -V | tail -1); echo "$MK"
node $MK/scripts/check-mockup.mjs docs/design/<slug> --tokens-source <tokensFrom>
```

Zero errors before the user sees anything. Read every warning to them (an unclickable flow
step is usually a missing `data-goto`).

### 5. Alignment loop, per screen

Serve the folder (`python3 -m http.server`, or the Harnu browser pane) and present
`index.html`. Feedback edits the screen file (or `mockup.css` / a part); the index updates
for free. Point the user at "abrir sozinha" for a deep look and "percorrer" for a flow.
Feedback that asks for a value outside the tokens → surface the conflict, don't invent.
Keep rounds cheap: change, re-check, show. The loop ends only through step 6.

### 6. Approval, per screen

Approval is the user's explicit gesture at a screen's current state. Set that screen's
`status: "approved"` + `approvedAt`; flip `mockup.json.status` and the index banner only
when every screen is approved. Re-run the checker. An approved screen is frozen: any later
edit returns it to draft and reopens its loop. New asks after approval are a new draft
cycle, not a silent mutation.

### 7. Handoff

Offer `/dtk:implement-mockup` on the approved screens (same session, or a card whose `spec`
field is the mockup folder). Say which screens are still draft; implementation may start
on the approved ones.

## Rules

- **Convention first** — read `references/mockup-convention.md` before authoring.
- **One screen, one file** — never several roots in one file, never a screen inlined in
  the index. The index embeds; it does not contain.
- **Flows click** — a step without a `data-goto` reaching the next is not done.
- **Tokens verbatim, always** — the checker is the judge, not your eye.
- **Never self-approve** — status flips only on the user's explicit OK, per screen.
- **Templates verbatim** — `mockup.js` and the index runtime are copied, not rewritten.

## Red flags — stop

| Thought | Reality |
|---|---|
| "It's only three screens, one file is simpler" | Three become fifteen. The unit is the screen from the first one. |
| "I'll put the dialog in its own screen file" | A dialog is a state of the screen under it. Flows and QA depend on that. |
| "I'll show it now and run the checker later" | The checker runs before every presentation. |
| "The user said it looks good, I'll approve all" | Approval names screens. Ask which. |
| "This value isn't in tokens but it's close to one" | Use the token or raise the gap. Never the number. |
| "I'll tweak mockup.js for this project" | The runtime is shared by implement and QA. Extend with a part or state, never by editing it. |
