#!/bin/bash
# DTK — Lessons Loader
# Discovers and lists lesson files from the project's knowledge base.
# Usage: bash lessons-loader.sh [--category security] [--list] [--content]
#
# Searches in order:
#   1. docs/lessons/ (dtk standard — version-controlled)
#   2. .claude/projects/*/memory/lessons-*.md (Claude auto-memory fallback)

set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
CATEGORY=""
MODE="list"  # list | content | json

while [[ $# -gt 0 ]]; do
  case $1 in
    --category) CATEGORY="$2"; shift 2 ;;
    --list) MODE="list"; shift ;;
    --content) MODE="content"; shift ;;
    --json) MODE="json"; shift ;;
    *) shift ;;
  esac
done

DOCS_LESSONS="${PROJECT_ROOT}/docs/lessons"
FOUND_FILES=()

# Strategy 1: docs/lessons/ (preferred)
if [[ -d "$DOCS_LESSONS" ]]; then
  if [[ -n "$CATEGORY" ]]; then
    while IFS= read -r file; do
      FOUND_FILES+=("$file")
    done < <(find "${DOCS_LESSONS}/${CATEGORY}" -name "*.md" ! -name "index.md" 2>/dev/null | sort)
  else
    while IFS= read -r file; do
      FOUND_FILES+=("$file")
    done < <(find "$DOCS_LESSONS" -name "*.md" ! -name "index.md" 2>/dev/null | sort)
  fi
fi

# Strategy 2: Claude auto-memory fallback
if [[ ${#FOUND_FILES[@]} -eq 0 ]]; then
  # Derive the project path key Claude uses
  PROJECT_KEY=$(echo "$PROJECT_ROOT" | sed 's|/|-|g; s|^-||')
  CLAUDE_MEMORY_DIR="$HOME/.claude/projects/${PROJECT_KEY}/memory"

  if [[ -d "$CLAUDE_MEMORY_DIR" ]]; then
    if [[ -n "$CATEGORY" ]]; then
      while IFS= read -r file; do
        FOUND_FILES+=("$file")
      done < <(find "$CLAUDE_MEMORY_DIR" -name "lessons-${CATEGORY}*.md" 2>/dev/null | sort)
    else
      while IFS= read -r file; do
        FOUND_FILES+=("$file")
      done < <(find "$CLAUDE_MEMORY_DIR" -name "lessons-*.md" 2>/dev/null | sort)
    fi
  fi
fi

case "$MODE" in
  list)
    if [[ ${#FOUND_FILES[@]} -eq 0 ]]; then
      echo "No lessons found."
      exit 0
    fi
    for f in "${FOUND_FILES[@]}"; do
      echo "$f"
    done
    ;;

  content)
    if [[ ${#FOUND_FILES[@]} -eq 0 ]]; then
      echo "No lessons found."
      exit 0
    fi
    for f in "${FOUND_FILES[@]}"; do
      echo "=== $(basename "$f") ==="
      cat "$f"
      echo ""
    done
    ;;

  json)
    echo "{"
    echo "  \"source\": \"$([ -d "$DOCS_LESSONS" ] && echo "docs/lessons" || echo "claude-auto-memory")\","
    echo "  \"count\": ${#FOUND_FILES[@]},"
    echo "  \"categories\": ["

    # List unique categories
    CATEGORIES=()
    for f in "${FOUND_FILES[@]}"; do
      dir=$(dirname "$f")
      cat_name=$(basename "$dir")
      if [[ ! " ${CATEGORIES[*]:-} " =~ " ${cat_name} " ]]; then
        CATEGORIES+=("$cat_name")
      fi
    done

    FIRST=true
    for cat in "${CATEGORIES[@]}"; do
      $FIRST || echo ","
      FIRST=false
      COUNT=$(printf '%s\n' "${FOUND_FILES[@]}" | grep "/${cat}/" | wc -l)
      printf '    {"name": "%s", "count": %d}' "$cat" "$COUNT"
    done
    echo ""
    echo "  ],"

    echo "  \"files\": ["
    FIRST=true
    for f in "${FOUND_FILES[@]}"; do
      $FIRST || echo ","
      FIRST=false
      printf '    "%s"' "$f"
    done
    echo ""
    echo "  ]"
    echo "}"
    ;;
esac
