// Shared lesson parsing for export-lessons.mjs and retire-lessons.mjs (Node built-ins only).
//
// A lesson is docs/lessons/<category>/NNN-slug.md, opening with an optional
// frontmatter block:
//   ---
//   status: candidate | active | retired
//   source: own | peer
//   ---
//   ### Title
//   **Severity:** High
//   **Rule:** One actionable sentence.
// A lesson with no `status:` counts as `active` (files written before the lifecycle).

import { execFileSync } from 'node:child_process';
import { readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { basename, join, relative, sep } from 'node:path';

export const STATUSES = ['candidate', 'active', 'retired'];
const SEVERITY_RANK = { critical: 0, high: 1, medium: 2, low: 3 };

export function repoRoot(cwd = process.cwd()) {
  try {
    return execFileSync('git', ['rev-parse', '--show-toplevel'], { cwd, stdio: ['ignore', 'pipe', 'ignore'] })
      .toString().trim();
  } catch {
    return cwd;
  }
}

function splitFrontmatter(text) {
  const m = text.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?/);
  if (!m) return { fields: {}, body: text, raw: null };
  const fields = {};
  for (const line of m[1].split(/\r?\n/)) {
    const kv = line.match(/^([A-Za-z_][\w-]*):\s*(.*)$/);
    if (kv) fields[kv[1]] = kv[2].replace(/^["']|["']$/g, '').trim();
  }
  return { fields, body: text.slice(m[0].length), raw: m[0] };
}

export function parseLesson(file, lessonsDir) {
  const text = readFileSync(file, 'utf8');
  const { fields, body } = splitFrontmatter(text);
  const line = (re) => (body.match(re) || [])[1]?.trim() || '';
  const rel = relative(lessonsDir, file).split(sep).join('/');
  return {
    file,
    rel, // e.g. security/001-parameterize-raw-queries.md
    status: STATUSES.includes(fields.status) ? fields.status : 'active',
    source: fields.source || 'own',
    title: line(/^###\s+(.+)$/m) || basename(file, '.md'),
    severity: line(/^\*\*Severity:\*\*\s*(.+)$/m),
    rule: line(/^\*\*Rule:\*\*\s*(.+)$/m),
  };
}

export function listLessons(lessonsDir) {
  const out = [];
  const walk = (dir) => {
    let entries;
    try { entries = readdirSync(dir).sort(); } catch { return; }
    for (const name of entries) {
      const p = join(dir, name);
      if (statSync(p).isDirectory()) walk(p);
      else if (name.endsWith('.md') && name !== 'index.md' && name.toLowerCase() !== 'readme.md') out.push(parseLesson(p, lessonsDir));
    }
  };
  walk(lessonsDir);
  return out;
}

export function bySeverityThenPath(a, b) {
  const ra = SEVERITY_RANK[a.severity.toLowerCase()] ?? 4;
  const rb = SEVERITY_RANK[b.severity.toLowerCase()] ?? 4;
  return ra - rb || (a.rel < b.rel ? -1 : a.rel > b.rel ? 1 : 0);
}

// Rewrite (or add) `status:` in the frontmatter, leaving the rest of the file as-is.
export function setStatus(file, status) {
  const text = readFileSync(file, 'utf8');
  const { raw } = splitFrontmatter(text);
  let next;
  if (!raw) next = `---\nstatus: ${status}\n---\n${text}`;
  else if (/^status:.*$/m.test(raw)) next = raw.replace(/^status:.*$/m, `status: ${status}`) + text.slice(raw.length);
  else next = raw.replace(/^---\r?\n/, `---\nstatus: ${status}\n`) + text.slice(raw.length);
  writeFileSync(file, next);
}
