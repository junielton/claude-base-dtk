# Mockup convention (v2 — one file per screen)

The shared contract between `create-mockup` (authors), `implement-mockup` (consumes) and
`mockup-qa` (verifies). Templates live in `../templates/`, the mechanical gate in
`scripts/mockup/check-mockup.mjs` (plugin root).

## Why one file per screen

v1 was two files: `spec.html` (every component, one page) + `review.html` (prose + iframes).
It breaks past a handful of screens: a real one reached 34 screens in an 870 KB `spec.html`
and a `review.html` with 136 iframes. Nobody can open ONE screen to study it, flows were
hash tricks inside one document, and QA captured a huge page to read one root.

v2 keeps the two-audience split (machine contract vs human review) but makes the unit of
work the **screen**: one file, its own URL, its own states, its own approval. Flows are real
navigation between files, so a reviewer walks the mockup like the app.

## Layout

```
docs/design/<slug>/            ← follow the project's existing mockup folder if it has one
├── mockup.json                contract meta. Machine-read. The ONLY place status lives.
├── index.html                 review page. Human-read. Embeds screens by <iframe>, never copies them.
├── tokens.css                 verbatim copy of the project's token layer (path in mockup.json tokensFrom)
├── mockup.css                 anatomy shared by 2+ screens. var(--token) only.
├── mockup.js                  runtime. Copied verbatim from templates/mockup.js. Never edited.
├── screens/<id>.html          ONE screen per file. States via ?state=. One [data-dsqa="<id>"] root.
├── parts/<name>.js            optional: a piece used by 2+ screens (custom element, light DOM)
├── parts/index.html           optional: gallery, every part at every variant, one data-dsqa root each
└── assets/                    screenshots of the CURRENT state, reference images
```

## Screen, state, part — pick the right unit

| Unit | It is | Example |
|---|---|---|
| **screen** | a view with its own route or a distinct full view in the app | `visualizar--contatos`, `novo--empresa` |
| **state** | the SAME screen under a different condition | `loading`, `empty`, `erro-cep`, `confirmar-exclusao` (dialog open), `aba-socios` |
| **part** | markup repeated in 2+ screens | header, tab strip, data row, stepper |

A dialog, toast or drawer is a **state of the screen it sits on**, unless the app gives it its
own route. A tab switch inside one page is a state. A component mockup (one button, one row)
is a screen whose root is the component — the convention does not care about size.

## mockup.json

```json
{
  "status": "draft",                       // approved ONLY when every screen is approved
  "approvedAt": null,
  "project": "zm-extranet",
  "card": "T45",                           // board card / ticket, or null
  "tokensFrom": "resources/css/app.css",   // the project's real token source
  "viewports": [390, 768, 1280],           // widths QA captures at (index VIEWPORTS mirrors this)
  "targets": ["resources/js/pages/..."],   // files expected to change (union of screens[].targets)
  "screens": [
    { "id": "visualizar--contatos", "title": "Contatos (leitura)", "status": "draft", "approvedAt": null,
      "states": ["default", "vazio", "carregando"],     // first = default; mirrors <body data-states>
      "targets": ["resources/js/pages/ClientAnalysis/Show.vue"],
      "viewports": [390, 1280],                          // optional override
      "notes": "one line: what this screen is for" }
  ],
  "parts": [{ "id": "tabs", "variants": ["contatos", "socios"] }],
  "flows": [
    { "id": "excluir-contato", "title": "Excluir um contato",
      "steps": [
        { "screen": "editavel--contatos", "state": "default", "via": "botão Excluir da linha" },
        { "screen": "editavel--contatos", "state": "confirmar-exclusao", "via": "Excluir no diálogo" },
        { "screen": "editavel--contatos", "state": "default" } ] }
  ]
}
```

Rules: ids are `kebab-case`, `group--name` when the mockup has groups; a screen id IS its file
name; `states[0]` is the default; `flows[].steps[n].via` names what the user does to reach step
n+1, and screen n MUST carry a `data-goto` to step n+1 (the checker warns otherwise: a flow
you cannot click is a drawing, not a flow).

## screens/<id>.html

Start from `templates/screen.html`. Rules:

1. **Self-contained.** Loads only `../tokens.css`, `../mockup.css`, `../parts/*.js`,
   `../mockup.js`. No external requests. Opens over `file://` and `http://`.
2. **One root**: exactly one element with `data-dsqa="<id>"` (the id in `mockup.json`).
   Inner pieces may carry `data-dsqa-part="<name>"`; QA and the implementer use them as the
   anatomy map.
3. **States** are declared on `<body data-states="default vazio carregando">` and styled as
   `[data-dsqa="<id>"][data-state="vazio"] …`. `mockup.js` sets `data-state` from `?state=`.
   Every declared state must be visibly different; a state with no CSS is a lie.
