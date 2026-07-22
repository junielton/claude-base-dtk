# Scaffold-Design-Panel + Manifest Infra Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `dtk:scaffold-design-panel` — a deterministic installer that gives any Laravel project the BTP-2242 design-system panel (with Figma-link, sync-badge, and props-doc features) plus the `design/manifests/` infrastructure and its shared writer script.

**Architecture:** Templates live in the plugin at `templates/design-panel/` as ready files (generalized copies of the BTP-2242 panel + new manifest-aware files). Two stdlib-only Node scripts do all the work: `write-manifest.mjs` (the single writer every skill uses) and `install-design-panel.mjs` (preflight → copy → marker-guarded route registration → report). The model's role in the skill is intake + running the installer + interpreting output.

**Tech Stack:** Node ≥ 20 (stdlib only: `node:fs`, `node:path`, `node:crypto`, `node:test`), PHP 8.4 / Laravel (templates), Blade + Tailwind v4 tokens.

**Spec:** `docs/superpowers/specs/2026-07-22-design-panel-ecosystem-design.md` (this plan covers the scaffold + manifest half; the implement-design delta and update-design are Plan 2).

## Global Constraints

- **Working repo:** `/home/junielton/Workspace/jnieltn/claude-base-dtk`. The repo has pre-existing uncommitted/staged changes that are NOT yours — **never run `git add -A` / `git add .`**; always add explicit paths.
- **Source of truth for copied templates:** the BTP-2242 worktree at `/home/junielton/Workspace/btp/dev-design-workflow/.claude/worktrees/BTP-2242-figma-code-connect-vs-skill` (referred to below as `$BTP`).
- **No npm dependencies.** The dtk repo has no `package.json`; scripts must use only Node stdlib. Tests run with `node --test`.
- **Manifest writes only via `write-manifest.mjs`.** No other code writes `design/manifests/*.json`.
- **Idempotency:** running the installer twice must be a byte-for-byte no-op (verified by test).
- **Templates are self-contained:** they must not reference anything the target project may not have (no `<x-layout>`, no `Vite::fonts()`, no project enums beyond what the templates themselves ship).
- **PHP enum cases are TitleCase.** Blade/PHP templates follow the conventions already visible in the copied files.
- `sync.lastResult` ∈ `in-sync | drifted | never-checked | unreachable` — exact strings, everywhere.

## File Structure (all inside the dtk repo unless prefixed `$BTP`)

```
templates/design-panel/
  app/Http/Controllers/DesignSystem/PanelController.php        ← copy $BTP (1 edit: pass areaKey)
  app/Http/Controllers/DesignSystem/PreviewController.php      ← copy $BTP verbatim
  app/Http/Middleware/EnsureDesignSystemEnabled.php            ← copy $BTP verbatim
  app/Support/DesignSystem/ManifestRepository.php              ← NEW
  app/View/Components/Ui/PanelNavLink.php                      ← copy $BTP verbatim
  app/Enums/Components/PanelNavLink/Variant.php                ← copy $BTP verbatim
  config/design-system.php                                     ← NEW (trimmed registry)
  routes/design-system.php                                     ← NEW
  resources/views/components/design-system/shell.blade.php     ← NEW (standalone layout)
  resources/views/components/ui/panel-nav-link.blade.php       ← copy $BTP verbatim
  resources/views/design-system/layout.blade.php               ← copy $BTP (2 edits)
  resources/views/design-system/preview.blade.php              ← copy $BTP (1 edit)
  resources/views/design-system/items/_placeholder.blade.php   ← copy $BTP verbatim
  resources/views/design-system/items/_component.blade.php     ← NEW (the 3 features)
  resources/views/design-system/items/foundations/{colors,typography,spacing,radius,shadows}.blade.php ← copy $BTP verbatim
  design/manifests/.gitkeep
  design/manifests/component-manifest.schema.json              ← NEW
  tests/Feature/DesignSystem/PanelTest.php                     ← NEW
  tests/Feature/DesignSystem/ManifestRepositoryTest.php        ← NEW
bin/skill-scripts/design-panel/
  write-manifest.mjs                                           ← NEW
  install-design-panel.mjs                                     ← NEW
  tests/write-manifest.test.mjs                                ← NEW
  tests/install.test.mjs                                       ← NEW
  tests/fixtures/button-figma-context.txt                      ← NEW
  tests/fixtures/button-tokens.json                            ← NEW
skills/scaffold-design-panel/SKILL.md                          ← NEW
.claude-plugin/plugin.json                                     ← version bump only
```

---

### Task 1: `write-manifest.mjs` — the shared manifest writer

**Files:**
- Create: `bin/skill-scripts/design-panel/write-manifest.mjs`
- Create: `bin/skill-scripts/design-panel/tests/write-manifest.test.mjs`
- Create: `bin/skill-scripts/design-panel/tests/fixtures/button-figma-context.txt`
- Create: `bin/skill-scripts/design-panel/tests/fixtures/button-tokens.json`

