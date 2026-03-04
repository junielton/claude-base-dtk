---
name: implement-design
description: Full workflow for implementing a UI component from a Figma design — covers rebrand of existing components and creation of new ones from scratch. Handles context gathering (Figma + codebase), planning, execution, and DSQA verification automatically. Use whenever implementing or rebranding any UI component.
---

# implement-design

You are running the `/implement-design` skill. Your job is to take a Figma design and a component (existing or new) and implement it fully — from understanding the current state to verifying the final result with DSQA.

Do NOT skip any phase. Do NOT start implementing before completing the context-gathering phases.

---

## Phase 1 — Intake (Interactive)

Ask the user these questions **strictly one at a time**. Wait for each answer before asking the next.

**Q1:** "Qual o nome do componente? (ex: Header, Sidebar Values Card, Contact CTA)"

**Q2:** "Qual a URL do Figma para a versão **desktop**?"
- If the user doesn't provide one, keep asking. This is required.
- Extract `fileKey` and `nodeId` from the URL using this rule:
  - `figma.com/design/<fileKey>/...?node-id=<nodeId>`
  - URL-decode `nodeId`: replace `%3A` with `:`, replace `-` with `:`
  - Example: `node-id=2395-1234` → `2395:1234`

**Q3:** "Existe uma versão **mobile** no Figma? Se sim, qual a URL?"
- If yes: extract its `fileKey` and `nodeId` too.
- If no: note `mobile_figma: not provided` and continue.

**Q4:** "Qual a URL no localhost para visualizar esse componente? (ex: `localhost:3000/dev/components`)"

**Q5:** "Esse componente já existe no projeto? (sim / não / não sei)"
- If **não** or **não sei**: the skill will determine this in Phase 2.
- If **novo**: also ask "Em qual pasta devo criar o arquivo? (ex: `src/components/NomeDoComponente/`)"

Store all answers as working context. Now proceed to Phase 2.

---

## Phase 2 — Parallel Context Gathering

Dispatch two subagents simultaneously using the `Task` tool. Do NOT wait for one to finish before starting the other.

### Subagent A — Figma Extractor

Prompt this subagent with:

```
You are the Figma Extractor for the implement-design workflow.

Component: <name>
Figma desktop fileKey: <fileKey>
Figma desktop nodeId: <nodeId>
Figma mobile fileKey: <fileKey or "none">
Figma mobile nodeId: <nodeId or "none">

Your tasks:
1. Call get_design_context(fileKey, nodeId) for desktop
2. Call get_screenshot(fileKey, nodeId) for desktop
3. If mobile is provided: repeat both calls for mobile
4. From the design context, extract EVERY value:
   - fills → background colors (hex)
   - strokes → border colors
   - cornerRadius → border-radius
   - paddingLeft/Right/Top/Bottom
   - gap (if flex/grid layout)
   - Typography per text node: fontFamily, fontSize, fontWeight, lineHeight, letterSpacing
   - effects → box-shadow
   - All child elements: list every button, link, icon, text node, image, background
5. Compare the JSON output against the screenshot:
   - Identify anything VISIBLE in the screenshot that is NOT captured in the JSON
   - Note these as "visual gaps" with description
6. Check every button and link element: if no URL/href is specified → mark as "URL: a definir"
7. Return a complete structured report with all extracted values, visual gaps, and missing URLs.
```

### Subagent B — Codebase Explorer

Prompt this subagent with:

```
You are the Codebase Explorer for the implement-design workflow.

Component: <name>
Localhost URL: <url>
Is new component: <yes/no/unknown>

Your tasks:
1. Search the codebase for the component:
   - Use Grep to search for the component name in src/components/, src/app/
   - Use Glob pattern: src/components/**/<Name>* and src/app/**/<name>*
   - If found: identify the main component file and all imported sub-components
2. Read the main component file completely
3. Read all imported sub-components recursively (up to 2 levels deep)
4. Map from the code:
   - Props accepted (with types/defaults)
   - Internal state (useState, useReducer, etc.)
   - Data from CMS/GraphQL (WPGraphQL queries in src/lib/functions.js)
   - Hardcoded text strings (note each one for STATIC_CONTENT_TRACKER.md)
   - Chakra UI components used
   - Custom utilities or hooks used
5. Navigate to the localhost URL via Playwright:
   - browser_navigate(<localhost_url>)
   - If connection refused: note "dev server not running" and skip browser steps
   - Take a screenshot with browser_take_screenshot()
   - Note the current visual state
6. Return a structured report: files found, props, state, data sources, hardcoded text, screenshot path, current visual description.
```

