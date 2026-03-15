#!/usr/bin/env node

/**
 * DSQA Deep Inspect — extracts full style tree from a component
 *
 * Unlike capture-and-compare which grabs the root element + first-level children,
 * this goes 2 levels deep and captures layout-critical CSS properties for every
 * visible element in the component tree.
 *
 * Usage:
 *   node deep-inspect.mjs \
 *     --url http://localhost:3000/dev/components \
 *     --selector "[data-dsqa]" \
 *     --output ./dsqa-output/deep-inspect.json
 *
 * This is useful when the pixel diff shows mismatches but the root element
 * styles look correct — the problem is likely in a child element.
 */

import { parseArgs } from "node:util";
import { writeFile, mkdir } from "node:fs/promises";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { injectRgbToHex } from "./utils/color-utils.mjs";

const { values: args } = parseArgs({
  options: {
    url: { type: "string" },
    selector: { type: "string", default: "[data-dsqa]" },
    output: { type: "string", default: "./dsqa-output/deep-inspect.json" },
    viewport: { type: "string", default: "1440x900" },
    depth: { type: "string", default: "2" },
    timeout: { type: "string", default: "10000" },
  },
});

if (!args.url) {
  console.error("Usage: node deep-inspect.mjs --url <URL> [--selector SEL]");
  process.exit(1);
}

let puppeteer;
try {
  puppeteer = (await import("puppeteer")).default;
} catch {
  console.error("❌ puppeteer not found. npm install puppeteer");
  process.exit(1);
}

const [vpW, vpH] = args.viewport.split("x").map(Number);
const maxDepth = Number(args.depth);

const browser = await puppeteer.launch({
  headless: "new",
  args: ["--no-sandbox", "--disable-setuid-sandbox"],
});

try {
  const page = await browser.newPage();
  await page.setViewport({ width: vpW, height: vpH });
  await page.goto(args.url, {
    waitUntil: "networkidle2",
    timeout: Number(args.timeout),
  });

  // Inject shared rgbToHex helper into browser context
  await injectRgbToHex(page);

  const el = await page.$(args.selector);
  if (!el) {
    console.log(JSON.stringify({ error: `Selector not found: ${args.selector}` }));
    process.exit(1);
  }

  const tree = await el.evaluate((root, depth) => {
    const hex = window.__rgbToHex;

    const extract = (el, currentDepth) => {
      const s = window.getComputedStyle(el);
      const rect = el.getBoundingClientRect();

      const node = {
        tag: el.tagName.toLowerCase(),
        className: (el.className?.toString() || "").slice(0, 100),
        text: el.childNodes.length === 1 && el.childNodes[0].nodeType === 3
          ? el.textContent.trim().slice(0, 60)
          : null,
        rect: {
          x: Math.round(rect.x),
          y: Math.round(rect.y),
          w: Math.round(rect.width),
          h: Math.round(rect.height),
        },
        styles: {
          display: s.display,
          flexDirection: s.flexDirection !== "row" ? s.flexDirection : undefined,
          gap: s.gap !== "normal" ? s.gap : undefined,
          alignItems: s.alignItems !== "normal" ? s.alignItems : undefined,
          justifyContent: s.justifyContent !== "normal" ? s.justifyContent : undefined,
          backgroundColor: hex(s.backgroundColor),
          color: hex(s.color),
          fontSize: s.fontSize,
          fontWeight: s.fontWeight !== "400" ? s.fontWeight : undefined,
          fontFamily: s.fontFamily?.split(",")[0]?.trim().replace(/['"]/g, ""),
          lineHeight: s.lineHeight,
          letterSpacing: s.letterSpacing !== "normal" ? s.letterSpacing : undefined,
          padding: `${s.paddingTop} ${s.paddingRight} ${s.paddingBottom} ${s.paddingLeft}`,
          margin: `${s.marginTop} ${s.marginRight} ${s.marginBottom} ${s.marginLeft}`,
          borderRadius: s.borderRadius !== "0px" ? s.borderRadius : undefined,
          border: s.borderStyle !== "none" ? s.border : undefined,
          boxShadow: s.boxShadow !== "none" ? s.boxShadow : undefined,
        },
      };

      // Remove undefined values to keep output compact
      node.styles = Object.fromEntries(
        Object.entries(node.styles).filter(([, v]) => v !== undefined && v !== "transparent" && v !== null)
      );

      if (currentDepth < depth && el.children.length > 0) {
        node.children = [...el.children]
          .slice(0, 15) // cap per level to avoid huge output
          .filter(child => {
            const cs = window.getComputedStyle(child);
            return cs.display !== "none" && cs.visibility !== "hidden";
          })
          .map(child => extract(child, currentDepth + 1));
      }

      return node;
    };

    return extract(root, 0);
  }, maxDepth);

  const outPath = resolve(args.output);
  await mkdir(dirname(outPath), { recursive: true });
  await writeFile(outPath, JSON.stringify(tree, null, 2));

  console.log(JSON.stringify(tree, null, 2));
} finally {
  await browser.close();
}