**Interfaces:**
- Produces (CLI, used by Task 4's SKILL.md and by Plan 2):
  - Create/update: `node write-manifest.mjs --root <projectRoot> --slug <slug> --area <area> --component <blade-name> --file-key <key> --desktop-node <id> --desktop-url <url> [--mobile-node <id> --mobile-url <url>] [--layer-name <name>] --context <file> --tokens <file> [--variable-defs <file>] [--plan <relpath>]`
  - Touch sync: `node write-manifest.mjs --root <projectRoot> --slug <slug> --touch-sync <in-sync|drifted|unreachable>`
  - Writes `<projectRoot>/design/manifests/<slug>.json`; prints the manifest JSON to stdout; exit 0 on success, exit 1 with `error:`-prefixed stderr message on validation failure.

- [ ] **Step 1: Create fixtures**

`bin/skill-scripts/design-panel/tests/fixtures/button-figma-context.txt` (a realistic trimmed `get_design_context` excerpt — the parser only needs the props type block and a `data-name`):

```
Component set: Button
data-name="Button"

type ButtonProps = { kbd?: boolean; label?: string; leftIcon?: boolean;
                     rightIcon?: boolean; size?: "Default"; state?: "Enabled"; type?: "Default" };

<button className="bg-[var(--primary,#171717)] text-[var(--primary-foreground,#FFFFFF)] rounded-lg text-sm font-medium px-4 h-9">Get started</button>
```

`bin/skill-scripts/design-panel/tests/fixtures/button-tokens.json` (shape of `extract-figma-tokens.mjs` output — colors/typography/spacing/radii keys):

```json
{
  "colors": ["primary", "primary-foreground"],
  "typography": ["text-sm", "font-medium"],
  "spacing": ["px-4", "h-9"],
  "radii": ["rounded-lg"]
}
```

- [ ] **Step 2: Write the failing tests**

`bin/skill-scripts/design-panel/tests/write-manifest.test.mjs`:

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const script = join(here, '..', 'write-manifest.mjs');
const fixtures = join(here, 'fixtures');

function run(args, opts = {}) {
  return execFileSync('node', [script, ...args], { encoding: 'utf8', ...opts });
}

function freshRoot() {
  const root = mkdtempSync(join(tmpdir(), 'wm-'));
  mkdirSync(join(root, 'design', 'manifests'), { recursive: true });
  return root;
}

const createArgs = (root) => [
  '--root', root, '--slug', 'button', '--area', 'components',
  '--component', 'ui.button', '--file-key', 'tqdTWuxkX3MgCXwJh0zgKf',
  '--desktop-node', '1154:56909', '--desktop-url', 'https://figma.com/design/x?node-id=1154-56909&m=dev',
  '--context', join(fixtures, 'button-figma-context.txt'),
  '--tokens', join(fixtures, 'button-tokens.json'),
  '--plan', 'docs/plans/2026-07-20-implement-button.md',
];

test('creates a valid manifest from fixtures', () => {
  const root = freshRoot();
  run(createArgs(root));
  const m = JSON.parse(readFileSync(join(root, 'design/manifests/button.json'), 'utf8'));
  assert.equal(m.component, 'ui.button');
  assert.deepEqual(m.registry, { area: 'components', item: 'button' });
  assert.equal(m.figma.desktop.nodeId, '1154:56909');
  assert.equal(m.figma.desktop.layerName, 'Button');       // parsed from data-name
  assert.equal(m.figma.mobile, null);
  assert.deepEqual(m.api.props.map((p) => p.name).sort(),
    ['kbd', 'label', 'leftIcon', 'rightIcon', 'size', 'state', 'type'].sort());
  assert.deepEqual(m.tokens.colors, ['primary', 'primary-foreground']);
  assert.equal(m.sync.lastResult, 'in-sync');
  assert.ok(m.sync.implementedAt);
  assert.equal(m.plan, 'docs/plans/2026-07-20-implement-button.md');
});

test('rejects a create call missing required fields', () => {
  const root = freshRoot();
  assert.throws(
    () => run(['--root', root, '--slug', 'button', '--area', 'components']),
    (e) => e.status === 1 && /error: missing/.test(e.stderr),
  );
});

test('touch-sync updates only sync fields and preserves the rest', () => {
  const root = freshRoot();
  run(createArgs(root));
  const before = JSON.parse(readFileSync(join(root, 'design/manifests/button.json'), 'utf8'));
  run(['--root', root, '--slug', 'button', '--touch-sync', 'drifted']);
  const after = JSON.parse(readFileSync(join(root, 'design/manifests/button.json'), 'utf8'));
  assert.equal(after.sync.lastResult, 'drifted');
  assert.ok(after.sync.lastCheckedAt >= before.sync.lastCheckedAt);
  assert.deepEqual(after.api, before.api);
  assert.deepEqual(after.figma, before.figma);
});

test('touch-sync rejects an unknown result value', () => {
  const root = freshRoot();
  run(createArgs(root));
  assert.throws(
    () => run(['--root', root, '--slug', 'button', '--touch-sync', 'weird']),
    (e) => e.status === 1 && /error: invalid --touch-sync/.test(e.stderr),
  );
});

test('touch-sync on a missing manifest fails cleanly', () => {
  const root = freshRoot();
  assert.throws(
    () => run(['--root', root, '--slug', 'ghost', '--touch-sync', 'in-sync']),
    (e) => e.status === 1 && /error: no manifest/.test(e.stderr),
  );
});

test('re-running create updates in place and resets sync', () => {
  const root = freshRoot();
  run(createArgs(root));
  run(['--root', root, '--slug', 'button', '--touch-sync', 'drifted']);
  run(createArgs(root));
  const m = JSON.parse(readFileSync(join(root, 'design/manifests/button.json'), 'utf8'));
  assert.equal(m.sync.lastResult, 'in-sync');
});
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd /home/junielton/Workspace/jnieltn/claude-base-dtk && node --test bin/skill-scripts/design-panel/tests/write-manifest.test.mjs`
Expected: FAIL — cannot find module `write-manifest.mjs`.

- [ ] **Step 4: Implement `write-manifest.mjs`**

```js
#!/usr/bin/env node
/**
 * The ONLY writer of design/manifests/<slug>.json. Used by
 * scaffold-design-panel (backfill via Plan 2), implement-design (Phase 7),
 * and update-design (sync touches). Node stdlib only.
 */
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const SYNC_RESULTS = ['in-sync', 'drifted', 'never-checked', 'unreachable'];

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 2) {
    if (!argv[i].startsWith('--')) fail(`unexpected argument ${argv[i]}`);
    args[argv[i].slice(2)] = argv[i + 1];
  }
  return args;
}

function fail(msg) {
  process.stderr.write(`error: ${msg}\n`);
  process.exit(1);
}

