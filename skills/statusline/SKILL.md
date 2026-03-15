---
name: statusline
description: "Use when the user wants to enable or configure the DTK visual statusline with progress bar, git info, cost, and duration."
---

# /dtk:statusline — Enable Visual Statusline

## Steps

1. Determine the plugin root path by running:

```bash
echo "${CLAUDE_PLUGIN_ROOT:-not set}"
```

If `CLAUDE_PLUGIN_ROOT` is not set, find it:

```bash
find ~/.claude/plugins -path "*/dtk/scripts/statusline.sh" 2>/dev/null | head -1 | sed 's|/scripts/statusline.sh||'
```

2. Write the statusline config to the user's settings file at `~/.claude/settings.json`. Read the existing file first, then add/update only the `statusLine` key:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash {PLUGIN_PATH}/scripts/statusline.sh"
  }
}
```

Replace `{PLUGIN_PATH}` with the actual path found in step 1.

**Important:** Merge with existing settings — do NOT overwrite other keys.

3. Tell the user:
   - The statusline has been configured
   - They need to **restart the Claude Code session** for it to take effect
   - To disable later, remove the `statusLine` key from `~/.claude/settings.json`
