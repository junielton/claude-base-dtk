---
name: dsqa
description: "Use when verifying that a built UI component matches its Figma design, after implementing or refactoring a UI component, or when the user asks for design QA, visual review, or pixel-perfect comparison."
---

# Design QA (DSQA)

## Overview

Compares a Figma component specification against a running browser implementation using a 3-layer approach: Figma JSON vs source code, computed styles extraction, and visual pixel diff. Reports every deviation with exact values and actionable fixes.

## When to Use

- After implementing or refactoring a UI component
- User asks to "check the design", "compare with Figma", "design QA", "visual review"
- Before marking a UI task as complete
- User provides a Figma URL and wants to verify implementation

## When NOT to Use

- No Figma design exists for the component
- Component is purely backend with no visual output
- User wants to create a design, not verify one (use `/implement-design`)

## Step 0: Resolve Scripts

```bash
# resolver idiom: docs/conventions/script-resolution.md
SCRIPTS="${CLAUDE_PLUGIN_ROOT}/scripts"; [ -d "$SCRIPTS" ] || echo "dtk: scripts dir not found: $SCRIPTS" >&2; echo "$SCRIPTS"
```

Use the output path as `$SCRIPTS` for all script commands below.

## Prerequisites

Scripts live in `$SCRIPTS/dsqa/`:
- `capture-and-compare.mjs` — Takes element screenshot + extracts computed styles + pixel diff
- `deep-inspect.mjs` — Extracts full style tree (2 levels deep) for layout debugging

```bash
bash $SCRIPTS/dsqa/check-deps.sh --install
```

If scripts aren't found, fall back to **Playwright MCP method** (see Layer 2 fallback below).

### Dependency cache and comparison assumptions