/** `type XProps = { kbd?: boolean; label?: string; ... }` → [{name, type}] */
function parseProps(context) {
  const m = context.match(/type \w+Props = \{([\s\S]*?)\};/);
  if (!m) return [];
  return m[1]
    .split(';')
    .map((s) => s.trim())
    .filter(Boolean)
    .map((s) => {
      const [, name, opt, type] = s.match(/^(\w+)(\?)?:\s*(.+)$/) ?? [];
      return name ? { name, type: `${opt ? '?' : ''}${type.trim()}` } : null;
    })
    .filter(Boolean);
}

function parseLayerName(context) {
  return context.match(/data-name="([^"]+)"/)?.[1] ?? null;
}

function sha256(text) {
  return `sha256:${createHash('sha256').update(text).digest('hex')}`;
}

function manifestPath(root, slug) {
  return join(root, 'design', 'manifests', `${slug}.json`);
}

function save(root, slug, manifest) {
  mkdirSync(join(root, 'design', 'manifests'), { recursive: true });
  writeFileSync(manifestPath(root, slug), JSON.stringify(manifest, null, 2) + '\n');
  process.stdout.write(JSON.stringify(manifest, null, 2) + '\n');
}

const args = parseArgs(process.argv.slice(2));
for (const key of ['root', 'slug']) {
  if (!args[key]) fail(`missing --${key}`);
}

if (args['touch-sync']) {
  if (!SYNC_RESULTS.includes(args['touch-sync']) || args['touch-sync'] === 'never-checked') {
    fail(`invalid --touch-sync value "${args['touch-sync']}" (use in-sync|drifted|unreachable)`);
  }
  const path = manifestPath(args.root, args.slug);
  if (!existsSync(path)) fail(`no manifest at ${path}`);
  const manifest = JSON.parse(readFileSync(path, 'utf8'));
  manifest.sync.lastResult = args['touch-sync'];
  manifest.sync.lastCheckedAt = new Date().toISOString();
  save(args.root, args.slug, manifest);
  process.exit(0);
}

for (const key of ['area', 'component', 'file-key', 'desktop-node', 'desktop-url', 'context', 'tokens']) {
  if (!args[key]) fail(`missing --${key}`);
}

const context = readFileSync(args.context, 'utf8');
const tokens = JSON.parse(readFileSync(args.tokens, 'utf8'));
const existing = existsSync(manifestPath(args.root, args.slug))
  ? JSON.parse(readFileSync(manifestPath(args.root, args.slug), 'utf8'))
  : null;
const now = new Date().toISOString();

const manifest = {
  $schema: './component-manifest.schema.json',
  component: args.component,
  registry: { area: args.area, item: args.slug },
  figma: {
    fileKey: args['file-key'],
    desktop: {
      nodeId: args['desktop-node'],
      url: args['desktop-url'],
      layerName: args['layer-name'] ?? parseLayerName(context),
    },
    mobile: args['mobile-node']
      ? { nodeId: args['mobile-node'], url: args['mobile-url'] ?? null, layerName: null }
      : null,
  },
  api: {
    props: parseProps(context),
    variants: existing?.api?.variants ?? null,
    slots: existing?.api?.slots ?? ['default'],
  },
  tokens: {
    colors: tokens.colors ?? [],
    typography: tokens.typography ?? [],
    spacing: tokens.spacing ?? [],
    radius: tokens.radii ?? tokens.radius ?? [],
  },
  variableDefsHash: args['variable-defs'] ? sha256(readFileSync(args['variable-defs'], 'utf8')) : null,
  sync: {
    lastCheckedAt: now,
    lastResult: 'in-sync',
    implementedAt: existing?.sync?.implementedAt ?? now.slice(0, 10),
  },
  plan: args.plan ?? existing?.plan ?? null,
};

if (!manifest.figma.desktop.layerName) fail('missing --layer-name and no data-name found in context');
save(args.root, args.slug, manifest);
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `node --test bin/skill-scripts/design-panel/tests/write-manifest.test.mjs`
Expected: 6 passing.

- [ ] **Step 6: Commit**

```bash
cd /home/junielton/Workspace/jnieltn/claude-base-dtk
git add bin/skill-scripts/design-panel/write-manifest.mjs bin/skill-scripts/design-panel/tests
git commit -m "feat(design-panel): add write-manifest.mjs, the single manifest writer" \
  -- bin/skill-scripts/design-panel
```

---

### Task 2: The template tree

**Files:** everything under `templates/design-panel/` in the File Structure map. Copy sources are exact `$BTP` paths.

**Interfaces:**
- Produces: the template tree Task 3's installer copies. Blade view names and PHP namespaces are contract: `App\Support\DesignSystem\ManifestRepository::find(string $area, string $item): ?array`, config keys `design-system.enabled`, `design-system.areas`, `design-system.manifests` (relative path string), `design-system.icons`.
- Registry entry contract (consumed by everything): `['label' => string, 'view' => string, 'preview' => ?string, 'previewProps' => ?array, 'scripts' => ?bool, 'showcase' => ?string]` — `view` defaults to `design-system.items._component` for components; `showcase` is an optional extra view included inside the default page.

- [ ] **Step 1: Copy the verbatim files**

```bash
BTP=/home/junielton/Workspace/btp/dev-design-workflow/.claude/worktrees/BTP-2242-figma-code-connect-vs-skill
T=templates/design-panel
mkdir -p $T/app/Http/Controllers/DesignSystem $T/app/Http/Middleware \
  $T/app/Support/DesignSystem $T/app/View/Components/Ui $T/app/Enums/Components/PanelNavLink \
  $T/config $T/routes $T/resources/views/components/design-system \
  $T/resources/views/components/ui $T/resources/views/design-system/items/foundations \
  $T/design/manifests $T/tests/Feature/DesignSystem
cp $BTP/app/Http/Controllers/DesignSystem/PreviewController.php $T/app/Http/Controllers/DesignSystem/
cp $BTP/app/Http/Middleware/EnsureDesignSystemEnabled.php $T/app/Http/Middleware/
cp $BTP/app/View/Components/Ui/PanelNavLink.php $T/app/View/Components/Ui/
cp $BTP/app/Enums/Components/PanelNavLink/Variant.php $T/app/Enums/Components/PanelNavLink/
cp $BTP/resources/views/components/ui/panel-nav-link.blade.php $T/resources/views/components/ui/
cp $BTP/resources/views/design-system/items/_placeholder.blade.php $T/resources/views/design-system/items/
cp $BTP/resources/views/design-system/items/foundations/*.blade.php $T/resources/views/design-system/items/foundations/
touch $T/design/manifests/.gitkeep
```

