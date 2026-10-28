#!/usr/bin/env node
// Proposes retiring lessons that real review outcomes keep proving wrong.
//
// Usage:
//   node bin/skill-scripts/lessons/retire-lessons.mjs --outcomes <file.json | -> \
//     [--min-negative 3] [--lessons <dir>] [--apply]
//
// Rule: a lesson (status active or candidate) is proposed for `retired` when its findings
// were refuted or marked wrong >= --min-negative times (default 3) AND accepted 0 times.
// Without --apply it only prints the proposal; --apply rewrites `status: retired` in each
// proposed lesson's frontmatter and nothing else. Re-run export-lessons.mjs afterwards.
//
// Input: outcomes.py --json reports per reviewer and per comment tag (Q/CR/FFT/NIT) and
// carries no lesson attribution, so this script defines its own shape. Either form works:
//
//   Shape A — one row per review finding that cited a lesson:
//   { "findings": [
//       { "lesson": "security/001-slug.md", "outcome": "refuted-by-verifier" },
//       { "lessons": ["qa/002-slug.md", "qa/003-slug.md"], "outcome": "accepted" } ] }
//
//   Shape B — counts already aggregated per lesson:
//   { "lessons": { "security/001-slug.md": { "refuted-by-verifier": 2, "marked-wrong": 1, "accepted": 0 } } }
//
// A lesson ref is its path under docs/lessons/ (a leading `docs/lessons/` and the `.md`
// are optional) or, when unique, its bare file name. Outcome names follow the review
// outcome metrics (docs/review-outcomes.md); `_` and `-` are interchangeable:
//   negative: refuted, refuted-by-verifier, marked-wrong
//   accepted: accepted, agreed, resolved-by-merge
//   anything else (declined, replied, no_reply, pending, …) is ignored.
//
// Exit: 0 ok (with or without a proposal), 1 bad usage or unreadable / unknown input.

import { readFileSync } from 'node:fs';
import { basename, join, resolve } from 'node:path';
import { listLessons, repoRoot, setStatus } from './lessons-lib.mjs';

const NEGATIVE = new Set(['refuted', 'refuted-by-verifier', 'marked-wrong']);
const ACCEPTED = new Set(['accepted', 'agreed', 'resolved-by-merge']);

function die(msg) { console.error(msg); process.exit(1); }

function parseArgs(argv) {
  const opts = { outcomes: null, minNegative: 3, lessons: null, apply: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--outcomes') opts.outcomes = argv[++i];
    else if (a === '--min-negative') opts.minNegative = Number(argv[++i]);
    else if (a === '--lessons') opts.lessons = argv[++i];
    else if (a === '--apply') opts.apply = true;
    else die(`Unknown option: ${a}`);
  }
  if (!opts.outcomes) die('--outcomes <file.json | -> is required');
  if (!Number.isInteger(opts.minNegative) || opts.minNegative < 1) die('--min-negative must be an integer >= 1');
  return opts;
}

// Flatten either input shape into [ref, outcome, count] rows.
function rows(data) {
  if (Array.isArray(data?.findings)) {
    return data.findings.flatMap((f) => {
      const refs = f.lessons ?? (f.lesson ? [f.lesson] : []);
      return refs.map((ref) => [ref, f.outcome, 1]);
    });
  }
  if (data?.lessons && typeof data.lessons === 'object' && !Array.isArray(data.lessons)) {
    return Object.entries(data.lessons).flatMap(([ref, counts]) =>
      Object.entries(counts || {}).map(([outcome, n]) => [ref, outcome, Number(n) || 0]));
  }
  die('outcomes JSON must have a "findings" array or a "lessons" object (see the header of this script)');
}

const opts = parseArgs(process.argv.slice(2));
let data;
try {
  data = JSON.parse(readFileSync(opts.outcomes === '-' ? 0 : opts.outcomes, 'utf8'));
} catch (err) {
  die(`cannot read outcomes JSON: ${err.message}`);
}

const lessonsDir = resolve(opts.lessons || join(repoRoot(), 'docs/lessons'));
const lessons = listLessons(lessonsDir);
const byKey = new Map();
const byName = new Map();
for (const l of lessons) {
  byKey.set(l.rel.replace(/\.md$/, ''), l);
  const name = basename(l.rel, '.md');
  byName.set(name, byName.has(name) ? null : l); // null marks an ambiguous bare name
}
const resolveRef = (ref) => {
  const key = String(ref).replace(/^\.?\//, '').replace(/^docs\/lessons\//, '').replace(/\.md$/, '');
  return byKey.get(key) || (key.includes('/') ? undefined : byName.get(key)) || undefined;
};

const tally = new Map(); // lesson -> { negative, accepted, detail }
const unmatched = new Set();
for (const [ref, rawOutcome, n] of rows(data)) {
  const lesson = resolveRef(ref);
  if (!lesson) { unmatched.add(String(ref)); continue; }
  const outcome = String(rawOutcome || '').toLowerCase().replace(/_/g, '-');
  const t = tally.get(lesson) || { negative: 0, accepted: 0, detail: {} };
  if (NEGATIVE.has(outcome)) t.negative += n;
  else if (ACCEPTED.has(outcome)) t.accepted += n;
  else continue;
  t.detail[outcome] = (t.detail[outcome] || 0) + n;
  tally.set(lesson, t);
}

const proposal = [...tally.entries()]
  .filter(([l, t]) => l.status !== 'retired' && t.negative >= opts.minNegative && t.accepted === 0)
  .sort(([a], [b]) => (a.rel < b.rel ? -1 : 1));

console.log(`Retirement proposal (rule: >= ${opts.minNegative} refuted/marked-wrong, 0 accepted)`);
if (proposal.length === 0) console.log('No lesson meets the rule.');
for (const [l, t] of proposal) {
  const detail = Object.entries(t.detail).map(([k, v]) => `${k} ${v}`).join(' · ');
  console.log(`- ${l.rel}  ${detail} · accepted 0  [${l.status} → retired]`);
}
if (unmatched.size) console.error(`warning: no lesson matches: ${[...unmatched].sort().join(', ')}`);

if (proposal.length === 0) process.exit(0);
if (!opts.apply) {
  console.log('Dry run: nothing written. Re-run with --apply to set status: retired.');
} else {
  for (const [l] of proposal) setStatus(l.file, 'retired');
  console.log(`Applied: ${proposal.length} lesson(s) set to status: retired. Re-run export-lessons.mjs.`);
}
