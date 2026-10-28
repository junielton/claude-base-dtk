#!/usr/bin/env node
/* check-mockup.mjs <mockup-dir> [--tokens-source <path>]
 * Mechanical gate for the mockup convention. Exit 1 on any error.
 * Checks: mockup.json shape + status consistency; one file per screen and one registry entry per
 * file; one [data-dsqa=<id>] root per screen; declared states; every data-goto resolves; flows are
 * clickable; raw colors outside tokens.css; index.html embeds every screen and copies none;
 * index status banner + VIEWPORTS mirror mockup.json; tokens.css is a verbatim subset of the source.
 */
import fs from 'node:fs';
import path from 'node:path';

const args = process.argv.slice(2);
const dir = path.resolve(args.find((a) => !a.startsWith('--')) || '.');
const tokSrcIdx = args.indexOf('--tokens-source');
const tokensSource = tokSrcIdx >= 0 ? path.resolve(args[tokSrcIdx + 1]) : null;

const errors = [], warnings = [];
const err = (m) => errors.push(m), warn = (m) => warnings.push(m);
const read = (p) => fs.readFileSync(p, 'utf8');
const exists = (p) => fs.existsSync(p);

// --- mockup.json
const metaPath = path.join(dir, 'mockup.json');
if (!exists(metaPath)) { err('mockup.json missing'); finish(); }
let meta;
try { meta = JSON.parse(read(metaPath)); } catch (e) { err(`mockup.json is not valid JSON: ${e.message}`); finish(); }
for (const k of ['status', 'project', 'tokensFrom', 'viewports', 'screens']) if (!(k in meta)) err(`mockup.json: "${k}" missing`);
if (!['draft', 'approved'].includes(meta.status)) err(`mockup.json: status must be draft|approved, got "${meta.status}"`);
const screens = Array.isArray(meta.screens) ? meta.screens : [];
const flows = Array.isArray(meta.flows) ? meta.flows : [];
const allApproved = screens.length > 0 && screens.every((s) => s.status === 'approved');
if (meta.status === 'approved' && !allApproved) err('mockup.json: status approved but not every screen is approved');
if (meta.status === 'approved' && !meta.approvedAt) err('mockup.json: status approved without approvedAt');
if (meta.status === 'draft' && allApproved) warn('mockup.json: every screen is approved but status is still draft');
for (const s of screens) {
  if (s.status === 'approved' && !s.approvedAt) err(`screen ${s.id}: approved without approvedAt`);
  if (!Array.isArray(s.states) || s.states.length === 0) err(`screen ${s.id}: "states" must be a non-empty array`);
}

// --- files
for (const f of ['mockup.js', 'tokens.css', 'index.html']) if (!exists(path.join(dir, f))) err(`${f} missing`);
const screensDir = path.join(dir, 'screens');
const files = exists(screensDir) ? fs.readdirSync(screensDir).filter((f) => f.endsWith('.html')) : [];
const ids = new Set(screens.map((s) => s.id));
for (const f of files) if (!ids.has(f.replace(/\.html$/, ''))) err(`screens/${f} is not registered in mockup.json`);
for (const id of ids) if (!files.includes(id + '.html')) err(`screen ${id} registered but screens/${id}.html missing`);

