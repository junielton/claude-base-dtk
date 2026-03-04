---
name: update
description: "Update the DTK plugin to the latest version — pulls latest changes from the remote repo and reinstalls the plugin."
---

# /dtk:update — Update DTK Plugin

You are updating the DTK plugin to the latest version.

## Steps

1. Pull latest changes from the marketplace clone:

```bash
cd ~/.claude/plugins/marketplaces/dtk-marketplace && git pull origin main 2>&1
```

2. Clear the plugin cache:

```bash
rm -rf ~/.claude/plugins/cache/dtk-marketplace
```

3. Reinstall the plugin:

```bash
claude plugin install dtk@dtk-marketplace
```

4. Show the user what version was installed:

```bash
cat ~/.claude/plugins/marketplaces/dtk-marketplace/.claude-plugin/plugin.json | jq -r '.version'
```

5. Tell the user:
   - Which version was installed
   - They need to **restart the Claude Code session** for the changes to take effect
