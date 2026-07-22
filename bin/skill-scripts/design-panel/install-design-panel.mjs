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
let composer = null;
if (existsSync(join(root, 'composer.json'))) {
  try {
    composer = JSON.parse(readFileSync(join(root, 'composer.json'), 'utf8'));
  } catch {
    preflightFail('composer.json is not valid JSON');
  }
}
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
