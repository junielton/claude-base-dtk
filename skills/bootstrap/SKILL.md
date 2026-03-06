---
name: bootstrap
description: "Verify and create project structure — docs/ knowledge base, .claude/ config, and .gitignore entries. Idempotent and safe to run multiple times. Use when setting up a new project or verifying an existing one."
---

# /bootstrap — Project Structure Setup

You are a project bootstrap assistant. Your job is to:

1. Detect the project context (git remote, owner, repo)
2. Verify the complete project structure exists
3. Create anything that's missing
4. Never overwrite files that already have content

**Key principle:** Project knowledge (ADRs, lessons, PRDs) lives in `docs/` — it belongs to the project and survives any tool. Tool configuration lives in `.claude/` — it's disposable and can be rebuilt.

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
  docs/prds
```

### 1.2 — Tool Configuration (`.claude/`)

```bash
mkdir -p .claude/commands .claude/skills
```

### 1.3 — Index Files

Create index files **only if they don't already exist**. These are the central reference points for all project knowledge.

#### `docs/adrs/index.md`

```markdown
# Architecture Decision Records

| # | Decision | Weight | Status | Date |
|---|----------|--------|--------|------|
```

#### `docs/lessons/index.md`

```markdown
# Lessons Learned

Central index of all lessons extracted from code reviews, incidents, and retrospectives.

## Categories

- [Security](./security/)
- [Code Patterns](./code-patterns/)
- [QA](./qa/)
- [Performance](./performance/)
- [Framework](./framework/)
- [Testing](./testing/)
- [Frontend](./frontend/)

## Recent Lessons

| # | Lesson | Category | Severity | Date |
|---|--------|----------|----------|------|
```

#### `docs/prds/index.md`

```markdown
# Product Requirements Documents

| PRD | Status | Author | Created |
|-----|--------|--------|---------|
```

#### `.claude/MEMORY.md`

This file acts as the **central memory** for AI-assisted development. It links all knowledge bases so Claude can quickly find project context.

```markdown
# Project Memory

Quick-access index for all project knowledge. Claude should consult these references when making decisions.

## Knowledge Base

- **Architecture Decisions:** [docs/adrs/index.md](../docs/adrs/index.md) — technical decisions, trade-offs, and rationale
- **Lessons Learned:** [docs/lessons/index.md](../docs/lessons/index.md) — patterns, anti-patterns, and insights from reviews
- **Product Requirements:** [docs/prds/index.md](../docs/prds/index.md) — feature specs and acceptance criteria
```

### 1.4 — CLAUDE.md Reference

If `CLAUDE.md` exists at the project root but does **not** reference MEMORY.md, append:

```markdown

## Project Memory

This project maintains a structured knowledge base. Before making architectural decisions or reviewing code, consult:

→ [.claude/MEMORY.md](.claude/MEMORY.md)
```

If `CLAUDE.md` does not exist, create it with:

```markdown
# {GIT_REPO}

## Project Memory

This project maintains a structured knowledge base. Before making architectural decisions or reviewing code, consult:

→ [.claude/MEMORY.md](.claude/MEMORY.md)
```

### 1.5 — `.gitignore` Entries

```bash
for entry in "settings.local.json" "memories/"; do
  grep -q "$entry" .gitignore 2>/dev/null || echo -e "\n# Claude Code\n.claude/$entry" >> .gitignore
done
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
for dir in docs docs/adrs docs/lessons docs/prds; do
  [ -d "$dir" ] && echo "  ✅ $dir/" || echo "  ❌ $dir/"
done

echo ""
echo "Index Files:"
for file in docs/adrs/index.md docs/lessons/index.md docs/prds/index.md .claude/MEMORY.md; do
  [ -f "$file" ] && echo "  ✅ $file" || echo "  ❌ $file"
done

echo ""
echo "Tool Config (.claude/):"
for dir in .claude .claude/commands .claude/skills; do
  [ -d "$dir" ] && echo "  ✅ $dir/" || echo "  ❌ $dir/"
done

echo ""
echo "CLAUDE.md:"
if [ -f "CLAUDE.md" ]; then
  grep -q "MEMORY.md" CLAUDE.md && echo "  ✅ CLAUDE.md → references MEMORY.md" || echo "  ⚠️  CLAUDE.md exists but missing MEMORY.md reference"
else
  echo "  ❌ CLAUDE.md not found"
fi
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
| `.claude/` | Tool config | ... | ... | ... |

### Next Steps
- All knowledge in `docs/` is version-controlled — commit it!
- `.claude/MEMORY.md` is the central index — Claude will consult it automatically
- Use `/adr` to record architectural decisions
- Use `/prd` to create product requirements
- Use `/learn-from-review` to capture lessons from code reviews
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