4. **Navigation** is `data-goto="<screen>"` or `data-goto="<screen>?state=<s>"` on any element
   (`data-goto="back"` = history back). A `<form data-goto>` navigates on submit; forms never
   really submit.
5. **Tokens verbatim**: every color, radius, spacing, font is `var(--token)` from `tokens.css`
   or inherited from `mockup.css`. A raw color anywhere in `screens/`, `mockup.css` or `parts/`
   fails the checker (it scans `<style>` blocks and `style=""` attributes, so text like
   `#1042` is fine). A value the token system lacks is a design-system change to raise with
   the user, never a number to sneak in. Dimensions the tokens do not cover (a dialog
   max-width, a breakpoint) are allowed as plain numbers with a `/* no token: … */` comment.
6. **Deterministic sample data**: fixed strings, fixed counts, no clocks. Record values the
   implementer must seed in `mockup.json` `screens[].notes` or a `sampleData` field.
7. **Zero prose.** No headings explaining, no captions, no before/after. That is `index.html`.
8. `body { margin: 0 }` (mockup.css does it) — the runtime reports body height to the index.

## parts/<name>.js

Only when a piece appears in 2+ screens. `customElements.define('mk-<name>', …)` rendering
**light DOM** (no shadow root) so tokens cascade and QA can select children. Variants come
from attributes. Styles live in `mockup.css`. `parts/index.html` renders every part at every
variant with `data-dsqa="part--<name>--<variant>"` so a part is reviewable alone. A part may
carry `data-goto` (a header's back button, a row's "ver"): the checker counts the `data-goto`
of every part a screen loads as that screen's, so flows through parts stay clickable.

## index.html

Start from `templates/index.html`. It is the human page and it stays **thin**:

- `Contexto e decisões` — why, what problem, decisions taken, screenshots of the current
  state from `assets/` as `<img>` (never rebuilt as markup).
- `Telas` — one `<article class="screen" data-screen="<id>" data-states="…">` per screen, in
  reading order: title + id, viewport chips, state chips, "abrir sozinha" link, one or two
  lines of notes, ONE iframe, the approval line. The runtime in the template handles chips
  and sizing; do not add behaviour.
- `Fluxos` — one `<article class="flow" data-flow="<id>">` per flow: ordered steps linking to
  `screens/<id>.html?state=…`, plus "percorrer" opening step 1 alone, where every
  `data-goto` is live.
- `Partes` — link to `parts/index.html` when parts exist.
- Status banner `data-status` and `const VIEWPORTS` mirror `mockup.json`; the checker fails
  on drift. No `data-dsqa` root may exist in this file.

## Approval

- A screen is approved only by the user's explicit gesture aimed at THAT screen's current
  state ("esse pode", "aprovado o visualizar"). Then `screens[].status = "approved"` +
  `approvedAt`. A bulk "tudo aprovado" approves every screen the user has seen.
- `mockup.json.status` becomes `approved` only when every screen is; the index banner
  follows. Implementation may start on approved screens while others are still draft.
- An approved screen is frozen. Any edit to its file, to `mockup.css` or to a part it uses
  flips it (and the overall status) back to `draft` and reopens the loop. No skill flips a
  status to unblock itself.

## The checker

```bash
node $SCRIPTS/mockup/check-mockup.mjs docs/design/<slug> --tokens-source <project tokens file>
```

Run it before every presentation, before any status flip, and first thing in
`implement-mockup` and `mockup-qa`. Errors block; warnings are read aloud to the user.

## Consuming a mockup (implement-mockup / mockup-qa)

- Parse `mockup.json`. Work screen by screen; refuse a screen whose status is `draft`.
- Per screen, the element checklist comes from `screens/<id>.html` + `mockup.css` + the
  parts it loads: root → children → tokens, spacing, radii, typography, per state. Anatomy
  (which element carries which style) is part of the contract.
- Flows become a **navigation checklist**: for each step, trigger element → destination
  screen + state. Verified by clicking in the real app, not by reading the router.
- Reference capture, per screen × state × viewport:
  ```bash
  node $SCRIPTS/dsqa/capture-and-compare.mjs \
    --url "file:///abs/docs/design/<slug>/screens/<id>.html?state=<s>" \
    --selector '[data-dsqa="<id>"]' --viewport <w>x900 --output ./mockup-qa/<id>-<s>-<w>/spec
  ```

## Legacy mockups

A v1 mockup (`spec.html` + `review.html`) or a dirty one (presentation and components fused)
is **distilled** into this layout before anything is implemented: one screen file per
`data-dsqa` root, states regrouped, flows declared, index rewritten thin. Show the result and
ask "is THIS what was approved?" before setting any screen to approved.
