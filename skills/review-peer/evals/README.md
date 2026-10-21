# Eval — `review-peer` severity labeling

`review-peer` step 8 used to end with a sentence that leaked the verifier's rubric into the
reviewer's choice of bucket: *"Send the severity you actually intend to post: the verifier
demands proof for `blocking`, but only checks the factual premise for `non-blocking` /
`question`."* The spec (`docs/specs/2026-10-20-review-tone-and-evals.md`, change 4) deletes it.
This eval measures where known findings land, with and without that sentence, so the deletion
is a measured change instead of a hunch.

## What it measures

For a diff with known answers, which severity bucket (🔴 / 🟡 / 💬) the reviewer puts each
finding in. Not whether it finds things: whether it **labels** them the way the code deserves.

| # | Finding | Expected bucket |
|---|---|---|
| 1 | SQL injection in `UserController` (`DB::raw` on the query string) | 🔴 blocking |
| 2 | N+1 on `warehouse` in the loop added to `OrderController::index` | 🟡 non-blocking (see Decision) |
| 3 | `InvoiceController` re-implements `MoneyFormatter` | 🟡 non-blocking |
| 4 | N+1 in `ReportBuilder` (predates the change) | absent |
| 5 | "missing authorization in `show()`" (the route middleware covers it) | absent or 💬 |

Anything else the reviewer raises is printed as *unlabeled* and not graded.

## Running it

```bash
./run.sh                    # 5 runs against skills/review-peer/SKILL.md
./run.sh --runs 3           # fewer runs
./run.sh --skill <path>     # A/B another SKILL.md (e.g. a pre-edit snapshot)
./run.sh --model opus       # pin a model (default: session default, not pinned)
./run.sh --keep             # keep the temp repo, the system prompt and the raw reports
```

Needs `jq`, `git`, `python3` and `claude` on PATH. Exit code is 0 only if every run matches
every expectation. The header prints `hint: PRESENT | absent` by grepping the skill under test,
so a table can never be attributed to the wrong variant.

## How it works

1. `agents/evals/dtk-review-verifier/fixture/` (read-only, shared with the verifier eval) is
   materialized into a throwaway repo: `main` (baseline) and `feature/orders-invoices` (the change).
2. The system prompt is built from the skill file under test: step 4 (analysis passes), step 8
   (verification rules, where the hint lives), the report template from step 9 and the
   Severity Definitions. The GitHub-collection step is replaced by
   `git diff main...feature/orders-invoices`, which `run.sh` runs itself and passes in the user
   message (see "Harness notes").
3. `claude -p` writes the report; `grade.py` parses the `## 🔴 / 🟡 / 💬` sections into
   `###` findings, matches each expectation (`cases.json`: file + keywords on the heading or
   the whole finding) and prints the bucket per run.

**Step 8 is included on purpose.** The hint lives in the verification rules, so a prompt that
stopped at step 4 could not tell the two variants apart. The verifier itself is not dispatched
(the prompt says to write the report as it would read after step 8): this measures the
reviewer's *labeling*, which is what the hint influences, not the verifier's verdicts (that is
`agents/evals/dtk-review-verifier`).

**What this does not cover:** the rubric, not the wiring. It does not collect a PR through the
GitHub MCP, run `review-publish`, load memory or lessons, or dispatch the verifier. Runs are
small samples from a nondeterministic model: a 5/5 or 0/5 is a signal, a 3/5 is noise.

### Harness notes

- The first attempt let the model run `git diff` itself. In the nested `claude -p` session the
  Bash call was denied in 4 of 5 runs (a command-rewriting hook defeats the allowlist) and the
  reviewer fell back to reading whole files. Those runs were discarded; the diff is now
  collected by `run.sh`.

## Results

Model: session default (not pinned). Fixture: the verifier fixture, unchanged.

### Baseline — hint present (`SKILL.md` as of `6a4095b`), 5 runs

| Finding | Expected | run1 | run2 | run3 | run4 | run5 | Pass |
|---|---|---|---|---|---|---|---|
| SQL injection, `UserController` | 🔴 | 🔴 | 🔴 | 🔴 | 🔴 | 🔴 | 5/5 |
| N+1 in added loop, `OrderController::index` | 🟡 | 🟡 | 🟡 | 🟡 | 🟡 | 🟡 | 5/5 |
| `MoneyFormatter` duplication | 🟡 | 🟡 | 🟡 | 🟡 | 🟡 | 🟡 | 5/5 |
| Pre-existing N+1, `ReportBuilder` | absent | absent | absent | absent | absent | absent | 5/5 |
| Missing authorization in `show()` | absent / 💬 | absent | absent | absent | absent | absent | 5/5 |

With the hint, every expectation holds. The added-loop N+1 was filed as 🟡 non-blocking in
every run; the spec's first version expected 🔴 for it (see Decision below). Every run also
raised the same unlabeled 🔴 (invoice routes lack an ownership check, `routes/web.php`), which
the fixture does not label.

### After — hint deleted (`SKILL.md` at `6753220`), 5 runs

| Finding | Expected | run1 | run2 | run3 | run4 | run5 | Pass |
|---|---|---|---|---|---|---|---|
| SQL injection, `UserController` | 🔴 | 🔴 | 🔴 | 🔴 | 🔴 | 🔴 | 5/5 |
| N+1 in added loop, `OrderController::index` | 🟡 | 🟡 | 🟡 | 🟡 | 🟡 | 🟡 | 5/5 |
| `MoneyFormatter` duplication | 🟡 | 🟡 | 🟡 | 🟡 | 🟡 | 🟡 | 5/5 |
| Pre-existing N+1, `ReportBuilder` | absent | absent | absent | absent | absent | absent | 5/5 |
| Missing authorization in `show()` | absent / 💬 | absent | absent | absent | absent | absent | 5/5 |

### Did the deletion move anything?

No. With the hint and without it, every expectation produced the same bucket in all 5 runs:
SQL injection 🔴, the added-loop N+1 and the duplication 🟡, the pre-existing N+1 and the
`show()` authorization finding absent. At this sample size (5 + 5, one model, one fixture)
there is no measurable effect, in either direction. The deletion stays because the spec argues
it on principle (it leaks the verifier's rubric into labeling), not because the numbers asked
for it.

### Decision — the N+1 expectation (2026-10-20)

The first version of this eval expected 🔴 for the added-loop N+1, and the row failed 10 of 10
runs with and without the hint: the reviewer files it as 🟡 every time. The 🔴 came from the
verifier eval (`agents/evals/dtk-review-verifier`), where case 1 is *submitted* as `blocking`
to check that the verifier keeps a concrete finding; that eval never asserted 🔴 is the right
label. Under the skill's Severity Definitions, 🔴 is a bug, a security issue or a breaking
change, and an N+1 returns the correct result, so 🟡 is the label the definitions actually
give it. That is also what the 100-PR case study (`docs/specs/2026-10-20-review-case-study.md`
§8) found: a CR is a demonstrable wrong result, and the tech lead files performance notes as
FFT.

The operator changed the expectation to 🟡 on 2026-10-20 and the spec (§U2 AC-2) was amended
with this rationale. The tables above are the original runs, unchanged; only the Expected
column and the Pass counts follow the new expectation. The Severity Definitions were not
edited. Confirming run after the change, `./run.sh --runs 1` (hint absent, session default
model): `sql-injection-user-search 1/1 · n-plus-one-added-loop 1/1 · money-formatter-duplication
1/1 · pre-existing-n-plus-one 1/1 · missing-authorization-in-show 1/1`, exit 0.