- [ ] **Step 2: Copy `PanelController.php` with one edit**

Copy `$BTP/app/Http/Controllers/DesignSystem/PanelController.php`, then in the `view(...)` call add `'areaKey' => $areaKey` — it is already passed; verify the layout include below receives it. No other change. (If the copied file already passes `areaKey`, this step is a verification only.)

- [ ] **Step 3: Create `routes/design-system.php`**

```php
<?php

use App\Http\Controllers\DesignSystem\PanelController;
use App\Http\Controllers\DesignSystem\PreviewController;
use App\Http\Middleware\EnsureDesignSystemEnabled;
use Illuminate\Support\Facades\Route;

Route::middleware(EnsureDesignSystemEnabled::class)->group(function () {
    Route::get('/design-system/preview/{area}/{item}', PreviewController::class)
        ->name('design-system.preview');

    Route::get('/design-system/{area?}/{item?}', PanelController::class)
        ->name('design-system');
});
```

- [ ] **Step 4: Create the standalone shell** — `resources/views/components/design-system/shell.blade.php`

The template must not depend on the project's `<x-layout>` (BTP's uses a `Vite::fonts()` macro other projects won't have):

```blade
@props([
    'title' => null,
    'scripts' => false,
])

<!DOCTYPE html>
<html lang="{{ str_replace('_', '-', app()->getLocale()) }}">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{{ $title ? $title . ' — ' . config('app.name') : config('app.name') }}</title>
    @vite(array_filter(['resources/css/app.css', $scripts ? 'resources/js/app.js' : null]))
</head>
<body {{ $attributes->class('bg-background text-foreground') }}>
    {{ $slot }}
</body>
</html>
```

- [ ] **Step 5: Create `layout.blade.php` and `preview.blade.php` from the BTP versions**

`resources/views/design-system/layout.blade.php` — same as `$BTP`'s, with the wrapper swapped to the shell and `areaKey` passed into the item include:

```blade
<x-design-system.shell :title="'Design System · ' . $item['label']" :scripts="$item['scripts'] ?? false" class="min-h-screen">

    <header class="sticky top-0 z-10 border-b border-border bg-background">
        <div class="flex h-16 items-center gap-6 px-6">
            <a href="{{ route('design-system') }}"
                class="whitespace-nowrap rounded-md text-base font-medium outline-none focus-visible:ring-2 focus-visible:ring-foreground">
                {{ config('app.name') }} <span class="text-muted-foreground">/ Design System</span>
            </a>
            <nav class="flex items-center gap-1 overflow-x-auto" aria-label="Design system areas">
                @foreach ($areas as $key => $area)
                    <x-ui.panel-nav-link variant="topbar" :href="route('design-system', $key)" :active="$key === $areaKey">
                        {{ $area['label'] }}
                    </x-ui.panel-nav-link>
                @endforeach
            </nav>
        </div>
    </header>

    <div class="flex">
        <aside class="min-h-[calc(100vh-4rem)] w-56 shrink-0 border-r border-border p-4">
            <p class="px-3 pb-2 text-sm uppercase tracking-widest text-muted-foreground">
                {{ $areas[$areaKey]['label'] }}
            </p>
            <nav class="flex flex-col gap-0.5" aria-label="{{ $areas[$areaKey]['label'] }} items">
                @foreach ($areas[$areaKey]['items'] as $key => $entry)
                    <x-ui.panel-nav-link variant="sidebar" :href="route('design-system', [$areaKey, $key])" :active="$key === $itemKey">
                        {{ $entry['label'] }}
                    </x-ui.panel-nav-link>
                @endforeach
            </nav>
        </aside>

        <main class="max-w-4xl flex-1 px-10 py-12">
            @include($item['view'], [
                'itemLabel' => $item['label'],
                'itemKey' => $itemKey,
                'areaKey' => $areaKey,
                'item' => $item,
            ])
        </main>
    </div>
</x-design-system.shell>
```

`resources/views/design-system/preview.blade.php`:

```blade
@use('Illuminate\View\ComponentAttributeBag')

<x-design-system.shell :title="'Preview · ' . $label" :scripts="$scripts ?? false">
    <x-dynamic-component :component="$previewComponent" :attributes="new ComponentAttributeBag($props ?? [])" />
</x-design-system.shell>
```

- [ ] **Step 6: Create `config/design-system.php`** (trimmed: foundations only, empty components area, panel-chrome docs preserved)

