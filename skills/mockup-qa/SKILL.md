---
name: mockup-qa
description: "Use when verifying that a built UI matches an approved HTML mockup (a docs/design/<slug>/ folder with mockup.json and screens/), after implementing from a mockup, before closing a mockup-driven card, or when the user asks 'tá igual ao mockup?', 'confere com o aprovado', or disputes parity. The HTML-mockup sibling of dtk:dsqa (Figma). Do NOT use when the source is Figma or when no approved mockup exists."
---

# mockup-qa

Compare an approved mockup, screen by screen and state by state, against the running app.
Both sides render in the same engine, so computed styles must be **equal** and the pixel
diff is trustworthy. Read `../create-mockup/references/mockup-convention.md` (`$MK/references/…`) first.

## Step 0 — scripts and gate

```bash
# resolver idiom: docs/conventions/script-resolution.md
SCRIPTS="${CLAUDE_PLUGIN_ROOT}/scripts"; [ -d "$SCRIPTS" ] || echo "dtk: scripts dir not found: $SCRIPTS" >&2; echo "$SCRIPTS"
MK="${CLAUDE_PLUGIN_ROOT}/skills/create-mockup"; echo "$MK"
bash $SCRIPTS/dsqa/check-deps.sh --install
node $SCRIPTS/mockup/check-mockup.mjs <folder> --tokens-source <tokensFrom>
```

Checker errors → the mockup is not a valid contract; stop and say so.

**Dependency cache and comparison assumptions**

- **Cache:** `${XDG_CACHE_HOME:-$HOME/.cache}/dtk` — one pinned `package.json` plus `node_modules` (puppeteer, pngjs, pixelmatch). Installed once by `check-deps.sh --install`, reused by every run, shared with `dsqa`. Nothing is written to the user's project: its `package.json`, lockfile and `node_modules` stay untouched.
- **Clear it:** `rm -rf ~/.cache/dtk` (or `"$XDG_CACHE_HOME/dtk"`). The next `--install` rebuilds it; the first install also downloads Chromium (puppeteer's own cache, `~/.cache/puppeteer`).
- **Comparison assumptions:** the mockup capture and the app capture must share the same viewport (`--viewport <w>x900` per screen), `deviceScaleFactor` **1** (fixed by the script) and the same element crop (`element.screenshot()` of the selector). A non-null `sizeDifference` in the result means crop or scale is misaligned and the pixel % must not be trusted. `pixelmatch` runs with `threshold 0.1`, anti-aliasing ignored.
- **Alignment is tested:** `node --test 'bin/skill-scripts/dsqa/tests/*.test.mjs'` renders a fixture pair at 1280×800 and asserts 0% for identical pages and >0% for a 4px shift.

## 1. Resolve inputs

- **Mockup folder** and `mockup.json`. Only screens with `status: "approved"` are verified;
  a draft screen is refused with "needs approval in dtk:create-mockup".
- **Dev URL + state** per screen: where the app renders it and how each mockup state is
  reached (fixture, dev switch, real action). No way to reach a state → that state is
  reported as *unverifiable*, never skipped silently.
- **App selector**: `[data-dsqa="<id>"]` on the real root if present; else the most specific
  stable selector. Suggest adding `data-dsqa` when absent.

## 2. Layer 1 — contract capture (mockup side)

For each approved screen × state × viewport:

```bash
node $SCRIPTS/dsqa/capture-and-compare.mjs \
  --url "file://<abs>/screens/<id>.html?state=<s>" --selector '[data-dsqa="<id>"]' \
  --viewport <w>x900 --output ./mockup-qa/<id>-<s>-<w>/spec
```

Also read the screen file + `mockup.css` + its parts and write the **anatomy checklist**:
which element carries which style, which part renders which subtree. Similar pixels with a
different tree are different components.

## 3. Layer 2 — app capture + pixel diff

```bash
node $SCRIPTS/dsqa/capture-and-compare.mjs \
  --url "<devUrl>" --selector "<appSelector>" --viewport <w>x900 \
  --reference ./mockup-qa/<id>-<s>-<w>/spec/element-screenshot.png \
  --output ./mockup-qa/<id>-<s>-<w>/app
```

Navigation fails → tell the user to start the dev server and stop. Never "verify" from code.

## 4. Layer 3 — compare

**a) Computed styles, strict.** Diff `computedStyles` + `childrenStyles` property by
property. Equal, not close. Exceptions: `width`/`height` driven by different content, and
properties the mockup leaves free (say which).

**b) Anatomy.** Walk the app DOM against the checklist. A style on the wrong element is
**Critical** even when the pixels look alike.

**c) Pixel diff, data-aware.** Sample data seeded as in the mockup: < 1% Pass · 1–5% Needs
Work · > 5% Fail. Live data: advisory only; judge via `side-by-side.png`. Always look at the
composite yourself.

**d) Flows.** For each flow in `mockup.json`, in a real browser (Harnu pane, Playwright or
Chrome tools): click the trigger named in `via` on the app, assert the destination screen
and state. A missing transition is **Major**; a transition to the wrong screen is
**Critical**. The router file is not evidence.

Optional: `node $SCRIPTS/dsqa/deep-inspect.mjs --url "<devUrl>" --selector "<sel>" --depth 2`
when pixels differ but the root matches (the deviation is in a child).

## 5. Report (English)

```markdown
## Mockup QA Report — <slug>

**Result:** ✅ Pass | ⚠️ Needs Work | ❌ Fail
**Mockup:** <folder> · screens verified: <n>/<approved> · states: <n> · flows: <n>
**Dev URL(s):** … · **Viewports:** … · **Method:** capture-and-compare (file:// vs app) + flow walk

### Per screen
| screen | state | viewport | styles | anatomy | pixel | verdict |

### 🔴 Critical — fix before merging
- [ ] **<screen>/<state> · <property or anatomy>:** app `<actual>`, mockup `<expected>` · File `<path:line>` · Fix: … · Detected via: Styles | Anatomy | Pixel | Flow

### 🟡 Major   ### 🟢 Minor   ### Unverifiable (state unreachable, and why)
### Confirmed matches ✅
### Evidence — side-by-side composites: <paths>
### Next steps
```

✅ zero Critical, zero Major, pixel within threshold, every flow walks · ⚠️ zero Critical,
1+ Major · ❌ 1+ Critical (anatomy, token and wrong-destination findings are always Critical).

## Common mistakes

| Mistake | Fix |
|---|---|
| Verifying by reading code | Both captures and the flow walk are mandatory |
| Trusting a low pixel diff over anatomy | Anatomy is authoritative |
| Figma-era tolerance | Same engine: styles equal, diff < 1% with seeded data |
| Capturing `index.html` | It is presentation; always `screens/<id>.html?state=…` |
| Verifying the default state only | Every declared state, every viewport |
| Verifying a draft screen | Refuse; approval first |
