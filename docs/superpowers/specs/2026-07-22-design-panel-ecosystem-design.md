# Design-Panel Ecosystem — Design Spec

**Date:** 2026-07-22
**Status:** Approved pending user review
**Origin:** BTP-2242 (Figma Code Connect vs. skill-driven workflow evaluation, `dev-design-workflow` repo)

## Goal

Turn the design-system panel born in BTP-2242 into a reusable, skill-driven ecosystem that
out-competes Figma Code Connect: a deterministic panel scaffold for any Laravel project, a
persistent component ↔ Figma-node link (the manifest), and a drift-detection skill that closes
the loop back into re-implementation.

## Decisions (settled during brainstorming)

1. **Packaging:** all new skills live in the **dtk plugin**, alongside `dtk:implement-design`
   and `dtk:dsqa`. Per-project tweaks happen via `LESSONS.md`/local overrides, not forks.
   `dtk:bootstrap` is deprecated and will be deleted — the scaffold is standalone.
2. **Manifest format:** **one JSON file per component** (`design/manifests/<slug>.json`),
   text-only, schema-validated. Human prose stays in `docs/plans/*` (linked from the manifest).
3. **Panel features** (Figma link, sync badge, props/variants doc) must be **deterministically
   delivered**: shipped as ready templates in the plugin, installed by script — never
   model-generated per project.
4. **Drift detection baseline is the live render, not stored images.** Zero PNGs committed.
   The check compares a fresh Figma screenshot against the freshly rendered local preview
   (reusing the dsqa capture/compare scripts), plus token-hash comparison.
5. **Composition (Approach A):** 4 pieces, the manifest is the contract. No skill imports
   another; they communicate through `design/manifests/`. Each remains usable alone.

## Architecture

```
dtk:scaffold-design-panel   (new)       installs panel + manifest infra (once per project)
dtk:implement-design        (extended)  Figma → build → DSQA pass → writes manifest
dtk:update-design           (new)       reads manifests → drift check → report → (approval) re-trigger
dtk:dsqa                    (unchanged) consumed by the two above

design/manifests/<slug>.json            the contract everything reads/writes
```

All manifest writes go through **one shared script** (`write-manifest.mjs`) that validates
against a JSON Schema before writing. Three skills write; one real writer; no malformed
manifests.

## The Manifest

`design/manifests/<slug>.json` — ~3–5 KB of text per component:

```json
{
  "$schema": "…/component-manifest.schema.json",
  "component": "ui.button",
  "registry": { "area": "components", "item": "button" },
  "figma": {
    "fileKey": "tqdTWuxkX3MgCXwJh0zgKf",
    "desktop": { "nodeId": "1154:56909", "url": "https://…&m=dev", "layerName": "Button" },
    "mobile": null
  },
  "api": {
    "props": [{ "name": "label", "type": "string" }, { "name": "rightIcon", "type": "?string" }],
    "variants": { "enum": "App\\Enums\\Components\\Button\\Variant", "cases": ["Default"] },
    "slots": ["default"]
  },
  "tokens": {
    "colors": ["primary", "primary-foreground"],
    "radius": ["rounded-lg"],
    "typography": ["text-sm", "font-medium"]
  },
  "variableDefsHash": "sha256:…",
  "sync": {
    "lastCheckedAt": "2026-07-22T14:00:00Z",
    "lastResult": "in-sync",
    "implementedAt": "2026-07-20"
  },
  "plan": "docs/plans/2026-07-20-implement-button.md"
}
```

Key semantics:

- **`layerName` is the anchor; `nodeId` is a cache.** If a fetch by id fails (designer
  restructured the file), `update-design` re-locates the component by layer name inside the
  block (via `get_metadata`, same mechanism as the node map), self-heals the `nodeId`, and
  continues.
- **`api` and `tokens` are the textual snapshots** that let drift Layer 2 *describe* a change
  ("new prop `size`", "token `ring` gone") without any stored image. Both derive from
  artifacts `implement-design` already produces (`extract-figma-tokens.mjs` output, the typed
  Figma props).
- **`sync.lastResult`** ∈ `in-sync | drifted | never-checked | unreachable` — the field the
  panel badge renders.
- Presentation concerns stay in `config/design-system.php`; provenance/sync concerns live
  here. Separate lifecycles, separate files.

## `dtk:scaffold-design-panel`

### Shipped templates (`templates/design-panel/` in the plugin)

The BTP-2242 panel, generalized, with minimal placeholders (`{{namespace}}`):

```
app/Http/Controllers/DesignSystem/PanelController.php
app/Http/Controllers/DesignSystem/PreviewController.php
app/Support/DesignSystem/ManifestRepository.php        ← reads design/manifests/*.json
config/design-system.php                               ← empty registry + foundations
resources/views/design-system/layout.blade.php
resources/views/design-system/preview.blade.php
resources/views/design-system/items/foundations/*      ← colors, typography, spacing, radius, shadows
resources/views/design-system/items/_component.blade.php  ← default component page
routes/design-system.php
design/manifests/.gitkeep + component-manifest.schema.json
tests/Feature/DesignSystem/*                           ← installed into the project
```

Plus scripts: `install-design-panel.mjs` (installer), `write-manifest.mjs` (shared writer).

### Installer behavior (deterministic, idempotent)

