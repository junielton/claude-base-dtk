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
const schemaPath = join(here, '..', '..', '..', '..', 'templates', 'design-panel', 'design', 'manifests', 'component-manifest.schema.json');

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

test('touch-sync on a corrupted manifest fails cleanly instead of throwing a raw parse trace', () => {
  const root = freshRoot();
  writeFileSync(join(root, 'design/manifests/x.json'), '{oops');
  assert.throws(
    () => run(['--root', root, '--slug', 'x', '--touch-sync', 'in-sync']),
    (e) => e.status === 1 && /error: .*not valid JSON/.test(e.stderr),
  );
});

test('touch-sync on a manifest missing the sync key still succeeds', () => {
  const root = freshRoot();
  writeFileSync(
    join(root, 'design/manifests/nosync.json'),
    JSON.stringify({ component: 'ui.nosync', registry: { area: 'components', item: 'nosync' } }),
  );
  run(['--root', root, '--slug', 'nosync', '--touch-sync', 'in-sync']);
  const m = JSON.parse(readFileSync(join(root, 'design/manifests/nosync.json'), 'utf8'));
  assert.equal(m.sync.lastResult, 'in-sync');
  assert.ok(m.sync.lastCheckedAt);
});

test('re-running create updates in place and resets sync', () => {
  const root = freshRoot();
  run(createArgs(root));
  run(['--root', root, '--slug', 'button', '--touch-sync', 'drifted']);
  run(createArgs(root));
  const m = JSON.parse(readFileSync(join(root, 'design/manifests/button.json'), 'utf8'));
  assert.equal(m.sync.lastResult, 'in-sync');
});

test('a fresh manifest satisfies the component-manifest schema contract', () => {
  const root = freshRoot();
  run(createArgs(root));
  const m = JSON.parse(readFileSync(join(root, 'design/manifests/button.json'), 'utf8'));
  const schema = JSON.parse(readFileSync(schemaPath, 'utf8'));

  for (const key of schema.required) {
    assert.ok(Object.hasOwn(m, key), `manifest is missing required key "${key}"`);
  }
  assert.ok(
    schema.properties.sync.properties.lastResult.enum.includes(m.sync.lastResult),
    `sync.lastResult "${m.sync.lastResult}" is not one of the schema's enum values`,
  );
  assert.ok(Object.hasOwn(m.registry, 'area'));
  assert.ok(Object.hasOwn(m.registry, 'item'));
});

test('parses props types without trailing semicolon before closing brace', () => {
  const root = freshRoot();
  const contextPath = join(root, 'chip-context.txt');
  writeFileSync(contextPath, `Component set: Chip
data-name="Chip"

type ChipProps = { label?: string; active?: boolean }

<div className="chip">Chip</div>`);

  const tokensPath = join(root, 'chip-tokens.json');
  writeFileSync(tokensPath, JSON.stringify({ colors: [] }));

  run([
    '--root', root, '--slug', 'chip', '--area', 'components',
    '--component', 'ui.chip', '--file-key', 'filekey',
    '--desktop-node', '1:1', '--desktop-url', 'https://figma.com/x',
    '--context', contextPath,
    '--tokens', tokensPath,
  ]);

  const m = JSON.parse(readFileSync(join(root, 'design/manifests/chip.json'), 'utf8'));
  assert.deepEqual(m.api.props.map((p) => p.name).sort(), ['active', 'label'].sort());
});
