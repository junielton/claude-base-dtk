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
  writeFileSync(
    join(root, 'resources', 'css', 'app.css'),
    "@import 'tailwindcss';\n@theme static {\n"
      + '  --color-primary: #171717;\n'
      + '  --color-background: #ffffff;\n'
      + '  --color-foreground: #0a0a0a;\n'
      + '  --color-border: #e5e5e5;\n'
      + '  --color-secondary: #f5f5f5;\n'
      + '  --color-muted-foreground: #737373;\n'
      + '}\n',
  );
  mkdirSync(join(root, 'routes'), { recursive: true });
  writeFileSync(join(root, 'routes', 'web.php'), "<?php\n\nRoute::view('/', 'home');\n");
  writeFileSync(join(root, '.env.example'), 'APP_NAME=Laravel\n');
  return root;
}

/** Same as skeleton(), but app.css declares only --color-primary — used to
 *  exercise the chrome-token warning path. */
function minimalSkeleton() {
  const root = mkdtempSync(join(tmpdir(), 'laravel-minimal-'));
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

test('preflight fails cleanly on malformed composer.json', () => {
  const root = skeleton();
  writeFileSync(join(root, 'composer.json'), '{not json');
  const { status, err } = run(['--root', root], true);
  assert.equal(status, 1);
  assert.match(err, /preflight failed/);
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

test('installed PanelTest disables Vite so it passes before assets are built', () => {
  // Regression: the panel shell renders @vite(...), so a fresh app that hasn't
  // run `npm run build` yet throws ViteManifestNotFoundException unless the
  // installed test opts out with withoutVite(). Caught by the real E2E run
  // (Task 5), not by this script's own fixtures, since it needs actual PHPUnit
  // against a real Laravel app to surface.
  const root = skeleton();
  run(['--root', root]);
  const panelTest = readFileSync(join(root, 'tests/Feature/DesignSystem/PanelTest.php'), 'utf8');
  const getCalls = panelTest.match(/\$this->[^;]*->get\(/g) ?? [];
  assert.ok(getCalls.length > 0, 'expected at least one ->get( call in the installed PanelTest');
  for (const call of getCalls) {
    assert.match(call, /withoutVite\(\)/, `expected withoutVite() before: ${call}`);
  }
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

test('preflight warns, but does not abort, when app.css is missing chrome tokens', () => {
  const root = minimalSkeleton();
  const report = JSON.parse(run(['--root', root]).out);
  assert.equal(report.status, 'installed');
  assert.equal(report.warnings.length, 5);
  for (const token of [
    '--color-background',
    '--color-foreground',
    '--color-border',
    '--color-secondary',
    '--color-muted-foreground',
  ]) {
    assert.ok(
      report.warnings.some((w) => w.includes(token)),
      `expected a warning naming ${token}`,
    );
  }
});

test('preflight reports no warnings when app.css declares all chrome tokens', () => {
  const root = skeleton();
  const report = JSON.parse(run(['--root', root]).out);
  assert.deepEqual(report.warnings, []);
});
