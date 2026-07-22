# DTK — Developer Toolkit for Claude Code

A plugin for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with skills for smart commits, code reviews with persistent memory, architecture decision records, PRDs, and design QA.

## Installation

### 1. Add the marketplace

```bash
claude plugin marketplace add git@github.com:junielton/claude-base-dtk.git
```

> **Private repo?** Works the same way — just make sure your machine has SSH access to the repo.

### 2. Install the plugin

Choose the scope that fits your use case:

```bash
# Global — available in all your projects (default)
claude plugin install dtk@dtk-marketplace

# Project — shared with the team via .claude/settings.json (committed to git)
claude plugin install dtk@dtk-marketplace --scope project

# Local — only you, only this project, gitignored (.claude/settings.local.json)
claude plugin install dtk@dtk-marketplace --scope local
```

### Local development (without installing)

```bash
claude --plugin-dir /path/to/dtk
```

Loads the plugin directly from a local path — useful for development and testing.

## Skills

After installation, all skills are available as `/dtk:<skill-name>`.

### Code workflow

| Skill | Command | Description |
|-------|---------|-------------|
| **smart-commit** | `/dtk:smart-commit` | Analyzes uncommitted changes, groups related files, and creates organized commits using Conventional Commits |
| **create-pr** | `/dtk:create-pr` | Opens a GitHub PR with standardized title (`Title (ID)` from the branch name) and description — PR template, base branch, and task-tracker link discovered from the repo at runtime |
| **ship** | `/dtk:ship` | Runs the full PR lifecycle autonomously — review-local → smart-commit → create-pr → assign reviewers (CODEOWNERS + Copilot if enabled) → monitor CI + reviews → triage → reply → notify |
| **debug-gh-action** | `/dtk:debug-gh-action` | Debugs a failing GitHub Actions run end-to-end — resolves the run/job, reads logs, root-causes it, verifies the fix CI-parity, commits/pushes |
| **report-back** | `/dtk:report-back` | Shared final-report format for multi-step runs: a ✅/⏭️/❌ checklist with concrete outcomes plus a ≤3-line summary |
| **learn-from-review** | `/dtk:learn-from-review` | Extracts actionable lessons from code review sessions and persists them as individual files in `docs/lessons/` |

### Code review (with persistent memory)

All review skills save results to `memories/reviews/` and maintain a `review-state.md` that tracks what was found, resolved, and decided — so each subsequent review knows what changed since the last one. Reviews also load lessons from `docs/lessons/` as mandatory checkpoints.

| Skill | Command | Description |
|-------|---------|-------------|
| **review** | `/dtk:review <PR#>` | Reviews your own PR via GitHub MCP — analyzes diff, checks against lessons learned, evaluates comments |
| **review-local** | `/dtk:review-local [base]` | Reviews all changes on current branch vs base (default: `main`) — works before opening a PR |
| **review-peer** | `/dtk:review-peer <PR#>` | Reviews someone else's PR — constructive, GitHub-ready feedback with blocking/non-blocking/questions format |

### Documentation

| Skill | Command | Description |
|-------|---------|-------------|
| **adr** | `/dtk:adr` | Creates Architecture Decision Records in `docs/adrs/` with context, alternatives, and consequences |
| **prd** | `/dtk:prd` | Generates Product Requirements Documents through interactive refinement, saved to `docs/prds/` |

### Design QA

| Skill | Command | Description |
|-------|---------|-------------|
| **dsqa** | `/dtk:dsqa` | Compares a Figma design against a running browser implementation — reports every deviation with exact values and fixes |
| **implement-design** | `/dtk:implement-design` | Full workflow from Figma design to implemented component — handles context gathering, planning, execution, and DSQA verification |

## Scripts

Skills delegate reusable logic to scripts in `bin/skill-scripts/`, organized by domain. Scripts run from the installed plugin — no project setup required.

| Directory | Scripts | Used by |
|-----------|---------|---------|
| `review/` | `project-context.sh`, `memory-manager.sh`, `lessons-loader.sh` | review, review-local, review-peer |
| `lessons/` | `create-lesson.sh` | learn-from-review |
| `dsqa/` | `capture-and-compare.mjs`, `deep-inspect.mjs`, `check-deps.sh`, `utils/color-utils.mjs` | dsqa |
| `adr/` | `next-number.sh` | adr |
| `commit/` | `gather-changes.sh` | smart-commit |
| `shared/` | `figma-url-parser.sh` | dsqa, implement-design |

## Project structure used by the skills

The documentation skills write into a `docs/` knowledge base in your project, creating directories and index files on first use — no setup step needed:

```
your-project/
├── docs/
│   ├── adrs/                       ← architecture decision records (+ index.md)
│   ├── lessons/                    ← lessons learned from reviews (+ index.md)
│   ├── plans/                      ← implementation plans
│   └── prds/                       ← product requirements
└── memories/                       ← review state (gitignored)
    └── reviews/
```

## Knowledge cycle

```
Code review → /dtk:learn-from-review → docs/lessons/{category}/NNN-slug.md
                                                    ↓
Next review → lessons-loader.sh → loads as mandatory checkpoints
                                                    ↓
                              Issues reference specific lesson file paths
```

## Updating

If auto-update is enabled for the marketplace, the plugin updates automatically when Claude Code starts. Otherwise:

```bash
claude plugin update dtk@dtk-marketplace
```

## License

MIT
