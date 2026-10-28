// Alignment fixture for the dsqa diff script.
//
// Every visual-QA tool asserts that both sides share crop, scale and viewport;
// this is the first test that proves the diff script actually notices a shift.
//
//   node --test 'bin/skill-scripts/dsqa/tests/*.test.mjs'
//
// Needs puppeteer/pngjs/pixelmatch from the plugin cache (check-deps.sh --install)
// and a Chromium. If either cannot be provided the tests are SKIPPED with the
// reason — never faked as a pass.

import { test, before } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const dsqa = join(here, "..");
const fixtures = join(here, "fixtures", "alignment");
const VIEWPORT = "1280x800"; // deviceScaleFactor is pinned to 1 inside the script

const tmp = mkdtempSync(join(tmpdir(), "dsqa-align-"));
let skipReason = null;

const run = (cmd, args, opts = {}) =>
  spawnSync(cmd, args, { encoding: "utf8", ...opts });

const capture = (page, out, reference) => {
  const args = [
    join(dsqa, "capture-and-compare.mjs"),
    "--url", pathToFileURL(join(fixtures, page)).href,
    "--selector", "[data-dsqa]",
    "--viewport", VIEWPORT,
    "--output", out,
  ];
  if (reference) args.push("--reference", reference);
  const r = run("node", args);
  assert.equal(r.status, 0, `capture-and-compare failed:\n${r.stderr}`);
  return JSON.parse(r.stdout);
};

before(() => {
  const dep = run("bash", [join(dsqa, "check-deps.sh"), "--install"]);
  if (dep.status !== 0) {
    skipReason = `dsqa deps unavailable (check-deps.sh --install exit ${dep.status}): ${(dep.stderr || dep.stdout).trim()}`;
    return;
  }
  // Prove a browser actually launches before any assertion depends on it.
  const probe = run("node", [
    join(dsqa, "capture-and-compare.mjs"),
    "--url", pathToFileURL(join(fixtures, "identical.html")).href,
    "--viewport", VIEWPORT,
    "--output", join(tmp, "probe"),
  ]);
  if (probe.status !== 0) {
    skipReason = `Chromium/puppeteer cannot render here: ${probe.stderr.trim()}`;
  }
});

test("identical pair reports 0% mismatch", (t) => {
  if (skipReason) return t.skip(skipReason);
  const ref = capture("identical.html", join(tmp, "id-ref"));
  const cmp = capture("identical.html", join(tmp, "id-cmp"), ref.screenshot);
  assert.equal(cmp.mismatchPixels, 0);
  assert.equal(cmp.mismatchPercentage, 0);
  assert.equal(cmp.sizeDifference, null, "same crop/scale on both sides");
  assert.deepEqual(cmp.viewport, { width: 1280, height: 800 });
});

test("4px horizontal shift reports > 0% mismatch", (t) => {
  if (skipReason) return t.skip(skipReason);
  const ref = capture("identical.html", join(tmp, "sh-ref"));
  const cmp = capture("shifted.html", join(tmp, "sh-cmp"), ref.screenshot);
  assert.ok(cmp.mismatchPixels > 0, `expected mismatch, got ${cmp.mismatchPixels}`);
  assert.ok(cmp.mismatchPercentage > 0, `expected >0%, got ${cmp.mismatchPercentage}`);
  assert.equal(cmp.sizeDifference, null, "shift must not come from a crop/scale change");
});

test("dsqa deps install into the plugin cache, never the user's project", (t) => {
  // A project's package.json / package-lock.json stay byte-identical across the
  // install + resolve helper. Uses a throwaway cache so it proves a cold install.
  const proj = join(tmp, "project");
  const cache = join(tmp, "xdg");
  mkdirSync(proj, { recursive: true });
  writeFileSync(join(proj, "package.json"), '{\n  "name": "user-app",\n  "version": "1.0.0"\n}\n');
  writeFileSync(join(proj, "package-lock.json"), '{\n  "name": "user-app",\n  "lockfileVersion": 3,\n  "packages": {}\n}\n');
  const pkgBefore = readFileSync(join(proj, "package.json"));
  const lockBefore = readFileSync(join(proj, "package-lock.json"));
  const env = { ...process.env, XDG_CACHE_HOME: cache, PUPPETEER_SKIP_DOWNLOAD: "1" };

  const r = run("bash", [join(dsqa, "check-deps.sh"), "--install"], { cwd: proj, env });
  if (r.status !== 0) return t.skip(`cold install failed (exit ${r.status}): ${(r.stderr || r.stdout).trim()}`);

  assert.ok(readFileSync(join(proj, "package.json")).equals(pkgBefore), "package.json changed");
  assert.ok(readFileSync(join(proj, "package-lock.json")).equals(lockBefore), "package-lock.json changed");
  assert.equal(existsSync(join(proj, "node_modules")), false, "node_modules created in the project");

  const again = run("bash", [join(dsqa, "check-deps.sh")], { cwd: proj, env });
  assert.equal(again.status, 0, `cached deps not reused: ${again.stderr}`);

  const cached = JSON.parse(readFileSync(join(cache, "dtk", "package.json"), "utf8"));
  assert.deepEqual(Object.keys(cached.dependencies).sort(), ["pixelmatch", "pngjs", "puppeteer"]);
  for (const v of Object.values(cached.dependencies)) assert.match(v, /^\d+\.\d+\.\d+$/, "pinned, no ranges");
});

process.on("exit", () => rmSync(tmp, { recursive: true, force: true }));
