#!/usr/bin/env node

/**
 * DSQA Capture & Compare
 *
 * Navigates to a URL, scrolls to a specific CSS selector, takes a screenshot
 * of ONLY that element, extracts computed styles, and optionally compares
 * against a reference image using pixelmatch.
 *
 * Usage:
 *   node capture-and-compare.mjs \
 *     --url http://localhost:3000/dev/components \
 *     --selector "[data-dsqa]" \
 *     --output ./dsqa-output \
 *     --reference ./figma-screenshot.png \
 *     --viewport 1440x900
 *
 * Output (JSON to stdout + files to --output dir):
 *   {
 *     "screenshot": "dsqa-output/element-screenshot.png",
 *     "diff": "dsqa-output/diff.png",              // only if --reference
 *     "mismatchPercentage": 2.34,                   // only if --reference
 *     "mismatchPixels": 1542,                       // only if --reference
 *     "totalPixels": 65920,                         // only if --reference
 *     "computedStyles": { ... },
 *     "boundingBox": { x, y, width, height },
 *     "viewport": { width, height },
 *     "selector": "[data-dsqa]",
 *     "url": "http://localhost:3000/dev/components",
 *     "timestamp": "2025-02-26T..."
 *   }
 */

import { parseArgs } from "node:util";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";

// ---------------------------------------------------------------------------
// CLI args
// ---------------------------------------------------------------------------
const { values: args } = parseArgs({
  options: {
    url: { type: "string" },
    selector: { type: "string", default: "[data-dsqa]" },
    output: { type: "string", default: "./dsqa-output" },
    reference: { type: "string" },
    viewport: { type: "string", default: "1440x900" },
    timeout: { type: "string", default: "10000" },
    "wait-for": { type: "string" }, // extra selector to wait for before capture
    "scroll-margin": { type: "string", default: "20" }, // px margin around element
    help: { type: "boolean", default: false },
  },
});

if (args.help || !args.url) {
  console.log(`
DSQA Capture & Compare — screenshot an element and compare to Figma reference

FLAGS:
  --url           (required) Page URL, e.g. http://localhost:3000/dev/components
  --selector      CSS selector for the target element (default: [data-dsqa])
  --output        Directory for output files (default: ./dsqa-output)
  --reference     Path to Figma reference image for pixel comparison
  --viewport      Browser viewport as WIDTHxHEIGHT (default: 1440x900)
  --timeout       Navigation timeout in ms (default: 10000)
  --wait-for      Extra CSS selector to wait for before capturing
  --scroll-margin Padding in px around the element screenshot (default: 20)
  --help          Show this help
`);
  process.exit(args.help ? 0 : 1);
}

// ---------------------------------------------------------------------------
// Dynamic imports (so the script fails gracefully if deps aren't installed)
// ---------------------------------------------------------------------------
let puppeteer, PNG, pixelmatch;

try {
  puppeteer = (await import("puppeteer")).default;
} catch {
  console.error(
    "❌ puppeteer not found. Install it:\n  npm install -g puppeteer\n  # or in your project:\n  npm install --save-dev puppeteer"
  );
  process.exit(1);
}

