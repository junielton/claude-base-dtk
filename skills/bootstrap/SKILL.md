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
mkdir -p .claude/commands .claude/skills .claude/plans
```

### 1.3 — `.gitignore` Entries

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
echo "Tool Config (.claude/):"
for dir in .claude .claude/commands .claude/skills .claude/plans; do
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