```php
<?php

return [
    /*
     * Gates the whole panel. A config flag rather than an isProduction()
     * check because staging environments often run APP_ENV=production and
     * are exactly where the team needs the panel.
     */
    'enabled' => (bool) env('DESIGN_SYSTEM_ENABLED', env('APP_ENV') !== 'production'),

    /*
     * Where component manifests live, relative to base_path(). Written only
     * by dtk's write-manifest.mjs; read by ManifestRepository.
     */
    'manifests' => 'design/manifests',

    /*
     * Drives the panel topbar (areas) and sidebar (items). Adding a
     * component is a registry entry, not a route. Keys per item:
     *   view          Blade view for the showcase page. Components should use
     *                 'design-system.items._component' (manifest-aware default).
     *   showcase      optional extra view @included inside the default page.
     *   preview       <x-dynamic-component> name rendered standalone by the
     *                 preview route (without it, preview 404s).
     *   previewProps  extra props for the preview component.
     *   scripts       true opts the page into the JS bundle.
     */
    'areas' => [
        'foundations' => [
            'label' => 'Foundations',
            'items' => [
                'colors' => ['label' => 'Colors', 'view' => 'design-system.items.foundations.colors'],
                'typography' => ['label' => 'Typography', 'view' => 'design-system.items.foundations.typography'],
                'spacing' => ['label' => 'Spacing', 'view' => 'design-system.items.foundations.spacing'],
                'radius' => ['label' => 'Radius', 'view' => 'design-system.items.foundations.radius'],
                'shadows' => ['label' => 'Shadows', 'view' => 'design-system.items.foundations.shadows'],
            ],
        ],

        'components' => [
            'label' => 'Components',
            'items' => [
                // Populated by dtk:implement-design. Example:
                // 'button' => [
                //     'label' => 'Button',
                //     'view' => 'design-system.items._component',
                //     'preview' => 'ui.button',
                //     'previewProps' => ['label' => 'Get started'],
                // ],
            ],
        ],
    ],

    /*
     * Icon registry: each entry maps to <x-ui.icons.{name}> plus a category
     * for the panel's icon pages. Populated as components need icons.
     */
    'icons' => [],
];
```

- [ ] **Step 7: Create `ManifestRepository.php`**

`app/Support/DesignSystem/ManifestRepository.php`:

```php
<?php

namespace App\Support\DesignSystem;

use Illuminate\Support\Facades\Log;

class ManifestRepository
{
    /**
     * Find the manifest for a registry entry, or null when the component has
     * none yet. A malformed manifest is skipped (and logged) — it must never
     * break the panel.
     *
     * @return array<string, mixed>|null
     */
    public function find(string $area, string $item): ?array
    {
        foreach ($this->all() as $manifest) {
            if (($manifest['registry']['area'] ?? null) === $area
                && ($manifest['registry']['item'] ?? null) === $item) {
                return $manifest;
            }
        }

        return null;
    }

    /**
     * @return list<array<string, mixed>>
     */
    public function all(): array
    {
        $dir = base_path(config('design-system.manifests'));
        $manifests = [];

        foreach (glob($dir.'/*.json') ?: [] as $path) {
            if (str_ends_with($path, '.schema.json')) {
                continue;
            }
            $manifest = $this->read($path);
            if ($manifest !== null) {
                $manifests[] = $manifest;
            }
        }

        return $manifests;
    }

    /**
     * @return array<string, mixed>|null
     */
    private function read(string $path): ?array
    {
        $data = json_decode((string) file_get_contents($path), true);

        if (! is_array($data)
            || ! is_string($data['component'] ?? null)
            || ! is_array($data['registry'] ?? null)
            || ! is_string($data['figma']['fileKey'] ?? null)) {
            Log::warning("design-system: ignoring malformed manifest at {$path}");

            return null;
        }

        return $data;
    }
}
```

- [ ] **Step 8: Create `_component.blade.php`** — the manifest-aware default page (the 3 features)

`resources/views/design-system/items/_component.blade.php`:

```blade
@use('App\Support\DesignSystem\ManifestRepository')

@php
    $manifest = app(ManifestRepository::class)->find($areaKey, $itemKey);
    $sync = $manifest['sync'] ?? null;
    $badge = match ($sync['lastResult'] ?? 'never-checked') {
        'in-sync' => ['label' => 'In sync', 'classes' => 'bg-green-100 text-green-800'],
        'drifted' => ['label' => 'Figma drifted', 'classes' => 'bg-amber-100 text-amber-800'],
        'unreachable' => ['label' => 'Node unreachable', 'classes' => 'bg-red-100 text-red-800'],
        default => ['label' => 'Never checked', 'classes' => 'bg-secondary text-muted-foreground'],
    };
@endphp

<section class="space-y-8">
    <header class="space-y-2">
        <div class="flex items-center gap-3">
            <h2 class="text-3xl font-medium tracking-tight">{{ $itemLabel }}</h2>
            <span class="rounded-full px-2.5 py-0.5 text-xs font-medium {{ $badge['classes'] }}"
                @if ($sync['lastCheckedAt'] ?? false) title="Last checked {{ $sync['lastCheckedAt'] }}" @endif
            >{{ $badge['label'] }}</span>
        </div>
        @if ($manifest && ($manifest['figma']['desktop']['url'] ?? false))
            <a href="{{ $manifest['figma']['desktop']['url'] }}" target="_blank" rel="noopener"
                class="inline-flex items-center gap-1 text-sm text-muted-foreground underline-offset-4 hover:underline focus-visible:ring-2 focus-visible:ring-foreground">
                Open in Figma ↗
            </a>
        @endif
    </header>

    @isset($item['preview'])
        <div class="rounded-lg border border-border p-8">
            <x-dynamic-component :component="$item['preview']"
                :attributes="new Illuminate\View\ComponentAttributeBag($item['previewProps'] ?? [])" />
        </div>
    @endisset

    @if ($manifest && ! empty($manifest['api']['props']))
        <div class="space-y-3">
            <h3 class="text-lg font-medium">API</h3>
            <table class="w-full text-left text-sm">
                <thead class="text-muted-foreground">
                    <tr><th class="py-1.5 pr-6 font-medium">Prop</th><th class="py-1.5 font-medium">Type</th></tr>
                </thead>
                <tbody>
                    @foreach ($manifest['api']['props'] as $prop)
                        <tr class="border-t border-border">
                            <td class="py-1.5 pr-6 font-mono">{{ $prop['name'] }}</td>
                            <td class="py-1.5 font-mono text-muted-foreground">{{ $prop['type'] }}</td>
                        </tr>
                    @endforeach
                    @if ($manifest['api']['variants']['cases'] ?? false)
                        <tr class="border-t border-border">
                            <td class="py-1.5 pr-6 font-mono">variant</td>
                            <td class="py-1.5 font-mono text-muted-foreground">{{ implode(' | ', $manifest['api']['variants']['cases']) }}</td>
                        </tr>
                    @endif
                </tbody>
            </table>
        </div>
    @endif

    @isset($item['showcase'])
        @include($item['showcase'], ['itemLabel' => $itemLabel, 'itemKey' => $itemKey, 'areaKey' => $areaKey])
    @endisset
</section>
```