Wait for BOTH subagents to complete before proceeding.

---

## Phase 3 — Merge, Validate, Document

### 3a. Merge Results

Combine findings from both subagents into a unified context.

### 3b. Detect Critical Gaps

These gaps **block** the workflow — pause and ask the user before continuing:

- A button/link that is functionally interactive but has no URL specified in Figma
- A font family used in Figma that cannot be identified
- An asset (image, icon) visible in the Figma screenshot but not present anywhere in the project

These gaps are **non-blocking** — annotate them and continue:

- Color slightly different from design system (<10% deviation) → use nearest design system token
- Spacing not matching exactly → use nearest Chakra UI token
- Mobile Figma not provided → note it and proceed with desktop only

If you detect a critical gap, present it clearly and wait for the user's answer before proceeding.

### 3c. Save Context Document

Save the following document to `docs/plans/YYYY-MM-DD-implement-<component-name>.md`:

```markdown
# Component: <Name>

**Date:** <today>
**Status:** rebrand | new
**Skill:** implement-design

## Figma URLs
- Desktop: <url>
- Mobile: <url or "not provided">

## Screenshots
- Figma desktop: <path or description>
- Figma mobile: <path or "not provided">
- Current browser: <path or "dev server not running">

## Figma Spec — Desktop

### Layout
<layout type, dimensions, flex/grid, alignment>

### Colors
<all colors as hex with role: background, text, border, etc.>

### Typography
<per text node: fontFamily, fontSize, fontWeight, lineHeight>

### Spacing
<padding, gap, margin values>

### Element Inventory
<complete list: every button, link, icon, text node, image, background — with content and state variants>

### Visual Gaps
<anything visible in screenshot not captured in JSON; mark "URL: a definir" for missing link targets>

## Figma Spec — Mobile
<same structure, or "not provided">

## Current Implementation

### Files
<list of files found>

### Props
<component props with types>

### State
<internal state>

### Data Sources
<CMS/GraphQL fields, hardcoded strings>

## Gap Analysis

### What Changes
<list of changes needed to match Figma>

### What Stays
<elements unchanged>

### Reusable Child Components
<existing components in the project that can be reused>

### New Files Needed
<if any>

## Open Questions
<any critical gaps that required user input — document the question and the user's answer>
```

### 3d. Update STATIC_CONTENT_TRACKER.md

If Subagent B found any hardcoded text strings in the component, add an entry to `STATIC_CONTENT_TRACKER.md` for each one that isn't already tracked.

---

## Phase 4 — Invoke writing-plans

Invoke the `writing-plans` skill, passing the context document as input.

The writing-plans skill will produce a detailed step-by-step implementation plan.

---

## Phase 5 — Invoke executing-plans

Invoke the `executing-plans` skill with the implementation plan generated in Phase 4.

The executing-plans skill will implement the component changes.

---

## Phase 6 — Automatic DSQA

After executing-plans completes, automatically invoke the `dsqa` skill.

Provide it:
- The Figma desktop URL from intake
- The localhost URL from intake
- The component name as the `data-dsqa` selector (convert to kebab-case: "Sidebar Values Card" → `sidebar-values-card`)

The DSQA skill will verify the implementation against the Figma spec and report any deviations.

---

## Rules

- **Never start implementing before Phase 3 is complete.** Context first, code second.
- **Always gather both desktop and mobile Figma** — if mobile is missing, ask before proceeding.
- **One question at a time** in Phase 1. Do not ask multiple questions in one message.
- **Never guess** file locations — search the codebase explicitly.
- **Always take screenshots** — both from Figma and from the browser — for visual reference.
- **Trust the DSQA** — it is the final authority on whether the implementation matches the design.
- If the dev server is not running when Subagent B tries to connect: note it, continue the workflow, and remind the user to start `npm run dev` before Phase 6.
