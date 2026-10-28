#!/bin/bash
# Parses a Figma URL and extracts fileKey and nodeId.
# Usage: bash bin/skill-scripts/shared/figma-url-parser.sh "<figma-url>"
#
# Output (JSON): {"fileKey": "abc123", "nodeId": "1:234"}
#
# Handles URL-decoding of nodeId:
#   - %3A → : (percent-encoded colon)
#   - NNN-NNN → NNN:NNN (hyphen as separator, numeric only)

set -euo pipefail

URL="${1:?Usage: figma-url-parser.sh <figma-url>}"

FILE_KEY=$(echo "$URL" | grep -oP '(?:design|file)/\K[^/]+')
NODE_ID_RAW=$(echo "$URL" | grep -oP 'node-id=\K[^&]+' || echo "")

# Decode nodeId: prefer %3A decoding, fallback to numeric hyphen pattern
if echo "$NODE_ID_RAW" | grep -q '%3A'; then
  NODE_ID=$(echo "$NODE_ID_RAW" | sed 's/%3A/:/g')
else
  NODE_ID=$(echo "$NODE_ID_RAW" | sed 's/^\([0-9]*\)-\([0-9]*\)$/\1:\2/')
fi

cat <<EOF
{"fileKey": "$FILE_KEY", "nodeId": "$NODE_ID"}
EOF