- [ ] **Step 9: Create the JSON Schema** — `design/manifests/component-manifest.schema.json`

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "dtk component manifest",
  "type": "object",
  "required": ["component", "registry", "figma", "api", "tokens", "sync"],
  "properties": {
    "component": { "type": "string" },
    "registry": {
      "type": "object",
      "required": ["area", "item"],
      "properties": { "area": { "type": "string" }, "item": { "type": "string" } }
    },
    "figma": {
      "type": "object",
      "required": ["fileKey", "desktop"],
      "properties": {
        "fileKey": { "type": "string" },
        "desktop": { "$ref": "#/$defs/node" },
        "mobile": { "oneOf": [{ "$ref": "#/$defs/node" }, { "type": "null" }] }
      }
    },
    "api": {
      "type": "object",
      "properties": {
        "props": { "type": "array", "items": { "type": "object", "required": ["name", "type"] } },
        "variants": { "type": ["object", "null"] },
        "slots": { "type": "array", "items": { "type": "string" } }
      }
    },
    "tokens": { "type": "object" },
    "variableDefsHash": { "type": ["string", "null"] },
    "sync": {
      "type": "object",
      "required": ["lastResult"],
      "properties": {
        "lastResult": { "enum": ["in-sync", "drifted", "never-checked", "unreachable"] },
        "lastCheckedAt": { "type": "string" },
        "implementedAt": { "type": "string" }
      }
    },
    "plan": { "type": ["string", "null"] }
  },
  "$defs": {
    "node": {
      "type": "object",
      "required": ["nodeId"],
      "properties": {
        "nodeId": { "type": "string" },
        "url": { "type": ["string", "null"] },
        "layerName": { "type": ["string", "null"] }
      }
    }
  }
}
```

- [ ] **Step 10: Create the installed feature tests**

`tests/Feature/DesignSystem/PanelTest.php`:

```php
<?php

namespace Tests\Feature\DesignSystem;

use Tests\TestCase;

class PanelTest extends TestCase
{
    public function test_panel_renders_the_first_area_and_item(): void
    {
        config(['design-system.enabled' => true]);

        $this->get('/design-system')->assertOk()->assertSee('Foundations');
    }

    public function test_unknown_area_404s(): void
    {
        config(['design-system.enabled' => true]);

        $this->get('/design-system/nope')->assertNotFound();
    }

    public function test_preview_404s_without_a_preview_key(): void
    {
        config(['design-system.enabled' => true]);

        $this->get('/design-system/preview/foundations/colors')->assertNotFound();
    }

    public function test_panel_is_hidden_when_disabled(): void
    {
        config(['design-system.enabled' => false]);

        $this->get('/design-system')->assertNotFound();
    }
}
```

`tests/Feature/DesignSystem/ManifestRepositoryTest.php`:

```php
<?php

namespace Tests\Feature\DesignSystem;

use App\Support\DesignSystem\ManifestRepository;
use Illuminate\Support\Facades\File;
use Tests\TestCase;

class ManifestRepositoryTest extends TestCase
{
    private string $dir;

    protected function setUp(): void
    {
        parent::setUp();
        $this->dir = 'design/manifests-test-'.uniqid();
        config(['design-system.manifests' => $this->dir]);
        File::makeDirectory(base_path($this->dir), recursive: true);
    }

    protected function tearDown(): void
    {
        File::deleteDirectory(base_path($this->dir));
        parent::tearDown();
    }

    public function test_finds_a_manifest_by_registry_entry(): void
    {
        File::put(base_path($this->dir.'/button.json'), json_encode([
            'component' => 'ui.button',
            'registry' => ['area' => 'components', 'item' => 'button'],
            'figma' => ['fileKey' => 'abc', 'desktop' => ['nodeId' => '1:2']],
        ]));

        $found = app(ManifestRepository::class)->find('components', 'button');

        $this->assertSame('ui.button', $found['component']);
        $this->assertNull(app(ManifestRepository::class)->find('components', 'ghost'));
    }

    public function test_malformed_manifest_is_skipped_not_fatal(): void
    {
        File::put(base_path($this->dir.'/broken.json'), '{not json');

        $this->assertSame([], app(ManifestRepository::class)->all());
    }
}
```

- [ ] **Step 11: Lint every PHP template**

Run: `find templates/design-panel -name '*.php' -not -path '*views*' -exec php -l {} \;`
Expected: `No syntax errors detected` for each file. (Blade views are exercised by Task 5.)

- [ ] **Step 12: Commit**

```bash
git add templates/design-panel
git commit -m "feat(design-panel): add the panel template tree (manifest-aware component page)" \
  -- templates/design-panel
