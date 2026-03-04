---
name: bootstrap
description: "Verify project structure and fetch remote resources — creates docs/ knowledge base, .claude/ tool config, and CLAUDE.md. Idempotent and safe to run multiple times. Use when setting up a new project or verifying an existing one."
---

# /bootstrap — Verify Structure & Fetch Remote Resources

You are a project bootstrap assistant. Your job is to:

1. Read the project's resource manifest (`.claude/resources.json`) if it exists
2. Fetch resources from remote repositories as declared
3. Verify the complete project structure exists exactly as required
4. Create anything that's missing
5. Never overwrite files that already have content

**Key principle:** Project knowledge (ADRs, lessons, PRDs) lives in `docs/` — it belongs to the project and survives any tool. Tool configuration (commands, settings) lives in `.claude/` — it's disposable and can be rebuilt from remote resources.

This command is **idempotent** and **safe to run multiple times**.

---

## Step 0: Pre-Flight Checks

```bash
git rev-parse --is-inside-work-tree 2>/dev/null || echo "NOT_A_GIT_REPO"
REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
basename $(pwd)
```

Extract `GIT_OWNER` and `GIT_REPO`. If no remote, **ask the user**.

---

## Step 1: Check for Resource Manifest

```bash
cat .claude/resources.json 2>/dev/null || echo "NO_MANIFEST"
```

- **Manifest exists** → Step 2 (fetch remote resources)
- **No manifest** → Skip to Step 3 (use embedded defaults)

Ask the user:

> "No resource manifest found. Would you like me to create one? I'll need your Claude resources repo (e.g., `your-user/claude-resources`). Or I can proceed with embedded defaults."

### Step 1b: Create Initial Manifest (if user provides a repo)

```json
{
  "version": "1.0",
  "sources": {
    "core": {
      "repo": "{{USER_RESOURCES_REPO}}",
      "ref": "main",
      "private": true,
      "description": "Personal Claude Code resources"
    }
  },
  "install": {
    "commands": ["core:commands/*"],
    "memories": ["core:MEMORY.md"],
    "skills": ["core:skills/*"]
  },
  "stack_overrides": {},
  "overrides": {
    "GIT_OWNER": "auto",
    "GIT_REPO": "auto"
  }
}
```

---

## Step 2: Fetch Remote Resources

### 2.1 — Parse Manifest

Extract sources, install targets, stack_overrides, overrides.

### 2.2 — Clone/Update Sources

```bash
CACHE_DIR="/tmp/claude-resources-cache"
mkdir -p "$CACHE_DIR"

SOURCE_DIR="$CACHE_DIR/{source_name}"
if [ -d "$SOURCE_DIR/.git" ]; then
  cd "$SOURCE_DIR" && git fetch origin && git checkout {ref} && git pull origin {ref} 2>/dev/null; cd -
else
  git clone --depth 1 --branch {ref} "https://github.com/{repo}.git" "$SOURCE_DIR" 2>/dev/null
fi
```

**Error handling:** Never block — fall back to embedded templates if any source fails.

### 2.3 — Install Resources

Format: `{source_name}:{path}` — supports wildcards (`core:commands/*`).

**Installation mapping:**

| Resource type | Source path | Destination |
|---|---|---|
| commands | `commands/{file}.md` | `.claude/commands/{file}.md` |
| memories | `memories/MEMORY.md` | `.claude/MEMORY.md` |
| skills | `skills/{dir}/` | `.claude/skills/{dir}/` |
| hooks | `hooks/{file}.md` | `.claude/hooks/{file}.md` |
| settings | `settings.local.json` | `.claude/settings.local.json` |
| docs templates | `docs-templates/` | `docs/` (structure only — never overwrite content) |

**Conflict rules:** Existing file with content → **never overwrite** → report "skipped".

### 2.4 — Apply Stack Overrides

Stack-specific resources override base ones (respecting conflict rules).

### 2.5 — Replace Placeholders

On **newly created files only**: `{{GIT_OWNER}}`, `{{GIT_REPO}}`, `{{STACK}}`, `{{DATE}}`.

---

## Step 3: Verify Full Structure

### 3.1 — Project Knowledge (`docs/`) — PERMANENT

```bash
mkdir -p \
  docs/adrs \
  docs/lessons/security \
  docs/lessons/code-patterns \
  docs/lessons/qa \
  docs/lessons/performance \
  docs/lessons/framework \
  docs/lessons/testing \
  docs/lessons/frontend \
  docs/prds
```

### 3.2 — Tool Configuration (`.claude/`) — REBUILDABLE

```bash
mkdir -p .claude/commands .claude/skills .claude/plans
```

### 3.3 — `.gitignore` Entry

```bash
grep -q "settings.local.json" .gitignore 2>/dev/null || echo -e "\n# Claude Code local settings\n.claude/settings.local.json" >> .gitignore
```

---

## Step 4: Final Validation

```bash
echo "=== Structure Validation ==="

echo ""
echo "📂 Project Knowledge (docs/) — permanent, version-controlled:"
for dir in docs docs/adrs docs/lessons docs/prds; do
  [ -d "$dir" ] && echo "  ✅ $dir/" || echo "  ❌ $dir/"
done

echo ""
echo "🔧 Tool Config (.claude/) — rebuildable from resources:"
for dir in .claude .claude/commands .claude/skills .claude/plans; do
  [ -d "$dir" ] && echo "  ✅ $dir/" || echo "  ❌ $dir/"
done

echo ""
echo "📋 Commands:"
for cmd in review commit learn adr prd init bootstrap; do
  [ -f ".claude/commands/$cmd.md" ] && echo "  ✅ /$cmd" || echo "  ❌ /$cmd MISSING"
done
```

---

## Step 5: Output Report

```
## ✅ Bootstrap Complete: {GIT_OWNER}/{GIT_REPO}

### Mode: Remote (manifest) | Local (embedded defaults)

### Structure Status

| Layer | Purpose | Total | Existed | Created |
|-------|---------|-------|---------|---------|
| `docs/` | Project knowledge (permanent) | 12 | ... | ... |
| `.claude/` | Tool config (rebuildable) | 12 | ... | ... |
| Root | Project root files | 1 | ... | ... |

### Next Steps
- Review `.claude/resources.json` to add/remove resource sources
- All knowledge in `docs/` is version-controlled — commit it!
```

After outputting this report, immediately run `/init` to detect the project stack and adapt all configuration files.

---

## Rules

- **NEVER overwrite** a file that has content — only fill gaps
- **NEVER delete** any file or directory
- **Idempotent** — running 10 times = same result as 1 time
- **Remote-first** — prefer remote resources over embedded fallbacks
- **Graceful degradation** — if remote fails, fall back without blocking
- **Placeholder replacement** only on **newly created** files
- **Ask, don't guess** — if git remote missing, ask user
- **Knowledge in `docs/`** — always permanent, always committed to git
- **Config in `.claude/`** — always rebuildable from remote resources
- Write everything in **English**
- After bootstrap, remind to run `/init`
