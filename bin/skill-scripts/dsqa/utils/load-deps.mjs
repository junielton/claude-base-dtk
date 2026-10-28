/**
 * Resolves the DSQA npm dependencies (puppeteer, pngjs, pixelmatch) from the
 * plugin-owned cache — never from the user's project.
 *
 * The cache is installed by `check-deps.sh --install` into
 * ${XDG_CACHE_HOME:-$HOME/.cache}/dtk. ESM `import()` ignores NODE_PATH, so the
 * packages are resolved with an explicit createRequire anchored in that dir.
 */

import { createRequire } from "node:module";
import { join } from "node:path";
import { homedir } from "node:os";

export const cacheDir = join(
  process.env.XDG_CACHE_HOME || join(homedir(), ".cache"),
  "dtk"
);

const requireFromCache = createRequire(join(cacheDir, "package.json"));

/** Load one cached dependency, or return null when it is not installed. */
export function loadDep(name) {
  try {
    const mod = requireFromCache(name);
    return mod && mod.default ? mod.default : mod;
  } catch {
    return null;
  }
}

export const installHint = `bash <scripts>/dsqa/check-deps.sh --install   # installs into ${cacheDir}`;