```

---

### Task 3: `install-design-panel.mjs` — the deterministic installer

**Files:**
- Create: `bin/skill-scripts/design-panel/install-design-panel.mjs`
- Create: `bin/skill-scripts/design-panel/tests/install.test.mjs`

**Interfaces:**
- Consumes: the `templates/design-panel/` tree (Task 2), resolved relative to the script's own location.
- Produces (CLI, used by Task 4's SKILL.md): `node install-design-panel.mjs --root <projectRoot> [--force]`. Prints a JSON report `{status, created[], unchanged[], drifted[], overwritten[], edits[]}` to stdout. Exit 0 = installed/no-op; exit 1 = preflight failure (message on stderr); exit 2 = drift found without `--force` (report still printed).

- [ ] **Step 1: Write the failing tests**

`bin/skill-scripts/design-panel/tests/install.test.mjs`:

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const script = join(here, '..', 'install-design-panel.mjs');

function run(args, allowFailure = false) {
  try {
    return { out: execFileSync('node', [script, ...args], { encoding: 'utf8' }), status: 0 };
  } catch (e) {
    if (!allowFailure) throw e;
    return { out: e.stdout ?? '', err: e.stderr ?? '', status: e.status };
  }
}

/** Minimal fake-Laravel skeleton satisfying the preflight. */
function skeleton() {
  const root = mkdtempSync(join(tmpdir(), 'laravel-'));
  writeFileSync(join(root, 'artisan'), '#!/usr/bin/env php\n');
  writeFileSync(join(root, 'composer.json'), JSON.stringify({ require: { 'laravel/framework': '^13.0' } }));
  mkdirSync(join(root, 'resources', 'css'), { recursive: true });
  writeFileSync(join(root, 'resources', 'css', 'app.css'), "@import 'tailwindcss';\n@theme static {\n  --color-primary: #171717;\n}\n");
  mkdirSync(join(root, 'routes'), { recursive: true });
  writeFileSync(join(root, 'routes', 'web.php'), "<?php\n\nRoute::view('/', 'home');\n");
  writeFileSync(join(root, '.env.example'), 'APP_NAME=Laravel\n');
  return root;
}

test('preflight rejects a non-Laravel directory', () => {
  const root = mkdtempSync(join(tmpdir(), 'not-laravel-'));
  const { status, err } = run(['--root', root], true);
  assert.equal(status, 1);
  assert.match(err, /preflight/);
});

test('fresh install copies templates, registers routes, seeds env', () => {
  const root = skeleton();
  const report = JSON.parse(run(['--root', root]).out);
  assert.equal(report.status, 'installed');
  assert.ok(existsSync(join(root, 'app/Http/Controllers/DesignSystem/PanelController.php')));
  assert.ok(existsSync(join(root, 'config/design-system.php')));
  assert.ok(existsSync(join(root, 'design/manifests/component-manifest.schema.json')));
  assert.ok(existsSync(join(root, 'tests/Feature/DesignSystem/PanelTest.php')));
  const web = readFileSync(join(root, 'routes/web.php'), 'utf8');
  assert.match(web, /dtk:design-system routes/);
  assert.match(web, /design-system\.php/);
  assert.match(readFileSync(join(root, '.env.example'), 'utf8'), /DESIGN_SYSTEM_ENABLED=true/);
});

test('second run is a byte-for-byte no-op', () => {
  const root = skeleton();
  run(['--root', root]);
  const webBefore = readFileSync(join(root, 'routes/web.php'), 'utf8');
  const report = JSON.parse(run(['--root', root]).out);
  assert.equal(report.status, 'up-to-date');
  assert.equal(report.created.length, 0);
  assert.equal(readFileSync(join(root, 'routes/web.php'), 'utf8'), webBefore);
});

test('modified existing file is reported as drift, not overwritten', () => {
  const root = skeleton();
  run(['--root', root]);
  const target = join(root, 'config/design-system.php');
  writeFileSync(target, "<?php return ['enabled' => true];\n");
  const { out, status } = run(['--root', root], true);
  assert.equal(status, 2);
  const report = JSON.parse(out);
  assert.deepEqual(report.drifted, ['config/design-system.php']);
  assert.match(readFileSync(target, 'utf8'), /return \['enabled' => true\]/);
});

test('--force overwrites drifted files', () => {
  const root = skeleton();
  run(['--root', root]);
  writeFileSync(join(root, 'config/design-system.php'), '<?php return [];\n');
  const report = JSON.parse(run(['--root', root, '--force']).out);
  assert.deepEqual(report.overwritten, ['config/design-system.php']);
  assert.match(readFileSync(join(root, 'config/design-system.php'), 'utf8'), /design-system\.manifests|'manifests'/);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test bin/skill-scripts/design-panel/tests/install.test.mjs`
Expected: FAIL — cannot find `install-design-panel.mjs`.

- [ ] **Step 3: Implement `install-design-panel.mjs`**

```js
#!/usr/bin/env node
/**
 * Deterministic, idempotent installer for the dtk design-system panel.
 * Copies templates/design-panel/ into a Laravel project, registers the
 * routes file behind a marker, and seeds the env gate. Node stdlib only.
 */
import { existsSync, mkdirSync, readFileSync, writeFileSync, readdirSync, statSync, appendFileSync } from 'node:fs';
import { join, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const MARKER = '// dtk:design-system routes';
const here = dirname(fileURLToPath(import.meta.url));
const templateRoot = join(here, '..', '..', '..', 'templates', 'design-panel');

const args = process.argv.slice(2);
const force = args.includes('--force');
const rootIdx = args.indexOf('--root');
if (rootIdx === -1 || !args[rootIdx + 1]) {
  process.stderr.write('error: missing --root <projectRoot>\n');
  process.exit(1);
}
const root = args[rootIdx + 1];

function preflightFail(reason) {
  process.stderr.write(`preflight failed: ${reason}\n`);
  process.exit(1);
}

// --- Preflight -------------------------------------------------------------
if (!existsSync(join(root, 'artisan'))) preflightFail(`no artisan file in ${root} — not a Laravel project`);
const composer = existsSync(join(root, 'composer.json'))
  ? JSON.parse(readFileSync(join(root, 'composer.json'), 'utf8'))
  : null;
if (!composer?.require?.['laravel/framework']) preflightFail('composer.json does not require laravel/framework');
const appCssPath = join(root, 'resources', 'css', 'app.css');
if (!existsSync(appCssPath)) preflightFail('resources/css/app.css not found');
if (!/@theme/.test(readFileSync(appCssPath, 'utf8'))) {
  preflightFail('resources/css/app.css has no @theme block — the panel needs Tailwind v4 design tokens');
}
if (!existsSync(join(root, 'routes', 'web.php'))) preflightFail('routes/web.php not found');

// --- Copy templates --------------------------------------------------------
function* walk(dir) {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) yield* walk(full);
    else yield full;
  }
}

const report = { status: 'installed', created: [], unchanged: [], drifted: [], overwritten: [], edits: [] };

for (const src of walk(templateRoot)) {
  const rel = relative(templateRoot, src);
  const dest = join(root, rel);
  const content = readFileSync(src);
  if (!existsSync(dest)) {
    mkdirSync(dirname(dest), { recursive: true });
    writeFileSync(dest, content);
    report.created.push(rel);
  } else if (readFileSync(dest).equals(content)) {
    report.unchanged.push(rel);
  } else if (force) {
    writeFileSync(dest, content);
    report.overwritten.push(rel);
  } else {
    report.drifted.push(rel);
  }
}

// --- Marker-guarded route registration ------------------------------------
const webPath = join(root, 'routes', 'web.php');
const web = readFileSync(webPath, 'utf8');
if (!web.includes(MARKER)) {
  appendFileSync(webPath, `\n${MARKER}\nrequire __DIR__.'/design-system.php';\n`);
  report.edits.push('routes/web.php');
}

// --- Env gate --------------------------------------------------------------
const envExample = join(root, '.env.example');
if (existsSync(envExample) && !readFileSync(envExample, 'utf8').includes('DESIGN_SYSTEM_ENABLED')) {
  appendFileSync(envExample, 'DESIGN_SYSTEM_ENABLED=true\n');
  report.edits.push('.env.example');
}

// --- Report ----------------------------------------------------------------
if (report.created.length === 0 && report.overwritten.length === 0
  && report.edits.length === 0 && report.drifted.length === 0) {
  report.status = 'up-to-date';
}
process.stdout.write(JSON.stringify(report, null, 2) + '\n');
process.exit(report.drifted.length > 0 ? 2 : 0);
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test bin/skill-scripts/design-panel/tests/install.test.mjs`
Expected: 5 passing.