try {
  PNG = (await import("pngjs")).PNG;
  pixelmatch = (await import("pixelmatch")).default;
} catch {
  // pixelmatch/pngjs optional — comparison just won't run
  console.error(
    "⚠️  pngjs/pixelmatch not found — screenshot comparison will be skipped.\n  npm install --save-dev pngjs pixelmatch"
  );
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
const [vpW, vpH] = args.viewport.split("x").map(Number);
const outputDir = resolve(args.output);
await mkdir(outputDir, { recursive: true });

const browser = await puppeteer.launch({
  headless: "new",
  args: ["--no-sandbox", "--disable-setuid-sandbox"],
});

try {
  const page = await browser.newPage();
  await page.setViewport({ width: vpW, height: vpH });

  // Navigate
  console.error(`→ Navigating to ${args.url} ...`);
  await page.goto(args.url, {
    waitUntil: "networkidle2",
    timeout: Number(args.timeout),
  });

  // Optional: wait for extra selector
  if (args["wait-for"]) {
    console.error(`→ Waiting for ${args["wait-for"]} ...`);
    await page.waitForSelector(args["wait-for"], {
      timeout: Number(args.timeout),
    });
  }

  // Find target element — cascade through selectors
  const selectors = [
    args.selector,
    "[data-dsqa]",
    "main > *:first-child",
    "body > *:first-child",
  ];
  // dedupe while preserving order
  const uniqueSelectors = [...new Set(selectors)];

  let elementHandle = null;
  let matchedSelector = null;

  for (const sel of uniqueSelectors) {
    elementHandle = await page.$(sel);
    if (elementHandle) {
      matchedSelector = sel;
      break;
    }
  }

  if (!elementHandle) {
    const result = {
      error: `No element found for selectors: ${uniqueSelectors.join(", ")}`,
      url: args.url,
      timestamp: new Date().toISOString(),
    };
    console.log(JSON.stringify(result, null, 2));
    process.exit(1);
  }

  console.error(`→ Found element via "${matchedSelector}"`);

  // Scroll into view
  await elementHandle.evaluate((el) =>
    el.scrollIntoView({ block: "center", behavior: "instant" })
  );

  // Small wait for any scroll-triggered animations/lazy-load
  await page.evaluate(() => new Promise((r) => setTimeout(r, 300)));

  // Get bounding box
  const boundingBox = await elementHandle.boundingBox();

  // Take element-only screenshot (no full page scroll needed!)
  const margin = Number(args["scroll-margin"]);
  const screenshotPath = join(outputDir, "element-screenshot.png");

  await elementHandle.screenshot({
    path: screenshotPath,
    // clip with margin for context
  });

  console.error(`→ Screenshot saved: ${screenshotPath}`);

  // Extract computed styles
  const computedStyles = await elementHandle.evaluate((el) => {
    const s = window.getComputedStyle(el);

    // Helper: rgb to hex
    const rgbToHex = (rgb) => {
      if (!rgb || rgb === "rgba(0, 0, 0, 0)") return "transparent";
      const match = rgb.match(
        /rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)/
      );
      if (!match) return rgb;
      const [, r, g, b, a] = match;
      if (a !== undefined && parseFloat(a) === 0) return "transparent";
      return (
        "#" +
        [r, g, b]
          .map((x) =>
            parseInt(x)
              .toString(16)
              .padStart(2, "0")
          )
          .join("")
          .toUpperCase()
      );
    };

    return {
      backgroundColor: rgbToHex(s.backgroundColor),
      color: rgbToHex(s.color),
      fontFamily: s.fontFamily,
      fontSize: s.fontSize,
      fontWeight: s.fontWeight,
      lineHeight: s.lineHeight,
      letterSpacing: s.letterSpacing === "normal" ? "0px" : s.letterSpacing,
      paddingTop: s.paddingTop,
      paddingRight: s.paddingRight,
      paddingBottom: s.paddingBottom,
      paddingLeft: s.paddingLeft,
      marginTop: s.marginTop,
      marginRight: s.marginRight,
      marginBottom: s.marginBottom,
      marginLeft: s.marginLeft,
      borderRadius: s.borderRadius,
      boxShadow: s.boxShadow === "none" ? "none" : s.boxShadow,
      border: s.border,
      display: s.display,
      gap: s.gap,
      flexDirection: s.flexDirection,
      alignItems: s.alignItems,
      justifyContent: s.justifyContent,
      width: s.width,
      height: s.height,
      // Also capture child count for layout analysis
      childCount: el.children.length,
    };
  });

  // Extract children computed styles (first level only, for layout comparison)
  const childrenStyles = await elementHandle.evaluate((el) => {
    const rgbToHex = (rgb) => {
      if (!rgb || rgb === "rgba(0, 0, 0, 0)") return "transparent";
      const match = rgb.match(
        /rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)/
      );
      if (!match) return rgb;
      const [, r, g, b, a] = match;
      if (a !== undefined && parseFloat(a) === 0) return "transparent";
      return (
        "#" +
        [r, g, b]
          .map((x) =>
            parseInt(x)
              .toString(16)
              .padStart(2, "0")
          )
          .join("")
          .toUpperCase()
      );
    };

    return [...el.children].slice(0, 10).map((child, i) => {
      const s = window.getComputedStyle(child);
      return {
        index: i,
        tag: child.tagName.toLowerCase(),
        className: child.className?.toString().slice(0, 80) || "",
        text: child.textContent?.slice(0, 50) || "",
        backgroundColor: rgbToHex(s.backgroundColor),
        color: rgbToHex(s.color),
        fontSize: s.fontSize,
        fontWeight: s.fontWeight,
        padding: `${s.paddingTop} ${s.paddingRight} ${s.paddingBottom} ${s.paddingLeft}`,
        width: s.width,
        height: s.height,
      };
    });
  });

  // Build result
  const result = {
    screenshot: screenshotPath,
    computedStyles,
    childrenStyles,
    boundingBox,
    viewport: { width: vpW, height: vpH },
    selector: matchedSelector,
    url: args.url,
    timestamp: new Date().toISOString(),
  };

  // ---------------------------------------------------------------------------
  // Pixel comparison (if reference provided and deps available)
  // ---------------------------------------------------------------------------
  if (args.reference && PNG && pixelmatch) {
    console.error(`→ Comparing against reference: ${args.reference}`);

    try {
      const refBuffer = await readFile(resolve(args.reference));
      const testBuffer = await readFile(screenshotPath);

      const refImg = PNG.sync.read(refBuffer);
      const testImg = PNG.sync.read(testBuffer);

      // Resize to match if needed (use the smaller dimensions)
      const width = Math.min(refImg.width, testImg.width);
      const height = Math.min(refImg.height, testImg.height);

      // Crop both images to the common size
      const cropPNG = (img, w, h) => {
        if (img.width === w && img.height === h) return img;
        const cropped = new PNG({ width: w, height: h });
        for (let y = 0; y < h; y++) {
          for (let x = 0; x < w; x++) {
            const srcIdx = (y * img.width + x) << 2;
            const dstIdx = (y * w + x) << 2;
            cropped.data[dstIdx] = img.data[srcIdx];
            cropped.data[dstIdx + 1] = img.data[srcIdx + 1];
            cropped.data[dstIdx + 2] = img.data[srcIdx + 2];
            cropped.data[dstIdx + 3] = img.data[srcIdx + 3];
          }
        }
        return cropped;
      };

      const refCropped = cropPNG(refImg, width, height);
      const testCropped = cropPNG(testImg, width, height);

      const diffImg = new PNG({ width, height });
      const mismatchPixels = pixelmatch(
        refCropped.data,
        testCropped.data,
        diffImg.data,
        width,
        height,
        {
          threshold: 0.1, // sensitivity (0 = exact, 1 = very loose)
          alpha: 0.3,
          diffColor: [255, 0, 0], // red for diffs
          diffColorAlt: [0, 255, 0], // green for anti-aliased diffs
          includeAA: false, // ignore anti-aliasing differences
        }
      );

      const totalPixels = width * height;
      const mismatchPercentage =
        Math.round((mismatchPixels / totalPixels) * 10000) / 100;

      const diffPath = join(outputDir, "diff.png");
      await writeFile(diffPath, PNG.sync.write(diffImg));

      // Also save a side-by-side composite
      const sideBySide = new PNG({ width: width * 3 + 4, height: height });
      // Fill with white separator
      for (let y = 0; y < height; y++) {
        for (let x = 0; x < sideBySide.width; x++) {
          const idx = (y * sideBySide.width + x) << 2;
          sideBySide.data[idx] = 255;
          sideBySide.data[idx + 1] = 255;
          sideBySide.data[idx + 2] = 255;
          sideBySide.data[idx + 3] = 255;
        }
      }
      // Paste ref | test | diff
      const paste = (src, offsetX) => {
        for (let y = 0; y < height; y++) {
          for (let x = 0; x < width; x++) {
            const srcIdx = (y * width + x) << 2;
            const dstIdx = (y * sideBySide.width + (x + offsetX)) << 2;
            sideBySide.data[dstIdx] = src.data[srcIdx];
            sideBySide.data[dstIdx + 1] = src.data[srcIdx + 1];
            sideBySide.data[dstIdx + 2] = src.data[srcIdx + 2];
            sideBySide.data[dstIdx + 3] = src.data[srcIdx + 3];
          }
        }
      };
      paste(refCropped, 0);
      paste(testCropped, width + 2);
      paste(diffImg, width * 2 + 4);

      const compositePath = join(outputDir, "side-by-side.png");
      await writeFile(compositePath, PNG.sync.write(sideBySide));

      result.diff = diffPath;
      result.composite = compositePath;
      result.mismatchPixels = mismatchPixels;
      result.totalPixels = totalPixels;
      result.mismatchPercentage = mismatchPercentage;
      result.sizeDifference =
        refImg.width !== testImg.width || refImg.height !== testImg.height
          ? {
              reference: { width: refImg.width, height: refImg.height },
              test: { width: testImg.width, height: testImg.height },
            }
          : null;

      console.error(
        `→ Comparison: ${mismatchPercentage}% mismatch (${mismatchPixels}/${totalPixels} pixels)`
      );
      console.error(`→ Diff image: ${diffPath}`);
      console.error(`→ Side-by-side: ${compositePath}`);
    } catch (err) {
      result.comparisonError = err.message;
      console.error(`⚠️  Comparison failed: ${err.message}`);
    }
  }

  // Save full JSON report
  const reportPath = join(outputDir, "dsqa-data.json");
  await writeFile(reportPath, JSON.stringify(result, null, 2));
  result.reportPath = reportPath;

  // Output to stdout for the LLM to consume
  console.log(JSON.stringify(result, null, 2));
} finally {
  await browser.close();
}
