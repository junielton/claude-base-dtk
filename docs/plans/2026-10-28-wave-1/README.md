# Wave 1 — dtk quality delivery (2026-10-28)

Source plan: `plano-de-acao.md` (same folder). Market research behind it: `.harnu/out/reports/Posicionamento do dtk marketplace.md` on the orchestrator's machine (not committed).

## Topology

Eight independent units, parallel, all forked from the integration branch `feat/dtk-wave-1` at the same SHA. Every unit PR targets `feat/dtk-wave-1`. The final PR `feat/dtk-wave-1 → main` carries the Delivery Report. Nobody merges but the operator.

Shared-file hazards (confirmed by grep):
- W2 (scripts) and W6 (review-core) both touch `skills/review*/SKILL.md`. W2 edits ONLY the "Step 0: Resolve Scripts" block and script paths; W6 edits ONLY workflow prose below Step 0 and must keep Step 0 untouched. Conflicts expected to be trivial.
- W3 touches `agents/dtk-review-verifier.md` + its evals; W6 must not rewrite the verifier dispatch contract (inputs/outputs), only move prose.
- W4 touches `skills/learn-from-review/`, `bin/skill-scripts/lessons/`; W5 touches `bin/skill-scripts/review/outcomes.py` (read-only for W4; W4 may add a NEW script for retirement rather than editing outcomes.py).
- W1 touches README, LICENSE, workflow, and three one-line dead references; W8 adds a NEW workflow file only.

## Conventions for every executor

- Branch: `wave1/<unit-slug>` (already created by the orchestrator; never create another).
- Commits: Conventional Commits, scoped (`fix(scripts): …`, `feat(verifier): …`, `docs: …`). Small commits; the first commit of a unit that adds a test or eval case is the failing case.
- PR: do NOT open it. Commit, push, leave a clean tree, write `.harnu/REPORT.md`, report. A separate shipper session opens the PR against `feat/dtk-wave-1`.
- Scope: only the paths listed in your unit. No refactors outside them, no new dependencies, no edits to other units' files.
- Honest exit: if an AC cannot be satisfied, report `AC-n: unmet` with the reason, or `blocked` with the question. Never drop, weaken or rewrite an AC.
- Verify before claiming: run the commands in `WORKTREE.md` that cover what you touched, after your last edit, and quote the command + exit code in the report.
- Report format: branch, head sha, one-line summary, per-AC self-assessment (met/unmet/blocked + evidence line), unresolved findings. Written to `.harnu/REPORT.md` in the worktree AND sent via `SendMessage` to the orchestrator (address resolved at send time via `ListAgents`; open with `Report for session <owner-uuid> · mission <id> · step <stepId>`).

## Units and acceptance criteria

### W1 — hygiene (`wave1/w1-hygiene`)
Scope: `LICENSE`, `README.md`, `.github/workflows/auto-version.yml`, `CHANGELOG.md` (new), one-line edits in `skills/laravel-scaffold-design-panel/SKILL.md`, `bin/skill-scripts/design-panel/write-manifest.mjs` header, `skills/ship/SKILL.md`, `skills/implement-design/SKILL.md`.
- [ ] AC-1 — `LICENSE` file exists with the MIT text and the author's name; README license line matches — verify: review — source: plan §3 W1
- [ ] AC-2 — README install section uses the HTTPS clone URL `https://github.com/junielton/claude-base-dtk.git` as primary and keeps SSH as an alternative — verify: review — source: plan §3 W1
- [ ] AC-3 — README skills table lists every skill in `skills/` (20) with a one-line purpose; `draft-to-prompt` and `laravel-scaffold-design-panel` included — verify: review (`ls skills | wc -l` vs table rows) — source: plan §3 W1
- [ ] AC-4 — `auto-version.yml` creates a GitHub Release for each new tag with notes generated from commits since the previous tag; `CHANGELOG.md` is created with the existing 16 tags' history reconstructed from `git log` and the workflow prepends a section per release — verify: review + `act`-free dry-read of the workflow YAML (valid YAML, `softprops/action-gh-release` or `gh release create`) — source: plan §3 W1
- [ ] AC-5 — Dead references removed or made true: `dtk:update-design` mention in `laravel-scaffold-design-panel/SKILL.md` and `write-manifest.mjs` header; `speak-notify` binary mention in `ship/SKILL.md`; the "Phase 7 manifest write" claim about implement-design either removed from the panel skill or implemented as a documented step — verify: review (`grep -rn 'update-design\|speak-notify' skills bin` returns nothing misleading) — source: local inventory KQ7

