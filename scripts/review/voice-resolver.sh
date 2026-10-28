#!/bin/bash
#
# Finds the user's writing-voice skill for /dtk:review-publish.
# Resolution order: dtk.local.md setting, SKILL.md marker (voice: true), name/description heuristic.
# Outputs JSON: voice_skill (invoke name or ""), source (setting|marker|heuristic|none), candidates[].
#
# Usage:
#   bash scripts/review/voice-resolver.sh

set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

frontmatter() {
  sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$1" 2>/dev/null || true
}

field() {
  echo "$1" | grep -E "^${2}:" | head -1 | sed -E "s/^${2}: *//; s/^[\"']//; s/[\"']\$//"
}

invoke_name() {
  local dir="$1" name
  name=$(basename "$dir")
  case "$dir" in
    "$HOME"/.claude/plugins/cache/*/skills/*)
      local plugin
      plugin=$(echo "$dir" | sed -E 's#.*/plugins/cache/[^/]+/([^/]+)/[^/]+/skills/.*#\1#')
      echo "${plugin}:${name}"
      ;;
    *) echo "$name" ;;
  esac
}

emit() {
  local skill="$1" source="$2"; shift 2
  local list=""
  for c in "$@"; do list="${list:+$list, }\"$c\""; done
  local invoke=""
  [[ -n "$skill" ]] && invoke="Skill(skill=\\\"${skill}\\\")"
  printf '{\n  "voice_skill": "%s",\n  "source": "%s",\n  "candidates": [%s],\n  "invoke": "%s"\n}\n' "$skill" "$source" "$list" "$invoke"
}

for settings in "$PROJECT_ROOT/.claude/dtk.local.md" "$HOME/.claude/dtk.local.md"; do
  [[ -f "$settings" ]] || continue
  configured=$(field "$(frontmatter "$settings")" "voice_skill")
  if [[ -n "$configured" ]]; then
    emit "$configured" "setting" "$configured"
    exit 0
  fi
done

skill_files=()
while IFS= read -r f; do skill_files+=("$f"); done < <(
  {
    ls "$PROJECT_ROOT"/.claude/skills/*/SKILL.md 2>/dev/null || true
    ls "$HOME"/.claude/skills/*/SKILL.md 2>/dev/null || true
    ls "$HOME"/.claude/plugins/cache/*/*/*/skills/*/SKILL.md 2>/dev/null || true
  } | awk '!seen[$0]++'
)

marked=()
for f in "${skill_files[@]}"; do
  fm=$(frontmatter "$f")
  if echo "$fm" | grep -qE '^voice: *true|^ *role: *voice'; then
    marked+=("$(invoke_name "$(dirname "$f")")")
  fi
done

if [[ ${#marked[@]} -eq 1 ]]; then
  emit "${marked[0]}" "marker" "${marked[@]}"
  exit 0
elif [[ ${#marked[@]} -gt 1 ]]; then
  emit "" "marker" "${marked[@]}"
  exit 0
fi

guessed=()
for f in "${skill_files[@]}"; do
  dir=$(dirname "$f")
  name=$(basename "$dir")
  desc=$(field "$(frontmatter "$f")" "description")
  if echo "$desc" | grep -qiE 'speak|aloud|text-to-speech|\btts\b|dispatch|spawn|worktree|orchestrat'; then
    continue
  fi
  if echo "$name" | grep -qiE 'vox$|-vox|-voice$'; then
    guessed+=("$(invoke_name "$dir")")
  elif echo "$desc" | grep -qiE "personal voice|writing voice|sounds like|in (his|her|their|my|the user'?s) (own )?voice" && echo "$desc" | grep -qiE 'draft|repl(y|ies)|writ(e|ing)|message'; then
    guessed+=("$(invoke_name "$dir")")
  fi
done

if [[ ${#guessed[@]} -eq 1 ]]; then
  emit "${guessed[0]}" "heuristic" "${guessed[@]}"
elif [[ ${#guessed[@]} -gt 1 ]]; then
  emit "" "heuristic" "${guessed[@]}"
else
  emit "" "none"
fi
