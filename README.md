# dtk — Developer Toolkit for Claude Code

A plugin for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with skills for smart commits, code reviews with persistent memory, architecture decision records, PRDs, and design QA.

## Installation

### From a Git repository (recommended)

```bash
# Add the marketplace
claude plugin marketplace add git@github.com:junielton/claude-base-dtk.git

# Install the plugin
claude plugin install dtk@dtk-marketplace
```

> **Private repo?** Works the same way — just make sure your machine has SSH access to the repo.

### Local development

```bash
claude --plugin-dir /path/to/dtk
```

## Skills

After installation, all skills are available as `/dtk:<skill-name>`.

### Code workflow

| Skill | Command | Description |
|-------|---------|-------------|
| **smart-commit** | `/dtk:smart-commit` | Analyzes uncommitted changes, groups related files, and creates organized commits using Conventional Commits |
| **learn-from-review** | `/dtk:learn-from-review` | Extracts actionable lessons from code review sessions and saves them to `docs/lessons/` |

### Code review (with persistent memory)

All review skills save results to `memories/reviews/` inside the project and maintain a `review-state.md` that tracks what was found, resolved, and decided — so each subsequent review knows what changed since the last one.

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

### Project setup

| Skill | Command | Description |
|-------|---------|-------------|
| **bootstrap** | `/dtk:bootstrap` | Sets up project structure — creates `docs/` knowledge base, `.claude/` config, verifies everything, fetches remote resources |

### Design QA

| Skill | Command | Description |
|-------|---------|-------------|
| **dsqa** | `/dtk:dsqa` | Compares a Figma design against a running browser implementation — reports every deviation with exact values and fixes |
| **implement-design** | `/dtk:implement-design` | Full workflow from Figma design to implemented component — handles context gathering, planning, execution, and DSQA verification |

## Shared scripts

The plugin includes helper scripts in `scripts/` that skills use to avoid hardcoded project paths:

- **`project-context.sh`** — Detects git owner, repo, current branch, base branch, and task ID from the current project
- **`memory-manager.sh`** — Manages the `memories/reviews/` directory for persistent review state
- **`lessons-loader.sh`** — Discovers lesson files from `docs/lessons/` or falls back to Claude's auto-memory

## Project structure created by bootstrap

After running `/dtk:bootstrap`, your project gets:

```
your-project/
├── CLAUDE.md                  ← project conventions + architecture
├── docs/
│   ├── adrs/                  ← architecture decision records
│   │   └── index.md
│   ├── lessons/               ← lessons learned from reviews
│   │   ├── index.md
│   │   ├── security/
│   │   ├── code-patterns/
│   │   ├── performance/
│   │   └── ...
│   └── prds/                  ← product requirements
└── memories/
    └── reviews/               ← persistent review state (per branch/PR)
```

## Statusline

The plugin includes a rich terminal statusline showing model info, token usage, context window percentage, git status, and agent info. It's configured automatically via `settings.json`.

## Updating

If auto-update is enabled for the marketplace, the plugin updates automatically when Claude Code starts. Otherwise:

```bash
claude plugin update dtk@dtk-marketplace
```

## License

MIT
# claude-base-dtk
