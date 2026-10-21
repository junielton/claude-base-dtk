# Eval — `review-publish` payload

`review-publish` turns a saved review report into the JSON that goes to GitHub. This eval runs
the skill up to the dry run on five fixture reports and grades the `publish-N.json` it wrote,
programmatically: no judge model, no "does it read well". Same pattern as
`agents/evals/dtk-review-verifier/`.

What it pins down is the part of the review that decides whether the author acts: the verdict,
the absence of hedges, a `suggestion` block when the fix is a local patch, and nothing from the
reviewer's private sections leaking into the text.

## Running it

```bash
skills/review-publish/evals/run.sh                  # current skill, 3 runs x 5 cases
skills/review-publish/evals/run.sh --baseline       # the pre-change snapshot
skills/review-publish/evals/run.sh --runs 1 --case a,c   # quick smoke
skills/review-publish/evals/run.sh --model sonnet --jobs 5 --keep   # --keep leaves the run dirs
```

Needs `jq`, `python3`, and `claude` on PATH. Exit code 0 only if every run passes every check.
A full run is 15 `claude -p` sessions; expect ~10 minutes at `--jobs 5`.

The unit tests for `tone-lint.sh` and its wiring in `post-review.sh` are separate and offline:
`bash skills/review-publish/tests/run-tests.sh`.

## How it works

1. Each run gets a throwaway directory holding `memories/reviews/PR-N/peer-review-1.md` (the
   fixture report) and a copy of `bin/skill-scripts/`.
2. The skill body (`SKILL.md`, frontmatter stripped, `$ARGUMENTS` replaced by the PR number) is
   injected with `claude -p --append-system-prompt-file`. The prompt asks for steps 1 to 5 only:
   build `publish-1.json`, do the voice pass, run the dry run until clean, stop.
3. `gh` is `bin/gh`, a read-only stub that answers `pr view`, `pr diff` and `repo view` from
   `fixtures/pr.diff` and refuses everything else.
4. `grade.py` reads the `publish-1.json` the skill produced.

The voice pass is **not** stubbed: `claude -p` loads the live `~/.claude/skills/juni-vox`, which
prescribes hedges. That is the point. The skill has to strip them after the voice pass, and the
lint has to catch what survives; the eval does not depend on the voice skill changing.

### Never posts (AC-7)

Five independent guards; any one is enough:

1. `post-review.sh` in the run directory is a wrapper that always appends `--dry-run`, and the
   dry-run branch of the real script exits before the only call that submits a review.
2. `gh` on PATH is `bin/gh`, which exits 1 on everything but the three read calls. `run.sh`
   never calls `post-review.sh` or `gh` itself.
3. `GH_TOKEN` / `GITHUB_TOKEN` are set to a dead value, so a real `gh` could not authenticate.
4. `claude` runs with `--permission-mode dontAsk`, an explicit tool allowlist (no bare `gh`),
   and `--strict-mcp-config` (no MCP servers).
5. The run directory is a `mktemp` dir outside any git repo.

The summary also prints how many `gh api` calls were attempted in total (the stub refused all of them).

## The cases

All five share one PR (`fixtures/pr.diff`, repo `acme/shop`); a payload anchor is valid only on
an added line of that diff.

| # | Fixture | Expected |
|---|---|---|
| a | 1 CR + 2 FFT | `REQUEST_CHANGES`, 3 comments, the CR carries a `suggestion` block |
| b | FFT + Q only | `APPROVE`, 2 comments |
| c | zero findings | `APPROVE`, no comments |
| d | `Existing Review Comments`, `Reconciliation` (incl. a `Still pending` CR), `Lessons Applied` and CI notes | `APPROVE`, 2 comments, none of those sections in any body |
| e | one finding marked `Verifier: not checked` | `APPROVE`, the unchecked finding dropped |

## The checks

| Check | Passes when |
|---|---|
| `payload` | a `publish-N.json` exists, parses, and `commit_id` is the PR head |
| `verdict` | `event` equals the case's expected event |
| `lint` | `tone-lint.sh --payload` exits 0 |
| `anchors` | the `path:line` set equals the report's verified findings: nothing dropped, nothing invented |
| `no-leak` | no phrase from the banned sections appears in any body (`leak_phrases` in `cases.json`) |
| `suggestion` | case a only: the CR's body contains a ` ```suggestion ` block |
| `dry-run` | the skill reached `post-review.sh --dry-run` and its last run exited 0 |

A run passes only if every applicable check passes.

## Results

Model: session default (Sonnet 5.5). Live juni-vox. 3 runs per case, 15 per skill.

### Baseline: the skill as it was before this unit (`baseline/SKILL.md` + `baseline/post-review.sh`)

Measured in the commit that introduced this eval, before `tone-lint.sh` existed. The `lint`
column is therefore 0/15 for the trivial reason that the script is missing, and the headline is
0/15.

| Case | pass | payload | verdict | lint | anchors | no-leak | suggestion | dry-run |
|---|---|---|---|---|---|---|---|---|
| a 1 CR + 2 FFT | 0/3 | 3/3 | 0/3 | 0/3 | 3/3 | 3/3 | 0/3 | 3/3 |
| b FFT + Q | 0/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | - | 3/3 |
| c zero findings | 0/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | - | 3/3 |
| d banned sections | 0/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | - | 3/3 |
| e not checked | 0/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | - | 3/3 |
| **total** | **0/15** | | | | | | | |

The same 15 payloads (kept in `baseline/payloads/`), graded again once the lint exists, give the
number that matters: **4/15** (c 3/3, e 1/3). What fails, and why:

- `verdict` 0/3 on case a: the baseline posts the CR as `COMMENT`, as the skill told it to.
- `lint` 0/3 on a, b, d and 2 of 3 on e: every failing payload carries "might be worth"
  (the skill step 3 prescribes "could", "might be worth"; juni-vox says the same).
- `suggestion` 0/3 on a: the baseline never ships a `suggestion` block.
- `anchors`, `no-leak`, `payload` and `dry-run` are 15/15: the baseline already keeps the
  banned sections out and anchors correctly. Those are regression guards for the new skill, not
  things the change was meant to move.

### Unit tests at this commit

`tests/run-tests.sh`: **2 / 36** pass. The two that pass are the clean dry run and the clean real post,
which already worked; the other 34 need `tone-lint.sh` and its wiring in `post-review.sh`.

### New skill

_Recorded in the last commit of this unit._

## What this does not cover

- Step 0 (script resolution) is done in the prompt: its `$(find ...)` and `$SCRIPTS` expansion
  are refused by the sandbox's permission mode, and it is plumbing, not behaviour under test.
- Steps 6 to 8 (the confirmation gate, the post, the record) are out of scope by design.
- Three runs per case catches a rule the skill ignores, not a 1-in-10 slip. A single failure is
  worth re-running before it is believed.
- The fixtures are one PR in one language mix. The checks are about tone and shape, not about
  whether a finding is right; that is `dtk-review-verifier`'s eval.