1. **Preflight:** Laravel? Tailwind v4 with `@theme`? Blade? Abort with a clear diagnosis
   otherwise.
2. **Copy templates** that don't exist; for existing files, diff and report drift instead of
   overwriting (`--force` to overwrite explicitly). Running twice is a no-op.
3. **Single edit to an existing file:** append `require routes/design-system.php` to
   `web.php`, marker-guarded so it never doubles.
4. **Gate:** write `DESIGN_SYSTEM_ENABLED` to `.env.example`; the config flag (not an
   `isProduction()` check) inherits the staging-runs-as-production lesson from BTP-2242.
5. **Prove it:** boot the app, HTTP smoke-test `/design-system` and one foundations preview
   before declaring success.

The model's role in the skill: intake questions (namespace, partial panel present?), run the
installer, interpret the smoke test. Zero structural creativity.

### The 3 panel features (born from the default component page)

`_component.blade.php` reads `ManifestRepository`, so every registered component gets, for
free:

- **Figma link** — "Open in Figma ↗" from `figma.desktop.url`. No manifest → not rendered.
- **Sync badge** — green `in-sync` / amber `drifted` / gray `never-checked` / red
  `unreachable`, from `sync.lastResult` + `lastCheckedAt`. The panel only reads; only
  `update-design` writes.
- **Props/variants doc** — table rendered from `api` (props, types, enum cases, slots).
  Deterministic because it renders data, not prose.

A component-specific showcase view **extends** the default page rather than replacing it, so
the three features are never lost.

### Deliberate scope cuts

The scaffold ships no components, no icons beyond the ~5 the panel chrome itself needs, no
specific showcase views. The panel is born empty with working foundations, ready for
`implement-design` to populate. BTP-2242's repo is not auto-migrated; its ~30 manifests come
later via `update-design --backfill`.

## `dtk:implement-design` — the delta

One new **Phase 7 — Register manifest**, executed only after DSQA approves:

```bash
node bin/skill-scripts/design-panel/write-manifest.mjs \
  --slug button --area components \
  --file-key tqdTWuxkX3MgCXwJh0zgKf --desktop-node 1154:56909 \
  --context .implement-design-tmp/button-figma-context.txt \
  --tokens  .implement-design-tmp/button-tokens.json \
  --plan    docs/plans/2026-07-20-implement-button.md
```

The script derives `api`, `tokens`, `layerName`, and `variableDefsHash` from artifacts earlier
phases already produce, validates, writes. Re-implementation of an existing component = same
command; manifest updated, `sync` reset to `in-sync`.

## `dtk:update-design`

### Invocation modes

- **Single component** — "did Button's Figma change?"
- **Sweep** — iterate all `design/manifests/*.json`. This is the schedulable mode (cron/loop
  later, no skill changes needed).
- **Backfill** — component registered in the panel but missing a manifest: resolve the node
  (node map → `get_metadata` by layer name → ask for the URL as last resort), fetch once,
  write the manifest without re-implementing.

### Preflight

App up; `public/hot` answering or a fresh build — otherwise the comparison validates stale
styles and lies (dsqa's hardest-won lesson).

### Layer 1 — cheap, per component (~2 MCP calls)

1. Fresh `get_screenshot` of the node → temp dir. Node gone → re-locate by `layerName`,
   self-heal the manifest, continue; still unreachable → `sync: unreachable`, into the report.
2. Capture the local preview (`/design-system/preview/<area>/<slug>`) with the dsqa scripts;
   pixel-compare fresh-Figma × local-render.
3. `get_variable_defs` → hash × manifest's `variableDefsHash`.
4. All within tolerance → `write-manifest.mjs --touch-sync in-sync`, next component. Without
   drift this is the entire cost; 100 clean checks produce zero repo changes beyond
   `lastCheckedAt`.

### Layer 2 — only for divergent components

5. Re-fetch design context (with implement-design's documented fallbacks) → re-extract
   tokens/API → diff against the manifest's `api`/`tokens` snapshots.
6. Classify the drift: **visual** (pixel), **token** (palette), **API** (prop/variant
   added/removed), **structural** — and mark `sync: drifted`.

### Report and re-trigger (the human gate)

7. One `report-back`-style report: per component, what changed, side-by-side screenshots,
   recommendation. Panel badges already reflect the new state.
8. **Re-triggering `implement-design` is opt-in per component.** On approval, it invokes
   implement-design in re-implementation mode with the Layer-2 context as Phase 2 input (no
   double fetching). New DSQA pass → Phase 7 rewrites the manifest → loop closed.
   Auto-re-trigger can become an option later, once trusted.

## Testing & guardrails

- `write-manifest.mjs` and the installer get **their own tests in the plugin** (real Figma
  context fixtures → expected manifest; scaffold runs against a disposable Laravel skeleton).
- The scaffold installs **2–3 PHPUnit feature tests** into the target project: panel routes
  respond, preview 404s without a `preview` key, `ManifestRepository` reads valid and ignores
  invalid manifests. The scaffolded panel arrives tested.
- A malformed manifest **never breaks the panel**: the repository skips the file and logs;
  the badge shows `never-checked`.

## Out of scope (for now)

- Auto-migration of BTP-2242's existing components (backfill covers it on demand).
- Scheduled/cron drift sweeps (the sweep mode is ready for it; wiring it is a later choice).
- Non-Laravel stacks.
- Auto-re-trigger without human approval.
