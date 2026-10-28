#!/bin/bash
#
# Creates a new lesson file in docs/lessons/{category}/NNN-slug.md
# and updates docs/lessons/index.md with the new entry.
#
# Usage:
#   echo "<lesson content>" | bash bin/skill-scripts/lessons/create-lesson.sh \
#     --category security --title "SQL Injection in DB Raw" --severity Critical --source own
#
# Options:
#   --category   One of: security, code-patterns, qa, performance, framework, testing, frontend
#   --title      Short descriptive title for the lesson
#   --severity   One of: Critical, High, Medium, Low
#   --source     own (default) | peer. Where the lesson came from: the user's own review
#                (review / review-local) or a review of a teammate's PR (review-peer).
#                Sets the lifecycle status in the frontmatter: own → active, peer → candidate.
#   --check-dup  If set, searches existing lessons for similar title (prints match and exits 1)
#
# Each file opens with a frontmatter block (status: candidate | active | retired,
# source: own | peer) followed by the lesson body. Content piped in that already
# opens with `---` is written as-is.
#
# Output: path to the created file (or duplicate match if --check-dup finds one)

set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
LESSONS_DIR="${PROJECT_ROOT}/docs/lessons"

CATEGORY=""
TITLE=""
SEVERITY=""
SOURCE="own"
CHECK_DUP=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --category) CATEGORY="$2"; shift 2 ;;
    --title) TITLE="$2"; shift 2 ;;
    --severity) SEVERITY="$2"; shift 2 ;;
    --source) SOURCE="$2"; shift 2 ;;
    --check-dup) CHECK_DUP=true; shift ;;
    *) shift ;;
  esac
done

# Validate inputs
VALID_CATEGORIES="security code-patterns qa performance framework testing frontend"
if [[ -z "$CATEGORY" ]] || ! echo "$VALID_CATEGORIES" | grep -qw "$CATEGORY"; then
  echo "Error: --category must be one of: $VALID_CATEGORIES" >&2
  exit 1
fi

if [[ -z "$TITLE" ]]; then
  echo "Error: --title is required" >&2
  exit 1
fi

if [[ -z "$SEVERITY" ]]; then
  echo "Error: --severity is required (Critical, High, Medium, Low)" >&2
  exit 1
fi

case "$SOURCE" in
  own) STATUS="active" ;;
  peer) STATUS="candidate" ;;
  *) echo "Error: --source must be own or peer" >&2; exit 1 ;;
esac

# Generate slug from title
SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//')

CATEGORY_DIR="${LESSONS_DIR}/${CATEGORY}"

# Ensure directory exists
mkdir -p "$CATEGORY_DIR"

# Check for duplicates
if [[ "$CHECK_DUP" = true ]]; then
  for existing in "${CATEGORY_DIR}"/*.md; do
    [[ -f "$existing" ]] || continue
    [[ "$(basename "$existing")" == "index.md" ]] && continue

    # Check title similarity (case-insensitive first-line match)
    # Title = first `### ` heading, so a leading frontmatter block is skipped
    EXISTING_TITLE=$(grep -m1 '^### ' "$existing" | sed 's/^### //' || true)
    if echo "$EXISTING_TITLE" | grep -qi "$(echo "$TITLE" | sed 's/[^a-zA-Z0-9 ]//g')"; then
      echo "DUPLICATE:${existing}"
      exit 1
    fi
  done
  echo "NO_DUPLICATE"
  exit 0
fi

# Determine next number
LAST=$(find "$CATEGORY_DIR" -maxdepth 1 -name "*.md" ! -name "index.md" 2>/dev/null | \
  grep -oP '\d{3}' | sort -n | tail -1 || echo "000")
NEXT=$(printf "%03d" $((10#${LAST:-0} + 1)))

# Create lesson file
LESSON_FILE="${CATEGORY_DIR}/${NEXT}-${SLUG}.md"
CONTENT=$(cat)
if [[ "$CONTENT" == ---* ]]; then
  printf '%s\n' "$CONTENT" > "$LESSON_FILE"
else
  printf -- '---\nstatus: %s\nsource: %s\n---\n%s\n' "$STATUS" "$SOURCE" "$CONTENT" > "$LESSON_FILE"
fi

# Update index.md
INDEX_FILE="${LESSONS_DIR}/index.md"
if [[ -f "$INDEX_FILE" ]]; then
  # Find the correct category section and add entry after the table header
  # Category mapping for section headers
  case "$CATEGORY" in
    security) SECTION="Security" ;;
    code-patterns) SECTION="Code Patterns" ;;
    qa) SECTION="QA" ;;
    performance) SECTION="Performance" ;;
    framework) SECTION="Framework" ;;
    testing) SECTION="Testing" ;;
    frontend) SECTION="Frontend" ;;
  esac

  # Insert new row after the |---|...| line under the matching ## section
  # Use awk to find the section, then the table separator, then insert
  RELATIVE_PATH="${CATEGORY}/${NEXT}-${SLUG}.md"
  NEW_ROW="| ${NEXT} | [${TITLE}](${RELATIVE_PATH}) | ${SEVERITY} |"

  awk -v section="## $SECTION" -v row="$NEW_ROW" '
    $0 == section { in_section=1; print; next }
    in_section && /^\|---/ { print; print row; in_section=0; next }
    { print }
  ' "$INDEX_FILE" > "${INDEX_FILE}.tmp" && mv "${INDEX_FILE}.tmp" "$INDEX_FILE"
fi

echo "$LESSON_FILE"
