# Script resolution

Every dtk script lives under the plugin's top-level `scripts/` folder, grouped by domain
(`scripts/review/`, `scripts/dsqa/`, `scripts/gh-action/`, …). Skills never ship their own
`scripts/` folder, and the plugin has no top-level `bin/` (claude.ai and Cowork refuse a
plugin that has one).

## The idiom

A skill that runs a script resolves the folder with this one line, pasted verbatim, in the
block that runs its first script (the "Step 0: Resolve Scripts" block when the skill has one):

```bash
SCRIPTS="${CLAUDE_PLUGIN_ROOT}/scripts"; [ -d "$SCRIPTS" ] || echo "dtk: scripts dir not found: $SCRIPTS" >&2; echo "$SCRIPTS"
```

followed by:

> Use the output path as `$SCRIPTS` for all script commands below.

Later commands call `"$SCRIPTS/<domain>/<script>"`. Shell state does not carry between Bash
calls, so the printed absolute path is what later calls reuse.

## Why it works

Claude Code fills in plugin variables in a plugin skill's text before the model reads it: every
exact `${CLAUDE_PLUGIN_ROOT}` token becomes the plugin's absolute path. This happens for an
installed plugin (`~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`) and for one loaded
with `claude --plugin-dir <path>`, so the line above reaches the shell as a literal path:

```bash
SCRIPTS="/home/me/.claude/plugins/cache/dtk-marketplace/dtk/1.15.0/scripts"; …
```

The substitution matches only the exact token. Two consequences:

- Never write `${CLAUDE_PLUGIN_ROOT:-…}` or `${CLAUDE_PLUGIN_ROOT:-}` in a skill. The text
  substitution skips that form, and Claude Code does not export `CLAUDE_PLUGIN_ROOT` to the
  Bash tool (only to hooks and MCP servers), so it expands to the fallback.
- If the token was not filled in (the SKILL.md was read as a plain file, outside the plugin
  loader), `$SCRIPTS` becomes `/scripts`, the guard prints `dtk: scripts dir not found` on
  stderr, and the skill should stop rather than guess. Exporting `CLAUDE_PLUGIN_ROOT` by hand
  makes the same line work in a plain shell (that is how it is tested below).

`${CLAUDE_SKILL_DIR}` is filled in the same way and stays fine for a skill's own
`references/` and `templates/`. It is not used for scripts.

## Not allowed

- `find ~/.claude/plugins … -maxdepth N` searches: slow, and they pick an arbitrary version.
- Hard-coded `~/.claude/plugins/cache/...` paths: they break under `--plugin-dir` and pick a
  stale version.
- Bare relative paths such as `scripts/foo.sh`: they resolve against the user's project, not
  the plugin.

## Checks

```bash
# no other idiom left
grep -rn 'maxdepth\|plugins/cache\|\bbin/skill-scripts' skills/*/SKILL.md      # empty
# every scripts/ path a skill names exists
grep -oh 'scripts/[A-Za-z0-9_./-]*' skills/*/SKILL.md | sort -u | while read p; do test -e "$p" || echo MISSING $p; done
# the line works from any cwd once the token is filled in
cd /tmp && CLAUDE_PLUGIN_ROOT=<plugin dir> bash -c 'SCRIPTS="${CLAUDE_PLUGIN_ROOT}/scripts"; [ -d "$SCRIPTS" ] || echo "dtk: scripts dir not found: $SCRIPTS" >&2; echo "$SCRIPTS"'
```
