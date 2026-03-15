---
name: bootstrap
description: "Use when setting up a new project or verifying an existing project's docs/, bin/skill-scripts/, and .claude/ structure. Idempotent and safe to run multiple times."
---

# /bootstrap — Project Structure Setup

Detect the project context, verify the complete structure exists, create anything missing, and never overwrite files that already have content.

**Key principle:** Project knowledge (ADRs, lessons, PRDs) lives in `docs/` — permanent, version-controlled. Skill scripts live in `bin/skill-scripts/` — project-local, version-controlled. Tool configuration lives in `.claude/` — disposable, can be rebuilt.

**Idempotent** — safe to run multiple times.

---

## Step 0: Pre-Flight Checks

```bash
git rev-parse --is-inside-work-tree 2>/dev/null || echo "NOT_A_GIT_REPO"
REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
basename $(pwd)
```

Extract `GIT_OWNER` and `GIT_REPO`. If no remote, **ask the user**.

---

## Step 1: Create Project Structure

### 1.1 — Project Knowledge (`docs/`) — PERMANENT

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
  docs/plans \
  docs/prds \
  memories/reviews
```

Create index files if they don't exist:

```bash
[ -f docs/adrs/index.md ] || cat > docs/adrs/index.md << 'EOF'
# Architecture Decision Records

Technical decisions, trade-offs, and architectural choices for this project.

| # | Decision | Weight | Status |
|---|----------|--------|--------|

<!-- New ADRs are added at the top (newest first) -->
<!-- Each ADR is a separate file: ADR-NNN-short-slug.md -->
EOF

[ -f docs/lessons/index.md ] || cat > docs/lessons/index.md << 'EOF'
# Lessons Learned

Actionable lessons extracted from code reviews, organized by category.

## QA

| # | Title | Severity |
|---|-------|----------|

## Performance

| # | Title | Severity |
|---|-------|----------|

## Security

| # | Title | Severity |
|---|-------|----------|

## Framework

| # | Title | Severity |
|---|-------|----------|

## Code Patterns

| # | Title | Severity |
|---|-------|----------|

## Testing

| # | Title | Severity |
|---|-------|----------|

## Frontend

| # | Title | Severity |
|---|-------|----------|
EOF
```

Create CLAUDE.md stub if it doesn't exist:

```bash
[ -f CLAUDE.md ] || cat > CLAUDE.md << 'EOF'
# Project Conventions

<!-- Add project-specific conventions and architectural guidelines here. -->

## Architecture

## Conventions

## Knowledge Base

Project knowledge is stored in `docs/` and loaded automatically by review and development skills:

- **Lessons Learned** — `docs/lessons/` (see [index](docs/lessons/index.md)) — actionable rules extracted from code reviews via `/dtk:learn-from-review`
- **Architecture Decision Records** — `docs/adrs/` (see [index](docs/adrs/index.md)) — significant technical decisions via `/dtk:adr`
- **Product Requirements** — `docs/prds/` — requirements documents via `/dtk:prd`