const rawColor = /#[0-9a-fA-F]{3,8}\b|\b(rgba?|hsla?|oklch|oklab|color)\(/g;
const stripComments = (s) => s.replace(/<!--[\s\S]*?-->/g, '').replace(/\/\*[\s\S]*?\*\//g, '');
// In HTML only CSS contexts count: <style> blocks and style="" attributes. Text like "#1042" is not a color.
const cssOf = (html) => [...html.matchAll(/<style[^>]*>([\s\S]*?)<\/style>/g)].map((m) => m[1]).concat([...html.matchAll(/\sstyle="([^"]*)"/g)].map((m) => m[1])).join('\n');
const partsOf = (html) => [...html.matchAll(/<script[^>]*src="\.\.\/parts\/([^"]+\.js)"/g)].map((m) => m[1]);
const gotoTargets = new Map(); // screen id -> Set of "screen?state"

for (const s of screens) {
  const p = path.join(screensDir, s.id + '.html');
  if (!exists(p)) continue;
  const html = read(p);
  const roots = [...html.matchAll(/<[a-zA-Z][^>]*\sdata-dsqa="([^"]+)"/g)].map((m) => m[1]); // tag-anchored: ignores CSS selectors
  if (roots.filter((r) => r === s.id).length !== 1) err(`screen ${s.id}: expected exactly one data-dsqa="${s.id}" root, found ${roots.filter((r) => r === s.id).length}`);
  const bodyStates = (html.match(/<body[^>]*data-states="([^"]*)"/) || [])[1];
  if (!bodyStates) err(`screen ${s.id}: <body data-states="..."> missing`);
  else {
    const declared = bodyStates.split(/\s+/).filter(Boolean);
    const want = s.states || [];
    if (declared.join(' ') !== want.join(' ')) err(`screen ${s.id}: body data-states "${declared.join(' ')}" ≠ mockup.json states "${want.join(' ')}"`);
  }
  if (!/href="\.\.\/tokens\.css"/.test(html)) err(`screen ${s.id}: must link ../tokens.css`);
  if (!/src="\.\.\/mockup\.js"/.test(html)) err(`screen ${s.id}: must load ../mockup.js`);
  if (/(src|href)="https?:\/\//.test(html)) err(`screen ${s.id}: external request found (src/href=http...) — screens must be self-contained`);
  const colors = [...stripComments(cssOf(html)).matchAll(rawColor)].map((m) => m[0]);
  if (colors.length) err(`screen ${s.id}: raw color value(s) ${[...new Set(colors)].slice(0, 5).join(', ')} — use var(--token) from tokens.css`);
  const partHtml = partsOf(html).map((f) => { const pp = path.join(dir, 'parts', f); return exists(pp) ? read(pp) : ''; }).join('\n');
  const targets = new Set([...(html + '\n' + partHtml).matchAll(/data-goto="([^"]+)"/g)].map((m) => m[1]));
  gotoTargets.set(s.id, targets);
  for (const t of targets) {
    if (t === 'back') continue;
    const [scr, q = ''] = t.split('?');
    const target = screens.find((x) => x.id === scr);
    if (!target) { err(`screen ${s.id}: data-goto="${t}" → screen "${scr}" does not exist`); continue; }
    const st = new URLSearchParams(q).get('state');
    if (st && !(target.states || []).includes(st)) err(`screen ${s.id}: data-goto="${t}" → state "${st}" not declared on ${scr}`);
  }
}

// shared css + parts: raw colors
for (const f of ['mockup.css', ...(exists(path.join(dir, 'parts')) ? fs.readdirSync(path.join(dir, 'parts')).map((x) => 'parts/' + x) : [])]) {
  const p = path.join(dir, f);
  if (!exists(p) || fs.statSync(p).isDirectory() || f.endsWith('index.html')) continue;
  const colors = [...stripComments(read(p)).matchAll(rawColor)].map((m) => m[0]);
  if (colors.length) err(`${f}: raw color value(s) ${[...new Set(colors)].slice(0, 5).join(', ')} — use var(--token)`);
}

// --- flows
for (const fl of flows) {
  const steps = fl.steps || [];
  if (steps.length < 2) warn(`flow ${fl.id}: fewer than 2 steps`);
  steps.forEach((st, i) => {
    const scr = screens.find((x) => x.id === st.screen);
    if (!scr) { err(`flow ${fl.id} step ${i + 1}: screen "${st.screen}" does not exist`); return; }
    if (st.state && !(scr.states || []).includes(st.state)) err(`flow ${fl.id} step ${i + 1}: state "${st.state}" not declared on ${st.screen}`);
    const next = steps[i + 1];
    if (!next) return;
    const targets = gotoTargets.get(st.screen) || new Set();
    const ok = [...targets].some((t) => { const [s2, q = ''] = t.split('?'); const s3 = new URLSearchParams(q).get('state'); return s2 === next.screen && (!next.state || !s3 || s3 === next.state || (next.state === (screens.find((x) => x.id === next.screen)?.states || [])[0] && !s3)); });
    if (!ok) warn(`flow ${fl.id}: step ${i + 1} (${st.screen}) has no data-goto reaching step ${i + 2} (${next.screen}${next.state ? '?state=' + next.state : ''}) — the flow is not clickable there`);
  });
}

// --- index.html
const idxPath = path.join(dir, 'index.html');
if (exists(idxPath)) {
  const idx = read(idxPath);
  const banner = (idx.match(/class="status"[^>]*data-status="([^"]+)"/) || idx.match(/data-status="([^"]+)"/) || [])[1];
  if (banner !== meta.status) err(`index.html: status banner "${banner}" ≠ mockup.json status "${meta.status}"`);
  const embedded = new Set([...idx.matchAll(/data-screen="([^"]+)"/g)].map((m) => m[1]));
  for (const id of ids) if (!embedded.has(id)) err(`index.html: screen ${id} is not embedded (no <article data-screen="${id}">)`);
  for (const id of embedded) if (!ids.has(id)) err(`index.html: embeds unknown screen "${id}"`);
  if (/<[a-zA-Z][^>]*\sdata-dsqa="/.test(idx)) err('index.html: contains data-dsqa roots — component markup must live only in screens/ (embed via iframe)');
  const vpLine = (idx.match(/const VIEWPORTS = \[([^\]]*)\]/) || [])[1];
  if (vpLine) {
    const got = vpLine.split(',').map((x) => Number(x.trim())).filter(Boolean);
    if (JSON.stringify(got) !== JSON.stringify(meta.viewports)) err(`index.html: VIEWPORTS [${got}] ≠ mockup.json viewports [${meta.viewports}]`);
  }
  for (const id of ids) {
    const m = idx.match(new RegExp(`data-screen="${id}"[^>]*data-states="([^"]*)"`));
    const want = (screens.find((s) => s.id === id)?.states || []).join(' ');
    if (m && m[1] !== want) err(`index.html: screen ${id} data-states "${m[1]}" ≠ mockup.json "${want}"`);
  }
  for (const fl of flows) if (!idx.includes(`data-flow="${fl.id}"`)) warn(`index.html: flow ${fl.id} is not presented`);
}

// --- tokens verbatim
if (tokensSource) {
  if (!exists(tokensSource)) err(`--tokens-source ${tokensSource} not found`);
  else {
    const src = read(tokensSource), tok = read(path.join(dir, 'tokens.css'));
    const decls = [...stripComments(tok).matchAll(/(--[\w-]+)\s*:\s*([^;]+);/g)];
    const srcDecls = new Map([...stripComments(src).matchAll(/(--[\w-]+)\s*:\s*([^;]+);/g)].map((m) => [m[1], m[2].trim()]));
    for (const [, name, value] of decls) {
      if (!srcDecls.has(name)) err(`tokens.css: ${name} does not exist in ${meta.tokensFrom}`);
      else if (srcDecls.get(name) !== value.trim()) err(`tokens.css: ${name} = "${value.trim()}" but source has "${srcDecls.get(name)}"`);
    }
  }
} else warn('tokens verbatim check skipped (pass --tokens-source <project token file>)');

function finish() {
  for (const w of warnings) console.log('WARN  ' + w);
  for (const e of errors) console.log('ERROR ' + e);
  console.log(`\n${errors.length} error(s), ${warnings.length} warning(s) — ${dir}`);
  process.exit(errors.length ? 1 : 0);
}
finish();
