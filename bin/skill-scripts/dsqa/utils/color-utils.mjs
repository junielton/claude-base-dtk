/**
 * Shared color utilities for DSQA scripts.
 *
 * Canonical implementation of rgbToHex — used by both
 * capture-and-compare.mjs and deep-inspect.mjs.
 *
 * NOTE: This module is for Node.js context. For browser context (page.evaluate),
 * use the injectRgbToHex() helper which defines window.__rgbToHex via page.evaluate.
 */

/**
 * Converts an rgb/rgba CSS color string to uppercase hex.
 * Returns "transparent" for fully transparent colors.
 *
 * @param {string} rgb - CSS color value like "rgb(255, 0, 0)" or "rgba(0, 0, 0, 0)"
 * @returns {string} Hex color like "#FF0000" or "transparent"
 */
export function rgbToHex(rgb) {
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
      .map((x) => parseInt(x).toString(16).padStart(2, "0"))
      .join("")
      .toUpperCase()
  );
}

/**
 * Injects the rgbToHex function into a Puppeteer page's browser context
 * as window.__rgbToHex. Call this once before any page.evaluate() that needs
 * color conversion.
 *
 * @param {import('puppeteer').Page} page - Puppeteer page instance
 */
export async function injectRgbToHex(page) {
  await page.evaluate(() => {
    window.__rgbToHex = (rgb) => {
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
          .map((x) => parseInt(x).toString(16).padStart(2, "0"))
          .join("")
          .toUpperCase()
      );
    };
  });
}
