#!/bin/bash

# DTK Statusline — Shows model, tokens, context usage, cache, git status, and agent info

# Read JSON input from stdin
input=$(cat)

# Extract all the values we need
model_display_name=$(echo "$input" | jq -r '.model.display_name // "N/A"')
model_id=$(echo "$input" | jq -r '.model.id // "N/A"')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // "N/A"')
project_dir=$(echo "$input" | jq -r '.workspace.project_dir // "N/A"')
output_style=$(echo "$input" | jq -r '.output_style.name // "default"')
agent_name=$(echo "$input" | jq -r '.agent.name // empty')
agent_type=$(echo "$input" | jq -r '.agent.type // empty')

# Token usage information
total_input=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
total_output=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
context_size=$(echo "$input" | jq -r '.context_window.context_window_size // 0')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
remaining_pct=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')

# Current usage (from last API call)
cache_creation=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
cache_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')

# Git information (skip locks for performance)
git_branch=""
git_status=""
git_ahead_behind=""

if git rev-parse --git-dir > /dev/null 2>&1; then
    git_branch=$(echo "$input" | jq -r '.git.branch // empty')
    if [ -z "$git_branch" ]; then
        git_branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || echo "detached")
    fi

    git --no-optional-locks diff-index --quiet HEAD -- 2>/dev/null
    if [ $? -eq 0 ]; then
        git_status="clean"
    else
        git_status="dirty"
    fi

    upstream=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)
    if [ -n "$upstream" ]; then
        ahead=$(git rev-list --count HEAD ^"$upstream" 2>/dev/null || echo "0")
        behind=$(git rev-list --count "$upstream" ^HEAD 2>/dev/null || echo "0")

        if [ "$ahead" != "0" ] || [ "$behind" != "0" ]; then
            git_ahead_behind=" ↑$ahead ↓$behind"
        fi
    fi
fi

# Color codes
RESET=$'\033[0m'
CYAN=$'\033[36m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
BLUE=$'\033[34m'
MAGENTA=$'\033[35m'
RED=$'\033[31m'
BOLD=$'\033[1m'
DIM=$'\033[2m'

# Line 1: Model and tokens
line1="${CYAN}${BOLD}${model_display_name}${RESET}${DIM} (${model_id})${RESET}"
line1+=" ${DIM}|${RESET} "
line1+="${GREEN}Tokens:${RESET} ${total_input}in/${total_output}out"
line1+=" ${DIM}|${RESET} "
line1+="${BLUE}Context:${RESET} ${context_size}"

if [ -n "$used_pct" ] && [ "$used_pct" != "null" ]; then
    if [ "$used_pct" -gt 80 ] 2>/dev/null; then
        pct_color="${RED}"
    elif [ "$used_pct" -gt 50 ] 2>/dev/null; then
        pct_color="${YELLOW}"
    else
        pct_color="${GREEN}"
    fi
    line1+=" (${pct_color}${used_pct}%${RESET} used"
    if [ -n "$remaining_pct" ] && [ "$remaining_pct" != "null" ]; then
        line1+=", ${remaining_pct}% left"
    fi
    line1+=")"
fi

echo "$line1"

# Line 2: Cache information and directories
line2=""
if [ "$cache_creation" != "0" ] || [ "$cache_read" != "0" ]; then
    line2+="${MAGENTA}Cache:${RESET} "
    if [ "$cache_creation" != "0" ]; then
        line2+="${cache_creation} created "
    fi
    if [ "$cache_read" != "0" ]; then
        line2+="${cache_read} read"
    fi
    line2+=" ${DIM}|${RESET} "
fi

line2+="${BLUE}CWD:${RESET} ${cwd}"
if [ "$cwd" != "$project_dir" ]; then
    line2+=" ${DIM}|${RESET} ${BLUE}Project:${RESET} ${project_dir}"
fi

echo "$line2"

# Line 3: Git, output style, and agent info
line3=""
if [ -n "$git_branch" ]; then
    if [ "$git_status" = "clean" ]; then
        status_color="${GREEN}"
    else
        status_color="${YELLOW}"
    fi
    line3+="${MAGENTA}Git:${RESET} ${status_color}${git_branch}${RESET} [${git_status}]${git_ahead_behind}"
    line3+=" ${DIM}|${RESET} "
fi

line3+="${CYAN}Style:${RESET} ${output_style}"

if [ -n "$agent_name" ]; then
    line3+=" ${DIM}|${RESET} "
    line3+="${YELLOW}Agent:${RESET} ${agent_name}"
    if [ -n "$agent_type" ]; then
        line3+="${DIM} (${agent_type})${RESET}"
    fi
fi

echo "$line3"