- **Cache:** `${XDG_CACHE_HOME:-$HOME/.cache}/dtk` — one pinned `package.json` plus `node_modules` (puppeteer, pngjs, pixelmatch). Installed once by `check-deps.sh --install`, reused by every run, shared with `mockup-qa`. Nothing is written to the user's project: its `package.json`, lockfile and `node_modules` stay untouched.
- **Clear it:** `rm -rf ~/.cache/dtk` (or `"$XDG_CACHE_HOME/dtk"`). The next `--install` rebuilds it; the first install also downloads Chromium (puppeteer's own cache, `~/.cache/puppeteer`).
- **Comparison assumptions:** both images must share the same viewport (`--viewport WxH`, default `1440x900`), `deviceScaleFactor` **1** (fixed by the script, so a Figma reference export must be 1x) and the same element crop (`element.screenshot()` of the selector). If sizes differ the script crops both to the smaller common size and reports `sizeDifference`; non-null means crop or scale is misaligned and the pixel % is not trustworthy. `pixelmatch` runs with `threshold 0.1`, anti-aliasing ignored.
- **Alignment is tested:** `node --test 'bin/skill-scripts/dsqa/tests/*.test.mjs'` renders a fixture pair at 1280×800 and asserts 0% for identical pages and >0% for a 4px shift.

## Workflow

### 1. Resolve Inputs

**Figma URL:** Scan conversation for `figma.com/design/` or `figma.com/file/`. Extract `fileKey` and `nodeId` (URL-decode `%3A` → `:`, replace `-` → `:`). If not found, ask.

**Dev server path:** Run `git diff --name-only HEAD` to identify modified files and infer the dev URL. If unable to infer, ask.

**Target element selector** (priority order):
1. `[data-dsqa]` — explicit marker (recommended)
2. `[data-testid]` matching the component name
3. Semantic selector: `button`, `header`, `nav`, `article`, `.card`, etc.

### 2. Layer 1 — Figma JSON vs Source Code

Call `get_design_context(fileKey, nodeId)` via Figma MCP.

If it returns an error, report "Layer 1 skipped" and continue with Layer 2.

Extract from Figma response: `fills` (background), `strokes` (border), `cornerRadius`, typography (`fontFamily`, `fontSize`, `fontWeight`, `lineHeight`, `letterSpacing`), padding, `effects` (box-shadow).

Read modified source files from git diff. Compare each Figma value against CSS/JSX code values.

**For each mismatch note:** property, Figma expected, code actual, file:line, suggested fix.

### 3. Layer 2 — Capture & Compare (Computed Styles)

**Script method (preferred — 10-50x cheaper in tokens):**

```bash
node $SCRIPTS/dsqa/capture-and-compare.mjs \
  --url "{devUrl}" \
  --selector "{selector}" \
  --output ./dsqa-output \
  --reference ./dsqa-output/figma-reference.png \
  --viewport 1440x900
```

Outputs JSON with: `computedStyles`, `childrenStyles`, `boundingBox`, `screenshot`, `mismatchPercentage`, `diff`, `composite`.

Compare `computedStyles` against Figma values from Layer 1.

**Playwright MCP fallback (if script unavailable):**

```
browser_navigate(url)
```

If navigation fails (connection refused), tell the user to start the dev server and re-run.

Then extract computed styles via `browser_evaluate` with `window.getComputedStyle(el)` for: backgroundColor, color, fontFamily, fontSize, fontWeight, lineHeight, letterSpacing, padding, borderRadius, boxShadow, border.

### 4. Layer 3 — Visual Pixel Diff

If `capture-and-compare` ran with `--reference`, check `mismatchPercentage`:
- < 2% → likely pixel-perfect
- 2-10% → noticeable differences, check diff image
- \> 10% → significant deviation

Look at the `composite` (side-by-side) image to understand WHAT is different.

If viewport width differs from Figma frame by >10%, note in Minor section.

### 5. Deep Inspect (optional, when needed)

If pixel diff shows mismatches but root styles look correct, the problem is in a child element:

```bash
node $SCRIPTS/dsqa/deep-inspect.mjs \
  --url "{devUrl}" \
  --selector "{selector}" \
  --depth 2
```

Compare each child node against the Figma component tree.

### 6. Output Report

Report is written in **English**.

```markdown
## DSQA Report — {ComponentName}

**Result:** ✅ Pass | ⚠️ Needs Work | ❌ Fail
**Figma:** {url}
**Dev URL:** {url}
**Viewport:** {width}px
**Pixel diff:** {mismatchPercentage}% ({mismatchPixels}/{totalPixels} pixels)
**Evaluated on:** {date}
**Method:** Direct script | Playwright MCP fallback

---

### 🔴 Critical — fix before merging
(Wrong color/branding, wrong font, broken layout)

- [ ] **{property}:** found `{actual}`, Figma specifies `{expected}`
  - File: `{file}:{line}`
  - Fix: {specific suggestion}
  - Detected via: {Figma JSON | Computed CSS | Pixel Diff}

### 🟡 Major — noticeable visual difference
(Spacing >4px, wrong font-weight, size >10% different)

- [ ] ...

### 🟢 Minor — small deviation, acceptable
(1-2px variation, browser rendering differences)

- [ ] ...

---

### Confirmed matches ✅
- **{property}:** `{value}` ✅

---

### Next steps
{N} blocking issues. {summary}.
{If issues: "Fix the Critical/Major items and run /dsqa again."}
{If no issues: "Component approved. Proceed."}
```

**Result definition:**
- ✅ Pass — zero Critical, zero Major, pixel diff < 5%
- ⚠️ Needs Work — zero Critical, 1+ Major OR pixel diff 5-15%
- ❌ Fail — 1+ Critical OR pixel diff > 15%

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Using Playwright MCP when scripts are available | Always prefer scripts — 10-50x cheaper in tokens |
| Not citing which layer detected each issue | Always cite: Figma JSON, Computed CSS, or Pixel Diff |
| Running DSQA without dev server running | Check server is running first, instruct user if not |
| Ignoring Code Connect snippets from Figma | Use snippet's prop values as Figma spec reference |
| Full-page screenshot for mid-page components | Scripts use `element.screenshot()` — captures only the element |
| Not URL-decoding the Figma nodeId | Replace `%3A` → `:` and `-` → `:` |
