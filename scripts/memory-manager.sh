#!/bin/bash
# DTK — Review Memory Manager
# Manages the memories/reviews/ directory for persistent review tracking.
# Usage: bash memory-manager.sh <action> [options]
#
# Actions:
#   init <review-id>          — Create memory dir, output JSON with state info
#   next-number <review-id> <prefix>  — Get next sequential review number
#   save-state <review-id>    — Reads stdin as new state content, saves to review-state.md

set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
MEMORY_BASE="${PROJECT_ROOT}/memories/reviews"

ACTION="${1:-help}"
shift || true

case "$ACTION" in
  init)
    REVIEW_ID="${1:?Usage: memory-manager.sh init <review-id>}"
    MEMORY_DIR="${MEMORY_BASE}/${REVIEW_ID}"

    mkdir -p "$MEMORY_DIR"

    STATE_EXISTS="false"
    STATE_CONTENT=""
    if [[ -f "${MEMORY_DIR}/review-state.md" ]]; then
      STATE_EXISTS="true"
      STATE_CONTENT=$(cat "${MEMORY_DIR}/review-state.md")
    fi

    # Count existing reviews
    REVIEW_COUNT=$(find "$MEMORY_DIR" -maxdepth 1 -name "review-*.md" ! -name "review-state.md" 2>/dev/null | wc -l || echo "0")
    PEER_COUNT=$(find "$MEMORY_DIR" -maxdepth 1 -name "peer-review-*.md" 2>/dev/null | wc -l || echo "0")

    # Output JSON
    cat <<EOF
{
  "memory_dir": "$MEMORY_DIR",
  "state_exists": $STATE_EXISTS,
  "review_count": $REVIEW_COUNT,
  "peer_review_count": $PEER_COUNT,
  "is_first_review": $([ "$STATE_EXISTS" = "true" ] && echo "false" || echo "true")
}
EOF

    # If state exists, output it to stderr so the caller can capture both
    if [[ "$STATE_EXISTS" = "true" ]]; then
      echo "---STATE_CONTENT_START---" >&2
      echo "$STATE_CONTENT" >&2
      echo "---STATE_CONTENT_END---" >&2
    fi
    ;;

  next-number)
    REVIEW_ID="${1:?Usage: memory-manager.sh next-number <review-id> <prefix>}"
    PREFIX="${2:-review}"
    MEMORY_DIR="${MEMORY_BASE}/${REVIEW_ID}"

    LAST=$(find "$MEMORY_DIR" -maxdepth 1 -name "${PREFIX}-*.md" ! -name "review-state.md" 2>/dev/null | \
      grep -oP "${PREFIX}-\K\d+" | sort -n | tail -1 || echo "0")
    NEXT=$((${LAST:-0} + 1))

    echo "$NEXT"
    ;;

  save-state)
    REVIEW_ID="${1:?Usage: memory-manager.sh save-state <review-id>}"
    MEMORY_DIR="${MEMORY_BASE}/${REVIEW_ID}"

    mkdir -p "$MEMORY_DIR"
    cat > "${MEMORY_DIR}/review-state.md"

    echo "Saved to: ${MEMORY_DIR}/review-state.md"
    ;;

  help|*)
    cat <<EOF
DTK Review Memory Manager

Usage: bash memory-manager.sh <action> [options]

Actions:
  init <review-id>                 Initialize memory dir, return state info as JSON
  next-number <review-id> <prefix> Get next sequential number for review files
  save-state <review-id>           Save review state (reads content from stdin)

Examples:
  bash memory-manager.sh init "feature/login"
  bash memory-manager.sh init "PR-123"
  bash memory-manager.sh next-number "PR-123" "peer-review"
  echo "# State..." | bash memory-manager.sh save-state "PR-123"
EOF
    ;;
esac