### W2 — scripts & resolver (`wave1/w2-scripts`)
Scope: `bin/` → `scripts/` move (git mv), the "Step 0: Resolve Scripts" block of every SKILL.md that has one, `skills/debug-gh-action/SKILL.md` script path, the `$MK` block in `skills/create-mockup`, `skills/implement-mockup`, `skills/mockup-qa`, `WORKTREE.md` and `README.md` paths, test runner paths.
- [ ] AC-1 — No top-level `bin/` directory remains; all scripts live under `scripts/` (same subfolders) and `git log --follow` shows renames, not deletes+adds — verify: test (`test ! -d bin && test -d scripts`) — source: code.claude.com/docs/en/plugins-reference (top-level `bin/` blocks claude.ai/Cowork install)
- [ ] AC-2 — Exactly one script-resolution idiom across all SKILL.md files: `SCRIPTS="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)}/scripts"` or an equivalent single documented snippet in `docs/conventions/script-resolution.md`, referenced by every skill; no `find -maxdepth`, no hard-coded `~/.claude/plugins/cache/...`, no bare relative `scripts/resolve-run.sh` — verify: test (`grep -rn 'maxdepth\|plugins/cache\|^scripts/' skills/*/SKILL.md` empty) — source: local inventory KQ7
- [ ] AC-3 — `skills/debug-gh-action/SKILL.md` resolves its script through the same idiom and works when cwd is a user project (test by running the resolver snippet from `/tmp`) — verify: test — source: local inventory KQ7
- [ ] AC-4 — All existing test suites pass after the move: `bash skills/review-publish/tests/run-tests.sh`, `node --test scripts/design-panel/tests/`, `python3 scripts/review/outcomes.py --self-test` — verify: test (exit 0 each, quoted in report) — source: WORKTREE.md
- [ ] AC-5 — `claude plugin validate --strict .` passes — verify: test — source: plugin docs
- [ ] AC-6 — Every SKILL.md that references a script path points at a path that exists (`grep -o 'scripts/[A-Za-z0-9_./-]*' skills/*/SKILL.md | sort -u` each exists) — verify: test — source: W2 objective

### W3 — verifier v2 (`wave1/w3-verifier-v2`)
Scope: `agents/dtk-review-verifier.md`, `agents/evals/dtk-review-verifier/**`, and ONLY the verifier-dispatch paragraph ("Verify Findings") in `skills/review/SKILL.md`, `skills/review-local/SKILL.md`, `skills/review-peer/SKILL.md` if the input contract changes.
- [ ] AC-1 — Context asymmetry: the verifier forms and records a provisional verdict from `severity + location + claim + scope` BEFORE it is allowed to read `reasoning`; the agent file makes this a two-phase method and the output block carries both `blind_verdict` and `final_verdict` — verify: review + eval — source: arXiv 2604.19049 (Refute-or-Promote, context asymmetry)
- [ ] AC-2 — Hard rule: a `blocking` finding whose claim is about runtime behavior survives only with a `file:line` citation of the code exhibiting it; a claim justified by naming/inference alone is `refuted` — verify: eval case — source: Anthropic REVIEW.md idiom (code.claude.com/docs/en/code-review-customize)
- [ ] AC-3 — Empirical gate, opt-in: for `blocking` findings the verifier MAY run commands from an explicit allowlist (`grep`, `rg`, `git`, `php -l`, `node -e`/`node --check`, `python3 -c`, a single filtered test such as `php artisan test --filter=<Class>` or `npx vitest run <file>` / `node --test <file>`) when a test or one-liner can falsify the claim; it NEVER runs migrations, seeders, package managers, builds, or unfiltered suites; the command + exit code is recorded in the verdict block as `empirical:` — verify: review + eval case — source: operator decision 2026-10-28 ("Sim, com allowlist")
- [ ] AC-4 — Model configurable: the agent frontmatter `model:` is set so the verifier runs on a different model than the reviewer by default (document the choice and how to override) — verify: review — source: Refute-or-Promote cross-model critic
- [ ] AC-5 — Existing eval suite still 9/9; at least 3 new cases added: (a) anchoring (persuasive but false `reasoning` on a refutable blocking claim → refuted), (b) empirical (a claim falsifiable by one filtered test → the verdict cites `empirical:`), (c) citation rule (behavior claim without file:line → refuted) — verify: test (`bash agents/evals/dtk-review-verifier/run.sh`, pass counts quoted) — source: plan §2 I2/I3
- [ ] AC-6 — `agents/evals/dtk-review-verifier/README.md` updated honestly with results, including any case that does not pass — verify: review — source: repo eval convention

