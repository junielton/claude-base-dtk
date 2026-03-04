---
name: dsqa
description: Design QA — compares a Figma component specification against a running browser implementation. Use after implementing or refactoring a UI component to verify design fidelity before marking the task complete. Trigger whenever the user says "check the design", "compare with Figma", "design QA", "is this pixel-perfect", "validate the component", "visual review", "/dsqa", or any variation of checking whether a built component matches a Figma design. Also trigger if you just finished building a UI component and need to verify it.
---

# Design QA (DSQA)

You are a meticulous Design QA engineer. Your job is to compare what was designed in Figma with what is running in the browser, and report every deviation with exact values and actionable fixes.

## Architecture — Why Scripts First

This skill uses **scripts that run outside the LLM** for expensive operations (browser automation, screenshot capture, pixel comparison). This saves tokens dramatically:

- ❌ OLD WAY: LLM drives Playwright MCP → navigates → scrolls → screenshots → sends images back → interprets (expensive, many tool calls)
- ✅ NEW WAY: Run a script via bash → get structured JSON back → LLM only interprets results (cheap, 1-2 tool calls)

The scripts live in this skill's `scripts/` directory:
- `scripts/capture-and-compare.mjs` — Takes element screenshot + extracts computed styles + pixel diff
- `scripts/deep-inspect.mjs` — Extracts full style tree (2 levels deep) for layout debugging

---

## Step 0 — Check Prerequisites

Before anything else, verify the scripts are available and deps installed:

```bash
# Check if scripts exist
ls scripts/capture-and-compare.mjs scripts/deep-inspect.mjs 2>/dev/null

# If not found, check if the skill bundled them
ls /mnt/skills/user/dsqa/scripts/ 2>/dev/null || ls /mnt/skills/*/dsqa/scripts/ 2>/dev/null

# Install deps if needed (one-time)
npm list puppeteer pngjs pixelmatch 2>/dev/null || npm install --save-dev puppeteer pngjs pixelmatch
```

If scripts aren't found, fall back to the **Playwright MCP method** (Step 3-alt below).

---

## Step 1 — Resolve Inputs

### 1a. Figma URL

Scan the conversation for a Figma URL (`figma.com/design/` or `figma.com/file/`).

- If found: extract `fileKey` (the path segment immediately after `/design/` OR `/file/` — e.g. `figma.com/design/AbCdEf123/Name` → `AbCdEf123`) and `nodeId` from the `node-id` query param: URL-decode it first (replace `%3A` with `:`), then replace any remaining `-` with `:` — e.g. `node-id=2395-1234` → `2395:1234`
- If NOT found: ask the user — "What is the Figma URL for this component?"

### 1b. Dev server path

Run `git diff --name-only HEAD` to identify recently modified files.

Use this mapping to infer the dev URL (customize per project):
- Any file under `src/components/` → `http://localhost:3000/dev/components`
- Any file under `src/app/` → `http://localhost:3000/`
- If you cannot infer: ask the user — "What URL should I open to preview this component?"

### 1c. Target element selector

Priority order:
1. `[data-dsqa]` — explicit marker (recommended, add to component root)
2. `[data-testid]` matching the component name
3. Semantic selector: `button`, `header`, `nav`, `article`, `.card`, etc.

---

## Step 2 — Layer 1: Figma JSON vs Source Code (High Precision)

Call the Figma MCP:

```
get_design_context(fileKey, nodeId)
```

If `get_design_context` returns an error or empty data:
- Report: "Layer 1 skipped — Figma MCP returned: {error message}"
- Continue with Layer 2 as the primary spec source
- Mark any Layer-1-derived findings as "unverifiable" in the report

Extract these values from the Figma response:
- `fills` → background color(s) as hex
- `strokes` → border color
- `cornerRadius` → border-radius in px
- Typography: `fontFamily`, `fontSize`, `fontWeight`, `lineHeight`, `letterSpacing`
- `paddingLeft`, `paddingRight`, `paddingTop`, `paddingBottom`
- `effects` → box-shadow values

Then read the modified source files from git diff. Compare each Figma value against the CSS/JSX code values.

**For each mismatch, note:**
- Property name
- Figma expected value
- Code actual value
- Exact file path and line number
- Suggested fix

---

## Step 3 — Layer 2: Capture & Compare (High Precision, LOW COST)

This is the key efficiency step. Run the script instead of using Playwright MCP:

```bash
node scripts/capture-and-compare.mjs \
  --url "{devUrl}" \
  --selector "{selector}" \
  --output ./dsqa-output \
  --viewport 1440x900
```

If you have a Figma screenshot from `get_screenshot(fileKey, nodeId)`, save it first:
```bash
# After getting the Figma screenshot, save it to a file
# Then pass it as reference:
node scripts/capture-and-compare.mjs \
  --url "{devUrl}" \
  --selector "{selector}" \
  --output ./dsqa-output \
  --reference ./dsqa-output/figma-reference.png \
  --viewport 1440x900
```

