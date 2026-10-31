# DTK — Developer Toolkit for Claude Code

A plugin for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with skills for smart commits, code reviews with persistent memory, architecture decision records, PRDs, and design QA.

## Installation

### 1. Add the marketplace

```bash
claude plugin marketplace add https://github.com/junielton/claude-base-dtk.git
```

> **Prefer SSH?** `claude plugin marketplace add git@github.com:junielton/claude-base-dtk.git` works the same way — just make sure your machine has SSH access to GitHub.

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
| **create-pr** | `/dtk:create-pr` | Opens a GitHub PR with standardized title (`Title (ID)` from the branch name, including `<prefix>/<ID>-<slug>` branches like `card/T593-…`) and description — PR template, base branch, and task-tracker link discovered from the repo at runtime (plain ID when no tracker pattern exists); UI diffs get agent-captured desktop (1440) and mobile (375) screenshots |
| **ship** | `/dtk:ship` | Runs the full PR lifecycle autonomously — review-local → smart-commit → create-pr → assign reviewers (CODEOWNERS + Copilot if enabled) → monitor CI + reviews → triage → reply → notify |
| **git-rebase-onto** | `/dtk:git-rebase-onto [target] [topic] [push]` | Moves a branch onto a new base with `git rebase --onto` — finds the cut point (stacked PRs, squash-merged parents), previews, backs up, rebases, and resolves conflicts conservatively; the `push` argument publishes with `--force-with-lease` without a second confirmation |
| **debug-gh-action** | `/dtk:debug-gh-action` | Debugs a failing GitHub Actions run end-to-end — resolves the run/job, reads logs, root-causes it, verifies the fix CI-parity, commits/pushes |
| **report-back** | `/dtk:report-back` | Shared final-report format for multi-step runs: a rail of steps with concrete outcomes, a ledger of what is owed, a links list and a ≤3-line summary |
| **learn-from-review** | `/dtk:learn-from-review` | Extracts actionable lessons from code review sessions and persists them as individual files in `docs/lessons/` |
| **draft-to-prompt** | `/dtk:draft-to-prompt` | Turns a rough idea, draft or vague request into a production-quality prompt for Claude models (Haiku, Sonnet, Opus, Fable) — also for boot prompts for new sessions, worktrees or dispatched agents |

### Code review (with persistent memory)

All review skills save results to `memories/reviews/` and maintain a `review-state.md` that tracks what was found, resolved, and decided — so each subsequent review knows what changed since the last one. Reviews also load lessons from `docs/lessons/` as mandatory checkpoints.

Before anything is reported, every finding goes through the **`dtk-review-verifier`** subagent (`agents/dtk-review-verifier.md`): a read-only skeptic that tries to disprove the finding against the actual code, with a bar that depends on severity — a blocking finding must be proven or it is dropped, while a suggestion or a question only has its factual premise checked. Refuted findings never reach the output, and each review reports how many were kept vs. refuted.

| Skill | Command | Description |
|-------|---------|-------------|
| **review** | `/dtk:review <PR#>` | Reviews your own PR via GitHub MCP — analyzes diff, checks against lessons learned, evaluates comments |
| **review-local** | `/dtk:review-local [base]` | Reviews all changes on current branch vs base (default: `main`) — works before opening a PR |
| **review-peer** | `/dtk:review-peer <PR#>` | Reviews someone else's PR and saves the report — blocking/non-blocking/questions, each verified before it is written |
| **review-publish** | `/dtk:review-publish <PR#>` | Turns the saved report into the GitHub review: verdict, one-line body, one inline comment per verified finding (Q/CR/FFT), written through your own voice skill when one exists, anchors validated against the diff, posted only after confirmation |

#### Voice skill

