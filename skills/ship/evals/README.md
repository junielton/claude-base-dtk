# Eval — `ship` delegation

`ship` is an orchestrator: each step names a skill (`review-local`, `smart-commit`, `create-pr`,
`debug-gh-action`, `report-back`). The failure this eval exists for is the agent loading `ship`
and then doing that work **inline** — reading the diff itself instead of `review-local`, running
`gh pr create` instead of `create-pr`, calling a red check flaky from the log instead of
`debug-gh-action`. It happens most with a dispatcher prompt that carries an override list: lines
like "review the diff cold" or "PR title/description per CONTRIBUTING.md" read as permission to
replace the step, when they are only input to it.

This eval measures **whether the skills were called**, from the tool-call trace, not from what the
agent says it did.

## Cases

| Case | Setup | What must hold |
|---|---|---|
| `dispatched-pr-only` | The T580 shape: committed + pushed, a dispatcher override list, CI green | `review-local` and `create-pr` called, in that order, and no raw `gh pr create` before `create-pr` |
| `dispatched-ci-red` | Same dispatch, one CI shard red on a timeout | Everything above, plus `debug-gh-action` called (the "flaky" verdict is the skill's, not the agent's) |
| `plain-ship-uncommitted` | `ship isso`, uncommitted changes, no overrides | `review-local` → `smart-commit` → `create-pr` in order, no raw `gh pr create` first, `report-back` called |
| `explicit-skip-respected` | The user names the steps to skip ("skip the local review", "plain `gh pr create`") | `review-local` and `create-pr` **not** called, raw `gh pr create` used. Guards against over-hardening: only an instruction that *names* a step may replace it |

## Running it

```bash
./run.sh                                  # 3 runs per case, Sonnet, against ../SKILL.md
./run.sh --skill <snapshot.md>            # A/B a pre-edit snapshot
./run.sh --case dispatched --runs 5       # cases matching a regex, more samples
./run.sh --model default                  # the session's default model instead of Sonnet
./run.sh --keep                           # keep sandboxes, traces and stderr
```

Needs `jq`, `git`, `python3` and `claude`. Exit code is 0 only if every valid run meets every
expectation. The header prints `contract : PRESENT | absent` by grepping the skill under test, so a
table can never be attributed to the wrong variant. Default model is **Sonnet**, on purpose: see
"The failure is model-dependent" below. Cost is about $0.15 per run on Sonnet, $1 on Fable 5.1.

## How it works

1. The skill under test is copied into a throwaway plugin named `dtk` as a **real skill**, next to
   stubs for the skills it chains. A stub just replies; the `create-pr` and `smart-commit` stubs run
   the one `gh`/`git` command the real skill would, so the pipeline has something to continue from.
2. Each run gets its own git repo: `main` plus a branch one commit ahead (or with uncommitted
   changes), a local bare `origin` rewritten to look like `github.com/acme/demo`, and
   `CONTRIBUTING.md` / a PR template.
3. `gh-stub.sh` is first on `PATH`. It never talks to GitHub, logs every call, and answers from state:
   `gh pr create` makes later `view`/`list`/`checks` find the PR; `GH_STUB_CI=red` fails one shard;
   the Copilot reviewer request returns 422, so there is no reviewer to wait on.
4. `claude -p` runs with `--setting-sources project`, so the user's own settings, hooks,
   plugins, personal skills and `CLAUDE.md` do not leak in. Verified from the `init` event: the only
   plugin is the stub `dtk`, no MCP servers, zero hooks.
5. `grade.py` reads the `stream-json` trace and checks each expectation: a skill called (min/max),
   a Bash command matched, or call A before call B. A run is **INVALID** (excluded from the
   pass rate, listed) when the harness broke it: no result event, or a stub skill returned an error.

### Why not `claude plugin eval`

It was the first thing tried, and it does not fit: only the plugin under test loads, so the personal
`ship` (the one that actually failed) is invisible; a stub `gh` on the agent's `PATH` is not a
documented pattern; and the Bash sandbox has no network, so the PR and CI state a pipeline needs
cannot be simulated. The custom harness follows `skills/review-peer/evals`.

## What this does not cover

- **Invocation, not quality.** The trace proves `review-local` was called, not that its real
  findings were good. The stubs reply with zero findings.
- **The skill bodies.** Stubs stand in for the real skills, so this tests ship's orchestration only.
- **`address-review`, `juni-vox` and the other personal skills** the personal `ship` chains after
  step 5. The dispatched cases stop at "CI reported", as the real dispatch does.
- **Sample size.** Runs are small samples from a nondeterministic model: 3/3 or 0/3 is a signal, 2/3
  is noise. Raise `--runs` before drawing a conclusion from one case.
- **Bash is not sandboxed** in these runs (the agent needs real `git`). The cwd is a throwaway repo
  and `gh` is a stub, but treat `--allowed-tools Bash` as what it is.

## Results (2026-10-27)

Sonnet 5.5, 5 runs per case, stub skills. "Before" is each ship without the Delegation contract;
"after" is the version in the tree. `personal` was `~/.claude/skills/ship`, deleted after this run (only `dtk:ship` remains), `dtk` is `dtk:ship`.
Cells are runs that passed, out of 5.

| Expectation | personal before | personal after | dtk before | dtk after |
|---|---|---|---|---|
| **dispatched-pr-only** `review-local` called | 0 | 5 | 0 | 5 |
| `create-pr` called | 0 | 5 | 0 | 5 |
| no raw `gh pr create` before `create-pr` | 0 | 5 | 0 | 5 |
| **dispatched-ci-red** `debug-gh-action` called | 0 | 5 | 0 | 5 |
| **plain-ship** `review-local` called | 3 | 5 | 3 | 5 |
| `smart-commit` called | 3 | 5 | 4 | 5 |
| `create-pr` called | 4 | 5 | 4 | 5 |
| `report-back` called | 0 | 4 | 2 | 5 |
| **explicit-skip** named skips obeyed (3 expectations) | 5 | 5 | 5 | 5 |

Every expectation not listed (ship loaded, ordering between skills) passed 5/5 in all four columns.

- **The T580 failure reproduces.** Without the contract, a dispatch prompt with "review the diff
  cold" and "PR title/description per CONTRIBUTING.md" made Sonnet run `ship`, then `gh pr create`
  straight away: no `review-local`, no `create-pr`, and on a red shard no `debug-gh-action`. 10 of 10
  dispatched runs, in both ships. Even a plain "ship isso" skipped a step in about 2 of 5 runs.
- **The contract fixes it.** Every dispatched and plain expectation is 5/5 in both ships, except
  `report-back` in the personal ship (4/5, one run wrote the report by hand).
- **It did not over-harden.** When the user names the steps to skip, ship still obeys, before and after.
- **Cost of the graded runs:** about $3 per column.

### The failure is model-dependent

On the session's default model (Fable 5.1) the same personal `ship` **without** the contract passed
12 of 12 runs (3 per case, 4 cases), so that eval could not tell before from after. Sonnet is where
the shortcut shows up. That fits the incident: Harnu routes `chore`/`feature`/`bug` cards to Sonnet,
and a shipper dispatched for a card is the shape of the T580 run. The transcript does not say which
model ran, so this is consistent with the evidence, not proven.

### Caveats

- The stubs reply instantly, so skipping a skill saves nothing here. A real `review-local` is long,
  which may make the shortcut *more* tempting in production. If a regression slips past this eval,
  run it against the real skills before trusting it.
- 5 runs per cell is a small sample. 5/5 vs 0/5 is a signal; the 4/5 `report-back` is noise-level.
- Only Sonnet 5.5 was run on the full matrix.
