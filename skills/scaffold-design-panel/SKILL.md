---
name: scaffold-design-panel
description: "Use when a Laravel project needs the dtk design-system panel installed — a /design-system showcase with per-component preview routes, Figma-link/sync/API features driven by design/manifests/. Triggers on 'scaffold the design panel', 'install the design-system panel', 'cria o painel de design system', or when dtk:implement-design finds no panel to register components into. NOT for building components (implement-design) or verifying them (dsqa)."
---

# Scaffold Design Panel

Installs the dtk design-system panel into a Laravel project. Deterministic by
design: every file is a ready template shipped with the plugin; the installer
script copies and wires them. Your job is intake, running two commands, and
interpreting their output — never authoring panel code by hand.

## Requirements (preflight enforces these)

- Laravel project (`artisan` + `laravel/framework` in composer.json)
- Tailwind v4 with an `@theme` block in `resources/css/app.css`
- Blade views (the panel ships its own standalone shell; no layout needed)

## Workflow

### Phase 1 — Intake (one question at a time)

1. "Which project root should I install into?" (default: current repo root)
2. Confirm `resources/css/app.css` declares the project's design tokens in
   `@theme` — the foundations pages render straight from those tokens.

### Phase 2 — Install

Run the installer from the plugin:

    node <plugin>/bin/skill-scripts/design-panel/install-design-panel.mjs --root <projectRoot>

Read the JSON report:

- `status: installed` — fresh install; continue to Phase 3.
- `status: up-to-date` — nothing to do; report and stop.
- exit 2 with `drifted: [...]` — files exist locally with different content.
  NEVER pass `--force` on your own: show the drifted list to the user and let
  them decide (their edits may be deliberate).
- exit 1 — preflight failure; report the reason verbatim and stop.

### Phase 3 — Prove it works

1. `php artisan test --compact tests/Feature/DesignSystem` — the installed
   feature tests must pass.
2. Boot the app (`composer run dev` or `php artisan serve`) and GET
   `/design-system` — expect 200 with the Foundations sidebar.
3. If styles are missing, check `public/hot` (stale dev-server reference) or
   run `npm run build`.

### Phase 4 — Report

Report-back checklist: files created (count), routes registered, env gate,
test results, panel URL.

## The manifest infrastructure

The install seeds `design/manifests/` (+ JSON Schema). Manifests are written
ONLY by:

    node <plugin>/bin/skill-scripts/design-panel/write-manifest.mjs --root <projectRoot> --slug <slug> ...

`dtk:implement-design` calls it after DSQA approval; `dtk:update-design`
maintains the `sync` block. Never hand-edit a manifest.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Passing `--force` without asking | Drift may be deliberate local work — always ask |
| Writing panel files by hand | Everything is a template; fix the template in the plugin instead |
| Skipping the Phase 3 smoke test | An install that never rendered is not "installed" |
| Hand-editing `design/manifests/*.json` | Only `write-manifest.mjs` writes manifests |