To load all lessons programmatically:
```sh
bash bin/skill-scripts/review/lessons-loader.sh --content
```
EOF
```

### 1.2 — Skill Scripts (`bin/skill-scripts/`) — VERSION-CONTROLLED

```bash
mkdir -p bin/skill-scripts/review bin/skill-scripts/dsqa bin/skill-scripts/adr bin/skill-scripts/commit bin/skill-scripts/shared bin/skill-scripts/lessons
```

Copy scripts from the plugin if they don't exist in the project:

```bash
if [[ -z "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
  CLAUDE_PLUGIN_ROOT=$(find ~/.claude/plugins -path "*/dtk/bin/skill-scripts" -maxdepth 4 2>/dev/null | head -1 | sed 's|/bin/skill-scripts||')
fi

PLUGIN_SCRIPTS="${CLAUDE_PLUGIN_ROOT}/bin/skill-scripts"

# Review scripts
for script in project-context.sh memory-manager.sh lessons-loader.sh; do
  [ -f "bin/skill-scripts/review/$script" ] || cp "$PLUGIN_SCRIPTS/review/$script" "bin/skill-scripts/review/$script"
done
chmod +x bin/skill-scripts/review/*.sh

# DSQA scripts
for script in capture-and-compare.mjs deep-inspect.mjs check-deps.sh; do
  [ -f "bin/skill-scripts/dsqa/$script" ] || cp "$PLUGIN_SCRIPTS/dsqa/$script" "bin/skill-scripts/dsqa/$script"
done
mkdir -p bin/skill-scripts/dsqa/utils
[ -f "bin/skill-scripts/dsqa/utils/color-utils.mjs" ] || cp "$PLUGIN_SCRIPTS/dsqa/utils/color-utils.mjs" "bin/skill-scripts/dsqa/utils/color-utils.mjs"
[ -f bin/skill-scripts/dsqa/check-deps.sh ] && chmod +x bin/skill-scripts/dsqa/check-deps.sh

# ADR scripts
for script in next-number.sh; do
  [ -f "bin/skill-scripts/adr/$script" ] || cp "$PLUGIN_SCRIPTS/adr/$script" "bin/skill-scripts/adr/$script"
done
chmod +x bin/skill-scripts/adr/*.sh

# Commit scripts
for script in gather-changes.sh; do
  [ -f "bin/skill-scripts/commit/$script" ] || cp "$PLUGIN_SCRIPTS/commit/$script" "bin/skill-scripts/commit/$script"
done
chmod +x bin/skill-scripts/commit/*.sh

# Shared scripts
for script in figma-url-parser.sh; do
  [ -f "bin/skill-scripts/shared/$script" ] || cp "$PLUGIN_SCRIPTS/shared/$script" "bin/skill-scripts/shared/$script"
done
chmod +x bin/skill-scripts/shared/*.sh

# Lessons scripts
for script in create-lesson.sh; do
  [ -f "bin/skill-scripts/lessons/$script" ] || cp "$PLUGIN_SCRIPTS/lessons/$script" "bin/skill-scripts/lessons/$script"
done
chmod +x bin/skill-scripts/lessons/*.sh
```

### 1.3 — Tool Configuration (`.claude/`)

```bash
mkdir -p .claude/skills .claude/plans
```

### 1.4 — `.gitignore` Entries

```bash
for entry in "settings.local.json" "memories/" "plans/"; do
  grep -q ".claude/$entry" .gitignore 2>/dev/null || echo -e "\n# Claude Code\n.claude/$entry" >> .gitignore
done

# Review memories at project root
grep -q "^memories/" .gitignore 2>/dev/null || echo -e "\n# Review memories\nmemories/" >> .gitignore
```

---

## Step 2: Detect Stack

Detect the project's tech stack by checking for known files:

| File | Stack |
|------|-------|
| `composer.json` | PHP / Laravel |
| `package.json` + `next.config.*` | Next.js |
| `package.json` + `nuxt.config.*` | Nuxt |
| `package.json` | Node.js |
| `requirements.txt` / `pyproject.toml` | Python |
| `Gemfile` | Ruby |
| `go.mod` | Go |
| `Cargo.toml` | Rust |

Report the detected stack. If multiple are found, list them.

---

## Step 3: Final Validation

```bash
echo "=== Structure Validation ==="

echo ""
echo "Project Knowledge (docs/) — permanent, version-controlled:"
for dir in docs docs/adrs docs/lessons docs/plans docs/prds; do
  [ -d "$dir" ] && echo "  ✅ $dir/" || echo "  ❌ $dir/"
done

echo ""
echo "Skill Scripts (bin/skill-scripts/):"
for dir in bin/skill-scripts bin/skill-scripts/review bin/skill-scripts/dsqa bin/skill-scripts/adr bin/skill-scripts/commit bin/skill-scripts/shared bin/skill-scripts/lessons; do
  [ -d "$dir" ] && echo "  ✅ $dir/" || echo "  ❌ $dir/"
done

echo ""
echo "Tool Config (.claude/):"
for dir in .claude .claude/skills .claude/plans; do
  [ -d "$dir" ] && echo "  ✅ $dir/" || echo "  ❌ $dir/"
done

echo ""
echo "Review Memory (memories/) — gitignored:"
for dir in memories memories/reviews; do
  [ -d "$dir" ] && echo "  ✅ $dir/" || echo "  ❌ $dir/"
done
```

---

## Step 4: Output Report

```
## ✅ Bootstrap Complete: {GIT_OWNER}/{GIT_REPO}

### Stack: {detected stack}

### Structure Status

| Layer | Purpose | Total | Existed | Created |
|-------|---------|-------|---------|---------|
| `docs/` | Project knowledge (permanent) | ... | ... | ... |
| `bin/skill-scripts/` | Skill scripts (version-controlled) | ... | ... | ... |
| `.claude/` | Tool config | ... | ... | ... |

### Next Steps
- All knowledge in `docs/` is version-controlled — commit it!
- Use `/adr` to record architectural decisions
- Use `/prd` to create product requirements
```

---

## Rules

- **NEVER overwrite** a file that has content — only fill gaps
- **NEVER delete** any file or directory
- **Idempotent** — running 10 times = same result as 1 time
- **Graceful degradation** — if anything fails, report and continue
- **Ask, don't guess** — if git remote missing, ask user
- **Knowledge in `docs/`** — always permanent, always committed to git
- Write everything in **English**
