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
  const m = context.match(/type \w+Props = \{([\s\S]*?)\}\s*;?/);
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
  let manifest;
  try {
    manifest = JSON.parse(readFileSync(path, 'utf8'));
  } catch {
    fail(`manifest at ${path} is not valid JSON`);
  }
  if (typeof manifest.sync !== 'object' || manifest.sync === null) manifest.sync = {};
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