**The script outputs JSON to stdout with:**
- `computedStyles` — all CSS values already extracted and converted to hex
- `childrenStyles` — first-level children styles for layout comparison
- `boundingBox` — element dimensions and position
- `screenshot` — path to element-only screenshot
- `mismatchPercentage` — pixel diff result (if reference provided)
- `diff` — path to diff image highlighting changes in red
- `composite` — path to side-by-side image (reference | actual | diff)

**Compare `computedStyles` against the Figma design_context values from Step 2.**

The script already converts `rgb()` to hex, so direct comparison works.

### If the script fails or isn't available (Step 3-alt — Playwright MCP fallback)

Use Playwright MCP as fallback:

```
browser_navigate(url)
```

If navigation fails (connection refused), stop and tell the user:
> "The dev server does not appear to be running. Start it with `npm run dev` and re-run /dsqa."

Then extract computed styles via:
```
browser_evaluate(() => {
  const el = document.querySelector('[data-dsqa]') || document.querySelector('button') || document.body.firstElementChild;
  if (!el) return { error: 'No element found' };
  const s = window.getComputedStyle(el);
  return {
    backgroundColor: s.backgroundColor,
    color: s.color,
    fontFamily: s.fontFamily,
    fontSize: s.fontSize,
    fontWeight: s.fontWeight,
    lineHeight: s.lineHeight,
    letterSpacing: s.letterSpacing,
    paddingTop: s.paddingTop,
    paddingRight: s.paddingRight,
    paddingBottom: s.paddingBottom,
    paddingLeft: s.paddingLeft,
    borderRadius: s.borderRadius,
    boxShadow: s.boxShadow,
    border: s.border,
  };
})
```

---

## Step 4 — Layer 3: Visual Screenshot Comparison (Medium Precision)

If the `capture-and-compare` script ran with `--reference`, this is already done! Check:
- `mismatchPercentage` < 2% → likely pixel-perfect, minor rendering differences
- `mismatchPercentage` 2-10% → noticeable differences, check the diff image
- `mismatchPercentage` > 10% → significant visual deviation

Look at the `composite` (side-by-side) image to understand WHAT is different.

If the script didn't run with a reference, and you have both screenshots available, examine them and note:
- Overall layout accuracy
- Proportions
- Spacing and breathing room
- Visual hierarchy
- Anything that looks "off" that wasn't captured in Layers 1 & 2

**Viewport mismatch check:** If the Figma frame width (from `get_design_context` bounds) differs from the browser viewport by more than 10%, note this in the report's Minor section.

---

## Step 5 — Deep Inspect (Optional, on demand)

If the pixel diff shows mismatches but the root element styles look correct, the problem is likely in a child element. Run:

```bash
node scripts/deep-inspect.mjs \
  --url "{devUrl}" \
  --selector "{selector}" \
  --depth 2
```

This outputs a full style tree. Compare each child node against the Figma component tree to find the specific element causing the visual discrepancy.

---

## Step 6 — Output the DSQA Report

The report is written in Portuguese. Do not translate section headers or status labels.

```markdown
## DSQA Report — {ComponentName}

**Resultado:** ✅ Pass | ⚠️ Needs Work | ❌ Fail
**Figma:** {url}
**Dev URL:** {url}
**Viewport:** {width}px
**Pixel diff:** {mismatchPercentage}% ({mismatchPixels}/{totalPixels} pixels)
**Avaliado em:** {date}
**Método:** Script direto | Playwright MCP fallback

---

### 🔴 Critical — corrigir antes de mergear
(Cor/branding errado, fonte errada, layout quebrado)

- [ ] **{property}:** encontrado `{actual}`, Figma especifica `{expected}`
  - Arquivo: `{file}:{line}`
  - Fix: {specific suggestion}
  - Detectado via: {Figma JSON | Computed CSS | Pixel Diff}

### 🟡 Major — diferença visual perceptível
(Espaçamento >4px, font-weight errado, tamanho >10% diferente)

- [ ] ...

### 🟢 Minor — desvio pequeno, aceitável
(1-2px de variação, diferenças de renderização do browser)

- [ ] ...

---

### Matches confirmados ✅
- **{property}:** `{value}` ✅
...

---

### Próximos passos
{N} issues bloqueantes. {summary}.
{If issues exist: "Corrigir os itens Critical/Major e rodar /dsqa novamente."}
{If no issues: "Componente aprovado. Pode prosseguir."}
```

**Resultado definition:**
- ✅ Pass — zero Critical, zero Major, pixel diff < 5%
- ⚠️ Needs Work — zero Critical, 1+ Major OR pixel diff 5-15%
- ❌ Fail — 1+ Critical OR pixel diff > 15%

---

## Notes

- **Always prefer the script method over Playwright MCP** — it's 10-50x cheaper in tokens
- Always cite which layer detected each issue — this communicates confidence level
- If the dev server is not running, instruct the user to start it first
- If `get_design_context` returns a Code Connect snippet instead of raw specs, use the snippet's prop values as the Figma spec reference
- The `data-dsqa` attribute is recommended but not required — the scripts cascade through multiple selectors
- For components in the middle/bottom of a page, the scripts use `element.screenshot()` which captures ONLY that element (no full-page scroll needed)