### W4 — lessons export & lifecycle (`wave1/w4-lessons`)
Scope: `skills/learn-from-review/**`, `bin/skill-scripts/lessons/**` (or `scripts/lessons/**` if W2 lands first; do not fight the rename), `docs/lessons/` template docs, a NEW script for retirement; read-only use of `outcomes.py`.
- [ ] AC-1 — Each lesson file carries frontmatter `status: candidate | active | retired` and `source: own | peer`; `learn-from-review` writes `active` for lessons extracted from the user's own reviews and `candidate` for lessons extracted from `review-peer` sessions — verify: review + test fixture — source: operator decision 2026-10-28
- [ ] AC-2 — `lessons-loader.sh` (or successor) loads only `active` lessons into reviews by default; `--include-candidates` flag exists — verify: test (fixture dir with 3 statuses → loader output) — source: plan §2 I5
- [ ] AC-3 — Export: a script regenerates a delimited block (`<!-- dtk:lessons:start -->` … `<!-- dtk:lessons:end -->`) in `REVIEW.md` and `.github/copilot-instructions.md` of the target repo from active lessons, idempotently (running twice yields no diff), never touching text outside the markers; `learn-from-review` calls it after writing a lesson — verify: test (fixture repo, run twice, `git diff --stat` empty second time) — source: plan §2 I4; Copilot reads first 4,000 chars of copilot-instructions (github.blog 2025-06-13) so the block is capped and the cap documented
- [ ] AC-4 — Retirement: a script reads `outcomes.py` output (or its JSON) and lists lessons whose tagged findings were refuted or marked wrong N times with 0 accepted; it proposes `retired` (writes nothing without `--apply`) — verify: test with a synthetic outcomes JSON — source: plan §2 I5
- [ ] AC-5 — `skills/learn-from-review/SKILL.md` documents the lifecycle and the export in ≤ 40 added lines; description updated with trigger phrases and a "Do NOT use" line — verify: review — source: plan §3 W4

### W5 — review-outcomes skill (`wave1/w5-review-outcomes`)
Scope: NEW `skills/review-outcomes/**`, `docs/review-outcomes.md` (definitions section), `bin/skill-scripts/review/outcomes.py` (only to add machine-readable `--json` if missing).
- [ ] AC-1 — `skills/review-outcomes/SKILL.md` exists with a trigger-rich description ("how are my reviews doing", "review metrics", "taxa de falso positivo", …) and a "Do NOT use" line — verify: review — source: plan §2 I6
- [ ] AC-2 — The skill defines each metric explicitly in a table: `posted`, `refuted-by-verifier`, `accepted`, `resolved-by-merge`, `marked-wrong`, `hedges`, `CR-as-CR`; each with the exact signal used — verify: review — source: pr_lifecycle notes (no vendor publishes neutral definitions)
- [ ] AC-3 — `outcomes.py --json` emits those metrics per reviewer and per tag; `--self-test` still passes — verify: test — source: W5 objective
- [ ] AC-4 — The skill's output is a compact table plus a 3-line read, no emoji (report-back rail convention) — verify: review — source: `skills/report-back/SKILL.md`
- [ ] AC-5 — `docs/review-outcomes.md` gains a "Definitions" section and its example repos/reviewers are replaced by placeholders (`owner/repo`, `reviewer-a`) — verify: review — source: local inventory KQ7

