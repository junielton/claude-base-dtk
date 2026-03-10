#!/bin/bash

# DTK Statusline — Visual progress bar, model, git, cost, duration, clickable repo link
# Receives JSON session data on stdin from Claude Code

input=$(cat)

# ─── Extract fields ───────────────────────────────────────────────────────────
model=$(echo "$input" | jq -r '.model.display_name // "N/A"')
model_id=$(echo "$input" | jq -r '.model.id // "N/A"')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // "N/A"')
dir_name="${cwd##*/}"
output_style=$(echo "$input" | jq -r '.output_style.name // "default"')
agent_name=$(echo "$input" | jq -r '.agent.name // empty')
version=$(echo "$input" | jq -r '.version // empty')

# Context window
pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // 100' | cut -d. -f1)
total_in=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
total_out=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')

# Cost & duration
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
lines_added=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
lines_removed=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')

# Cache
cache_creation=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
cache_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')

# ─── Colors ───────────────────────────────────────────────────────────────────
RESET=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
CYAN=$'\033[36m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
MAGENTA=$'\033[35m'
BLUE=$'\033[34m'
WHITE=$'\033[37m'
BG_GREEN=$'\033[42m'
BG_YELLOW=$'\033[43m'
BG_RED=$'\033[41m'

# ─── Helpers ──────────────────────────────────────────────────────────────────

format_tokens() {
    local n=$1
    if [ "$n" -ge 1000000 ] 2>/dev/null; then
        printf "%.1fM" "$(echo "$n / 1000000" | bc -l)"
    elif [ "$n" -ge 1000 ] 2>/dev/null; then
        printf "%.1fk" "$(echo "$n / 1000" | bc -l)"
    else
        echo "$n"
    fi
}

format_duration() {
    local ms=$1
    local secs=$((ms / 1000))
    local mins=$((secs / 60))
    local hrs=$((mins / 60))
    if [ "$hrs" -gt 0 ]; then
        printf "%dh%02dm" "$hrs" "$((mins % 60))"
    elif [ "$mins" -gt 0 ]; then
        printf "%dm%02ds" "$mins" "$((secs % 60))"
    else
        printf "%ds" "$secs"
    fi
}

# ─── Progress bar ─────────────────────────────────────────────────────────────
BAR_WIDTH=20
filled=$((pct * BAR_WIDTH / 100))
empty=$((BAR_WIDTH - filled))

# Color based on usage
if [ "$pct" -ge 90 ] 2>/dev/null; then
    bar_color="${RED}"
    pct_color="${RED}${BOLD}"
elif [ "$pct" -ge 70 ] 2>/dev/null; then
    bar_color="${YELLOW}"
    pct_color="${YELLOW}"
else
    bar_color="${GREEN}"
    pct_color="${GREEN}"
fi

bar=""
for ((i=0; i<filled; i++)); do bar+="━"; done
for ((i=0; i<empty; i++)); do bar+="╌"; done

# ─── Git info (cached for performance) ───────────────────────────────────────
CACHE_FILE="/tmp/dtk-statusline-git-cache"
CACHE_MAX_AGE=5

cache_is_stale() {
    [ ! -f "$CACHE_FILE" ] || \
    [ $(($(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0))) -gt $CACHE_MAX_AGE ]
}

git_branch=""
git_dirty=""
git_ahead=""
git_behind=""
git_remote=""

if git rev-parse --git-dir > /dev/null 2>&1; then
    if cache_is_stale; then
        branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || echo "detached")

        git --no-optional-locks diff-index --quiet HEAD -- 2>/dev/null
        dirty=$?

        upstream=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)
        ahead=0; behind=0
        if [ -n "$upstream" ]; then
            ahead=$(git rev-list --count HEAD ^"$upstream" 2>/dev/null || echo "0")
            behind=$(git rev-list --count "$upstream" ^HEAD 2>/dev/null || echo "0")
        fi

        remote=$(git remote get-url origin 2>/dev/null | sed 's/git@github\.com:/https:\/\/github.com\//' | sed 's/\.git$//')

        echo "${branch}|${dirty}|${ahead}|${behind}|${remote}" > "$CACHE_FILE"
    fi

    IFS='|' read -r git_branch git_dirty git_ahead git_behind git_remote < "$CACHE_FILE"
fi

# ─── Line 1: Model + Context Progress Bar ────────────────────────────────────
tokens_in=$(format_tokens "$total_in")
tokens_out=$(format_tokens "$total_out")

line1="${CYAN}${BOLD}${model}${RESET}"
line1+=" ${DIM}${model_id}${RESET}"
line1+="  ${bar_color}${bar}${RESET} ${pct_color}${pct}%${RESET}"
line1+="  ${DIM}${tokens_in}↓ ${tokens_out}↑${RESET}"

# Cache info
if [ "$cache_creation" != "0" ] || [ "$cache_read" != "0" ]; then
    c_create=$(format_tokens "$cache_creation")
    c_read=$(format_tokens "$cache_read")
    line1+="  ${MAGENTA}⚡${c_read}${RESET}"
fi

printf '%b\n' "$line1"

# ─── Line 2: Git + Cost + Duration ───────────────────────────────────────────
line2=""

# Git branch with status
if [ -n "$git_branch" ]; then
    if [ "$git_dirty" = "0" ]; then
        line2+="${GREEN}●${RESET} "
    else
        line2+="${YELLOW}●${RESET} "
    fi

    # Clickable repo link (OSC 8)
    if [ -n "$git_remote" ]; then
        line2+=$(printf '%b' "\033]8;;${git_remote}\a${BOLD}${git_branch}${RESET}\033]8;;\a")
    else
        line2+="${BOLD}${git_branch}${RESET}"
    fi

    # Ahead/behind
    if [ "$git_ahead" != "0" ] 2>/dev/null; then
        line2+=" ${GREEN}↑${git_ahead}${RESET}"
    fi
    if [ "$git_behind" != "0" ] 2>/dev/null; then
        line2+=" ${RED}↓${git_behind}${RESET}"
    fi

    line2+="  ${DIM}│${RESET}  "
fi

# Cost
cost_fmt=$(printf '$%.2f' "$cost")
line2+="${YELLOW}${cost_fmt}${RESET}"

# Duration
duration_fmt=$(format_duration "$duration_ms")
line2+="  ${DIM}│${RESET}  ${BLUE}${duration_fmt}${RESET}"

# Lines changed
if [ "$lines_added" != "0" ] || [ "$lines_removed" != "0" ]; then
    line2+="  ${DIM}│${RESET}  ${GREEN}+${lines_added}${RESET} ${RED}-${lines_removed}${RESET}"
fi

# Agent
if [ -n "$agent_name" ]; then
    line2+="  ${DIM}│${RESET}  ${MAGENTA}⚙ ${agent_name}${RESET}"
fi

# Directory
line2+="  ${DIM}│${RESET}  ${DIM}${dir_name}${RESET}"

printf '%b\n' "$line2"