`review-publish` writes in the neutral register unless you have a writing-voice skill. It finds yours by `voice_skill:` in `~/.claude/dtk.local.md` (or the project's `.claude/dtk.local.md`), by `voice: true` in a skill's `SKILL.md` frontmatter, or by a skill named `<something>-vox` / `<something>-voice`. The voice skill only reshapes wording; the content is frozen before it runs.

### Documentation

| Skill | Command | Description |
|-------|---------|-------------|
| **adr** | `/dtk:adr` | Creates Architecture Decision Records with context, alternatives, and consequences — follows the repo's existing ADR layout, defaulting to `docs/adrs/` |
| **prd** | `/dtk:prd` | Generates Product Requirements Documents through interactive refinement, saved following the repo's existing PRD layout, defaulting to `docs/prds/` |

### Design QA

| Skill | Command | Description |
|-------|---------|-------------|
| **dsqa** | `/dtk:dsqa` | Compares a Figma design against a running browser implementation — reports every deviation with exact values and fixes |
| **implement-design** | `/dtk:implement-design` | Full workflow from Figma design to implemented component — handles context gathering, planning, execution, and DSQA verification |
| **laravel-scaffold-design-panel** | `/dtk:laravel-scaffold-design-panel` | Installs the dtk design-system panel in a Laravel project — a `/design-system` showcase with per-component preview routes and Figma-link/sync/API features driven by `design/manifests/` |

### HTML mockups (no Figma)

A visual contract authored as HTML inside the project: `docs/design/<slug>/` with `mockup.json` (status per screen), one `screens/<id>.html` per screen (states via `?state=`, flows via `data-goto` navigating between files), optional `parts/`, the project's tokens copied verbatim, and a thin `index.html` that only embeds. `scripts/mockup/check-mockup.mjs` is the mechanical gate the three skills share.

| Skill | Command | Description |
|-------|---------|-------------|
| **create-mockup** | `/dtk:create-mockup` | Authors the mockup screen by screen — inventory first, tokens verbatim, clickable flows, checker before every presentation, approval per screen |
| **implement-mockup** | `/dtk:implement-mockup` | Builds the approved screens 1:1 in the real app (parts first, states reachable, routes wired) and ends in a mandatory mockup-qa pass |
| **mockup-qa** | `/dtk:mockup-qa` | Verifies the app against the approved screens, state by state and viewport by viewport — strict computed styles, anatomy, pixel diff, flows walked by clicking |

## Scripts

Skills delegate reusable logic to scripts in `scripts/`, organized by domain. Scripts run from the installed plugin — no project setup required. Every skill resolves the folder with one line, documented in [`docs/conventions/script-resolution.md`](docs/conventions/script-resolution.md).

| Directory | Scripts | Used by |
|-----------|---------|---------|
| `review/` | `project-context.sh`, `memory-manager.sh`, `lessons-loader.sh` | review, review-local, review-peer |
| `lessons/` | `create-lesson.sh` | learn-from-review |
| `dsqa/` | `capture-and-compare.mjs`, `deep-inspect.mjs`, `check-deps.sh`, `utils/color-utils.mjs` | dsqa, mockup-qa |
| `adr/` | `next-number.sh` | adr |
| `commit/` | `gather-changes.sh` | smart-commit |
| `shared/` | `figma-url-parser.sh` | dsqa, implement-design |
| `pr/` | `upload-attachment.sh` | create-pr |
| `design-panel/` | `install-design-panel.mjs`, `write-manifest.mjs` | laravel-scaffold-design-panel |
| `mockup/` | `check-mockup.mjs` | create-mockup, implement-mockup, mockup-qa |
| `gh-action/` | `resolve-run.sh` | debug-gh-action |
| `git-rebase-onto/` | `analyze_branches.sh`, `safe_rebase_onto.sh`, `conflict_status.sh` | git-rebase-onto |

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

## Releases

Every merge to `main` with a releasable Conventional Commit is versioned and tagged automatically by `.github/workflows/auto-version.yml`, which also publishes a [GitHub Release](https://github.com/junielton/claude-base-dtk/releases) and prepends a section to [`CHANGELOG.md`](CHANGELOG.md).

## License

MIT — see [LICENSE](LICENSE). © Junielton Quirino.