### W6 — review-core consolidation (`wave1/w6-review-core`)
Scope: NEW `skills/review-core/references/*.md` (or `skills/review/references/` if a skill dir without SKILL.md is invalid — check `claude plugin validate`), workflow prose in `skills/review/SKILL.md`, `skills/review-local/SKILL.md`, `skills/review-peer/SKILL.md`, output vocabulary in `skills/review-publish/SKILL.md`. Do NOT touch "Step 0: Resolve Scripts" blocks (W2 owns them) nor the verifier input contract (W3 owns it).
- [ ] AC-1 — The ~150 lines repeated across review, review-local and review-peer (context gathering, lessons load, 4-pass analysis, memory load/reconcile, verifier dispatch, diff-reading rules, common mistakes) live once under `references/` and each skill loads them with an explicit "Read `<path>` now" step; each of the three SKILL.md files shrinks by ≥ 100 lines — verify: test (`wc -l` before/after quoted) — source: local inventory KQ7
- [ ] AC-2 — Behavior preserved: the frozen review-publish eval (`skills/review-publish/evals`) still passes at its documented level, and the review-peer eval expectations file is unchanged — verify: test — source: repo eval convention
- [ ] AC-3 — The shared analysis checklist is stack-neutral (no Eloquent/Livewire-only items as mandatory; stack-specific checks move to an optional `references/stacks/laravel.md` loaded when `composer.json` exists) — verify: review — source: local inventory KQ7
- [ ] AC-4 — Output vocabulary aligned with the report-back rail: review/review-local/review-peer reports use the same glyph set as `skills/report-back/SKILL.md` (no emoji); the rail glyphs are documented once in `references/output-vocabulary.md` — verify: review (`grep -c '✅\|❌\|🟡\|🔴' skills/review*/SKILL.md` = 0) — source: `skills/report-back/SKILL.md` ban
- [ ] AC-5 — `claude plugin validate --strict .` passes and each of the three descriptions keeps its trigger phrases — verify: test — source: plugin docs

### W7 — dsqa deps isolation (`wave1/w7-dsqa-deps`)
Scope: `skills/dsqa/**`, `skills/mockup-qa/**`, their scripts under `bin/skill-scripts/dsqa/` (or `scripts/dsqa/`), a NEW fixture dir.
- [ ] AC-1 — dsqa and mockup-qa no longer run `npm install --save-dev` in the user's project; dependencies (puppeteer, pngjs, pixelmatch) are installed into a plugin-owned cache dir (e.g. `${XDG_CACHE_HOME:-~/.cache}/dtk/node_modules`) via `npm install --prefix`, reused across runs, and the user's `package.json` is byte-identical before/after a run — verify: test (fixture project; `git diff --exit-code package.json package-lock.json`) — source: local inventory KQ7
- [ ] AC-2 — A minimal alignment fixture exists: two known HTML pages (identical layout, one with a 4px shift) and a test asserting the diff script reports > 0% for the shifted pair and 0% for identical pairs at a fixed viewport — verify: test (`node --test`) — source: design_to_code notes (alignment is asserted, never tested, across all tools)
- [ ] AC-3 — Both SKILL.md files document the cache location, how to clear it, and the viewport/scale assumptions — verify: review — source: W7 objective
- [ ] AC-4 — `claude plugin validate --strict .` passes — verify: test

### W8 — CI (`wave1/w8-ci`)
Scope: NEW `.github/workflows/ci.yml` only (plus a README badge line if desired).
- [ ] AC-1 — On `pull_request` and `push` to `main`/`feat/**`, CI runs: `bash skills/review-publish/tests/run-tests.sh`, `node --test` over the design-panel tests (path chosen by what exists: `bin/skill-scripts/...` or `scripts/...`, detect with a shell conditional so it survives W2), `python3 .../outcomes.py --self-test` — verify: test (workflow YAML valid; job steps present) — source: WORKTREE.md
- [ ] AC-2 — CI runs `claude plugin validate --strict .` using the official Claude Code CLI install step (`npm i -g @anthropic-ai/claude-code`), with a documented fallback that marks the step as skipped (not failed) when the CLI cannot be installed offline — verify: review — source: plugin docs
- [ ] AC-3 — The workflow never calls paid evals (`run.sh` suites that invoke `claude -p`) — verify: review (`grep -c 'evals' ci.yml` = 0 except comments) — source: WORKTREE.md notes
- [ ] AC-4 — Node 20+ and Python 3.11+ pinned via `actions/setup-node` / `actions/setup-python`; total runtime target < 3 min — verify: review — source: W8 objective
- [ ] AC-5 — A first CI run on the PR is green, or the failing step is a real pre-existing failure documented in the report — verify: test (CI URL in report) — source: W8 objective