- [ ] **Step 5: Run the full script test suite** (regression across Task 1 + 3)

Run: `node --test bin/skill-scripts/design-panel/tests/`
Expected: 11 passing.

- [ ] **Step 6: Commit**

```bash
git add bin/skill-scripts/design-panel/install-design-panel.mjs bin/skill-scripts/design-panel/tests/install.test.mjs
git commit -m "feat(design-panel): add the deterministic panel installer" \
  -- bin/skill-scripts/design-panel
```

---

### Task 4: `skills/scaffold-design-panel/SKILL.md` + plugin registration

**Files:**
- Create: `skills/scaffold-design-panel/SKILL.md`
- Modify: `.claude-plugin/plugin.json` (version `1.4.0` → `1.5.0` — touch ONLY the version field; the file has unrelated local modifications)

**Interfaces:**
- Consumes: the installer and writer CLIs exactly as specified in Tasks 1 and 3.

- [ ] **Step 1: Write `SKILL.md`**

```markdown
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
```

- [ ] **Step 2: Bump the plugin version**

In `.claude-plugin/plugin.json`, change `"version": "1.4.0"` to `"version": "1.5.0"`. Make no other edit to this file (it carries unrelated local modifications).

- [ ] **Step 3: Commit**

```bash
git add skills/scaffold-design-panel/SKILL.md .claude-plugin/plugin.json
git commit -m "feat: add the scaffold-design-panel skill" \
  -- skills/scaffold-design-panel .claude-plugin/plugin.json
```

Note: committing `.claude-plugin/plugin.json` by pathspec will include its pre-existing local modifications. **Before this commit**, show the user `git diff HEAD -- .claude-plugin/plugin.json` and confirm; if the unrelated changes shouldn't ride along, stash them first (`git stash push -- .claude-plugin/plugin.json`, re-apply the version bump, commit, `git stash pop`).

---

### Task 5: End-to-end prove-out against a real Laravel app

**Files:** none committed (scratch only). Requires network + composer; if unavailable, skip and state so in the final report.

- [ ] **Step 1: Create a disposable Laravel app**

```bash
cd "$SCRATCHPAD"   # the session scratchpad dir
composer create-project laravel/laravel panel-e2e --no-interaction --quiet
cd panel-e2e
```

- [ ] **Step 2: Give it a minimal `@theme`** (fresh Laravel has Tailwind v4 but may lack tokens the foundations pages read)

Append to `resources/css/app.css`:

```css
@theme static {
    --color-background: #ffffff;
    --color-foreground: #0a0a0a;
    --color-border: #e4e4e7;
    --color-secondary: #f4f4f5;
    --color-muted-foreground: #71717a;
}
```

- [ ] **Step 3: Run the installer, tests, and smoke test**

```bash
node /home/junielton/Workspace/jnieltn/claude-base-dtk/bin/skill-scripts/design-panel/install-design-panel.mjs --root "$PWD"
php artisan test --compact tests/Feature/DesignSystem   # expect: all pass
npm install --silent && npm run build --silent
php artisan serve --port 8199 &
sleep 2
curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8199/design-system          # expect 200
curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8199/design-system/nope     # expect 404
kill %1
```

- [ ] **Step 4: Re-run the installer to prove idempotency on a real app**

```bash
node /home/junielton/Workspace/jnieltn/claude-base-dtk/bin/skill-scripts/design-panel/install-design-panel.mjs --root "$PWD"
```

Expected: `"status": "up-to-date"`, empty `created`/`edits`.

- [ ] **Step 5: Clean up and record**

Delete the scratch app. If any step failed, fix the template/installer in the dtk repo (with a matching regression test where the failure was in script logic), re-run, and only then finish. Add one line with the E2E outcome to the final report.

---

## Self-Review Notes (already applied)

- Spec coverage: manifest schema (T2/S9), shared writer (T1), templates incl. 3 panel features (T2/S8), installer preflight/idempotency/marker/env-gate/smoke (T3, T5, SKILL Phase 3), installed feature tests (T2/S10), malformed-manifest guardrail (T2/S7 + test), version bump (T4). Deferred to Plan 2 per spec: implement-design Phase 7, update-design (all modes), backfill.
- `sync.lastResult` strings consistent across writer, badge view, schema.
- Writer arg names consistent between Task 1 tests, implementation, and SKILL.md.
```
