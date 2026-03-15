#!/bin/bash
# Checks DSQA dependencies (puppeteer, pngjs, pixelmatch).
# Usage: bash bin/skill-scripts/dsqa/check-deps.sh
#
# Exits 0 if all deps are available, 1 if any are missing.
# Also verifies that the DSQA scripts exist.

set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# Check scripts exist
SCRIPTS_OK=true
for script in bin/skill-scripts/dsqa/capture-and-compare.mjs bin/skill-scripts/dsqa/deep-inspect.mjs bin/skill-scripts/dsqa/utils/color-utils.mjs; do
  if [ ! -f "${PROJECT_ROOT}/$script" ]; then
    echo "Missing script: $script"
    SCRIPTS_OK=false
  fi
done

if [ "$SCRIPTS_OK" = false ]; then
  echo "Run /dtk:bootstrap to copy DSQA scripts to your project."
  exit 1
fi

# Check node_modules exists
if [ ! -d "${PROJECT_ROOT}/node_modules" ]; then
  echo "node_modules not found — run: npm install"
  exit 1
fi

# Check npm packages (local + global)
MISSING=()

for dep in puppeteer pngjs pixelmatch; do
  if ! npm list "$dep" >/dev/null 2>&1 && ! npm list -g "$dep" >/dev/null 2>&1; then
    MISSING+=("$dep")
  fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "Missing npm packages: ${MISSING[*]}"
  echo "Install: npm install --save-dev ${MISSING[*]}"
  exit 1
fi

echo "All DSQA dependencies installed."
