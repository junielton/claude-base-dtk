#!/bin/bash
#
# Manages persistent review state for review skills.
#
# Usage:
#   bash scripts/review/memory-manager.sh init <identifier>
#   bash scripts/review/memory-manager.sh next-number <identifier> <prefix>
#   bash scripts/review/memory-manager.sh save-state <identifier>   (reads stdin)
#   bash scripts/review/memory-manager.sh template <identifier> <type>
#   bash scripts/review/memory-manager.sh pr-number <argument>
#
# <identifier> is either "PR-NNNN" or a branch name. "PR-#NNNN" and "PR-<pull URL>" are
# normalized to "PR-NNNN", so a review never lands in a "PR-#NNNN" directory.
# <argument> is what a skill received as the PR: "184", "#184" or a pull URL.
# <prefix> is "review" or "peer-review".
# <type> is "review", "review-local", or "peer-review".

set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
MEMORY_BASE="${PROJECT_ROOT}/memories/reviews"

ACTION="${1:-help}"
shift || true

# pr_number <argument>: prints the bare PR number for "184", "#184" or
# "https://github.com/<owner>/<repo>/pull/184[/files][#…]"; returns 1 when there is none.
pr_number() {
  local arg="$1"
  arg="${arg#"${arg%%[![:space:]]*}"}"; arg="${arg%"${arg##*[![:space:]]}"}"
  if [[ "$arg" =~ ^#?([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]}"
  elif [[ "$arg" =~ ^https?://[^[:space:]]+/pull/([0-9]+)([/?#].*)?$ ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    return 1
  fi
}

# normalize_id <identifier>: "PR-#184" or "PR-<pull URL>" become "PR-184"; anything else is kept.
normalize_id() {
  local id="$1" n
  if [[ "$id" == PR-* ]] && n=$(pr_number "${id#PR-}"); then
    echo "PR-$n"
  else
    echo "$id"
  fi
}

case "$ACTION" in
  init)
    REVIEW_ID="${1:?Usage: memory-manager.sh init <review-id>}"
    REVIEW_ID=$(normalize_id "$REVIEW_ID")
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
    REVIEW_ID=$(normalize_id "$REVIEW_ID")
    PREFIX="${2:-review}"
    MEMORY_DIR="${MEMORY_BASE}/${REVIEW_ID}"

    LAST=$(find "$MEMORY_DIR" -maxdepth 1 -name "${PREFIX}-*.md" ! -name "review-state.md" 2>/dev/null | \
      grep -oP "${PREFIX}-\K\d+" | sort -n | tail -1 || echo "0")
    NEXT=$((${LAST:-0} + 1))

    echo "$NEXT"
    ;;

  save-state)
    REVIEW_ID="${1:?Usage: memory-manager.sh save-state <review-id>}"
    REVIEW_ID=$(normalize_id "$REVIEW_ID")
    MEMORY_DIR="${MEMORY_BASE}/${REVIEW_ID}"

    mkdir -p "$MEMORY_DIR"
    cat > "${MEMORY_DIR}/review-state.md"

    echo "Saved to: ${MEMORY_DIR}/review-state.md"
    ;;

  template)
    REVIEW_ID="${1:?Usage: memory-manager.sh template <review-id> <type>}"
    REVIEW_ID=$(normalize_id "$REVIEW_ID")
    TYPE="${2:-review}"

    case "$TYPE" in
      review)
        cat <<'TEMPLATE'
# Review State — PR #{PR_NUMBER}

## Metadata
- Identifier: PR #{PR_NUMBER}
- Branch: {branch name}
- Reviews: {count} (last: YYYY-MM-DD)
- Types: review

## Decisions
## Coverage
## Open Items
## Resolved Items
## Notes
TEMPLATE
        ;;
      review-local)
        cat <<'TEMPLATE'
# Review State — {branch-name}

## Metadata
- Identifier: {branch-name}
- Branch: {branch-name}
- Reviews: {count} (last: YYYY-MM-DD)
- Types: review

## Decisions
- `file:line` — Description of decision (review-N)

## Coverage
- Files analyzed: file1, file2, ...
- Key methods: Class::method(), ...

## Open Items
- [ ] `file:line` — Description (raised review-N, still open review-M)

## Resolved Items
- [x] `file:line` — Description (raised review-N, resolved review-M)

## Notes
- Observations not tied to specific code lines
TEMPLATE
        ;;
      peer-review)
        cat <<'TEMPLATE'
# Review State — PR #{PR_NUMBER}

## Metadata
- Identifier: PR #{PR_NUMBER}
- Branch: {branch name from PR}
- Reviews: {count} (last: YYYY-MM-DD)
- Types: review, peer-review

## Decisions
- `file:line` — Description of decision (peer-review-N)

## Coverage
- Files analyzed: file1, file2, ...
- Key methods: Class::method(), ...

## Open Items
- [ ] `file:line` — Description (raised peer-review-N, still open peer-review-M)

## Resolved Items
- [x] `file:line` — Description (raised peer-review-N, resolved peer-review-M)

## Notes
- Observations not tied to specific code lines
TEMPLATE
        ;;
      *)
        echo "Unknown type: $TYPE (valid: review, review-local, peer-review)" >&2
        exit 1
        ;;
    esac
    ;;

  pr-number)
    ARG="${1:?Usage: memory-manager.sh pr-number <argument>}"
    if ! pr_number "$ARG"; then
      echo "No PR number in '$ARG' (expected 184, #184 or a pull URL)" >&2
      exit 1
    fi
    ;;

  help|*)
    cat <<EOF
DTK Review Memory Manager

Usage: bash memory-manager.sh <action> [options]

Actions:
  init <review-id>                     Initialize memory dir, return state info as JSON
  next-number <review-id> <prefix>     Get next sequential number for review files
  save-state <review-id>               Save review state (reads content from stdin)
  template <review-id> <type>          Output save-state template (review|review-local|peer-review)
  pr-number <argument>                 Print the PR number in 184, #184 or a pull URL

A review-id of PR-#123 or PR-<pull URL> is stored as PR-123.

Examples:
  bash memory-manager.sh init "feature/login"
  bash memory-manager.sh init "PR-123"
  bash memory-manager.sh next-number "PR-123" "peer-review"
  echo "# State..." | bash memory-manager.sh save-state "PR-123"
  bash memory-manager.sh template "PR-123" "review"
  bash memory-manager.sh pr-number "#123"
EOF
    ;;
esac
