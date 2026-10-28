#!/bin/bash
# Returns the next ADR number in NNN format.
# Usage: bash bin/skill-scripts/adr/next-number.sh
#
# Reads docs/adrs/ADR-*.md to find the highest number, then increments.
# If no ADRs exist, returns 001.

set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

LAST=$(ls "${PROJECT_ROOT}/docs/adrs/ADR-"*.md 2>/dev/null | sort -t- -k2 -n | tail -1 | grep -oP 'ADR-\K\d{3}' || echo "000")
NEXT=$(printf "%03d" $((10#${LAST:-0} + 1)))
echo "$NEXT"
