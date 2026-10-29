#!/bin/bash
# Checks (and optionally installs) the DSQA dependencies: puppeteer, pngjs, pixelmatch.
# Usage: bash bin/skill-scripts/dsqa/check-deps.sh [--install]
#
# The deps live in a plugin-owned cache, never in the user's project:
#   ${XDG_CACHE_HOME:-$HOME/.cache}/dtk        (one package.json, pinned versions)
# Clear it with:  rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/dtk"
#
# Exits 0 if all deps are available in the cache, 1 if any are missing
# (or, with --install, if the install failed). Also verifies the DSQA scripts exist.

set -euo pipefail

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/dtk"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Pinned: bump here and the cache reinstalls itself on the next --install.
PUPPETEER_VERSION="25.16.0"
PNGJS_VERSION="7.0.0"
PIXELMATCH_VERSION="5.3.0"   # last CommonJS release; the scripts load it via createRequire

INSTALL=false
case "${1:-}" in
  --install) INSTALL=true ;;
  "") ;;
  *) echo "Usage: check-deps.sh [--install]" >&2; exit 2 ;;
esac

SCRIPTS_OK=true
for script in capture-and-compare.mjs deep-inspect.mjs utils/color-utils.mjs utils/load-deps.mjs; do
  if [ ! -f "${SCRIPT_DIR}/$script" ]; then
    echo "Missing script: ${SCRIPT_DIR}/$script"
    SCRIPTS_OK=false
  fi
done

if [ "$SCRIPTS_OK" = false ]; then
  echo "DSQA scripts not found next to check-deps.sh — the plugin install looks corrupted; try reinstalling the dtk plugin."
  exit 1
fi

# Echo each dep that is missing from the cache or installed at a different version than the pin.
missing_deps() {
  local dep want have
  for pair in "puppeteer:$PUPPETEER_VERSION" "pngjs:$PNGJS_VERSION" "pixelmatch:$PIXELMATCH_VERSION"; do
    dep="${pair%%:*}"; want="${pair##*:}"
    have=$(sed -n 's/^[[:space:]]*"version":[[:space:]]*"\([^"]*\)".*/\1/p' "${CACHE_DIR}/node_modules/${dep}/package.json" 2>/dev/null | head -1 || true)
    [ "$have" = "$want" ] || echo "$dep"
  done
}

MISSING=$(missing_deps | tr '\n' ' ')

if [ -n "${MISSING// /}" ] && [ "$INSTALL" = true ]; then
  mkdir -p "$CACHE_DIR"
  cat > "${CACHE_DIR}/package.json" <<JSON
{
  "name": "dtk-qa-cache",
  "private": true,
  "description": "Dependencies for the dtk dsqa / mockup-qa skills. Safe to delete: rm -rf ${CACHE_DIR}",
  "dependencies": {
    "pixelmatch": "${PIXELMATCH_VERSION}",
    "pngjs": "${PNGJS_VERSION}",
    "puppeteer": "${PUPPETEER_VERSION}"
  }
}
JSON
  echo "Installing DSQA dependencies into ${CACHE_DIR} (first run downloads Chromium) ..." >&2
  npm install --prefix "$CACHE_DIR" --no-audit --no-fund --loglevel=error >&2
  MISSING=$(missing_deps | tr '\n' ' ')
fi

if [ -n "${MISSING// /}" ]; then
  echo "Missing npm packages in ${CACHE_DIR}: ${MISSING}"
  echo "Install: bash ${SCRIPT_DIR}/check-deps.sh --install"
  exit 1
fi

echo "All DSQA dependencies installed (cache: ${CACHE_DIR})."
