# Eval — `dtk-review-verifier`

> Named `README.markdown`, not `README.md`, on purpose: every `*.md` under `agents/` is loaded
> as an agent definition, so a `README.md` here showed up as a bogus `dtk:evals:…:README` agent
> and failed `claude plugin validate --strict .` for missing frontmatter. GitHub still renders it.

The verifier is a binary classifier: one finding in, `real | refuted` out. That makes it a
much harder target to fake than a skill eval — there is no "did the answer feel good"
judgment, just a label to match. This suite is a set of findings with known-correct
verdicts, run against a real git repo the agent has to inspect.

## What it is actually measuring

Two failure modes, and they are not symmetric:

- **Over-pruning** — a real finding refuted. The review silently loses value and nobody
  ever notices, because a suppressed finding leaves no trace. This is the expensive one.
- **Under-pruning** — a false positive kept. The agent becomes a rubber stamp and you are
  back to where you started.

`run.sh` reports each separately at the end instead of collapsing both into a pass rate.

## Running it

```bash
./run.sh                    # every case, on the agent's frontmatter model (sonnet)
./run.sh --model opus       # override the model
./run.sh --case 4,6         # just these
./run.sh --jobs 1           # serialize
./run.sh --keep             # keep the temp repo + raw agent output
./run.sh --agent <path>     # A/B a different verifier definition against the same cases
```

Exit code is 0 only if every case matches. Needs `jq`, `git`, and `claude` on PATH.

## How it works

1. `fixture/before/` and `fixture/after/` are materialized into a throwaway git repo as two
   commits — `main` (baseline) and `feature/orders-invoices` (the change under review). The
   agent therefore has a real diff to reason about, not a description of one.
2. The agent's instructions are extracted from `agents/dtk-review-verifier.md` (frontmatter
   stripped) and injected via `--append-system-prompt-file`. The model comes from the
   frontmatter `model:` line unless `--model` is passed (`inherit` → session default).
3. Each case's finding is sent as the user prompt, in the same shape the review skills use:
   `severity`, `location`, `claim`, `scope`, `empirical`, then `reasoning` last under its own
   `--- reasoning (read only after recording blind_verdict) ---` heading.
4. Tools are `Read`, `Grep`, `Glob` and read-only `git`. A case with `"empirical": "allowed"`
   additionally gets the empirical allowlist (`grep`, `rg`, `php -l`, `node -e`,
   `node --check`, `node --test`, `python3 -c`, `git grep/blame`) — the other cases cannot run
   anything, so the gate's default-off is enforced, not just requested.
5. Scoring reads `final_verdict:` (falling back to a bare `verdict:` so a v1 definition can
   still be A/B-ed with `--agent`), plus whatever the case pins: `expect_suggested_severity`,
   `expect_blind_verdict`, `expect_empirical` (an `empirical:` line with an exit code),
   `expect_reason_contains`.

**What this does not cover:** it runs the agent's instructions directly rather than through
the Task dispatch in the review skills. It verifies the rubric, not the wiring — if a skill
stops dispatching, this suite stays green. In real dispatch the empirical allowlist is a
prompt-level rule (the agent has plain `Bash`); only this harness enforces it with
`--allowed-tools`. It also runs each case once, so a borderline case can flip between runs;
re-run before trusting a single failure.

**Known harness wart:** on a machine with a user-level hook that rewrites shell commands
(e.g. RTK turning `git diff` into `rtk git diff`), the rewritten command no longer matches the
`Bash(git diff:*)` allowlist and `claude -p` denies it. In the v2 runs below the agent said so
in cases 1, 8 and 9 and judged from file reads and `git log` instead. It did not change any
verdict here, but it means the "is this line added by the change" check is weaker than the
harness intends on such machines.

## The fixture

A small Laravel app, deliberately built so each case has exactly one defensible answer:

| Path | Role |
|---|---|
| `app/Http/Controllers/OrderController.php` | changed — adds `index()` with a genuine N+1 |
| `app/Http/Controllers/InvoiceController.php` | new — duplication, a real null risk, a validated field |
| `app/Http/Controllers/UserController.php` | changed — adds SQL injection via `DB::raw()` |
| `app/Http/Middleware/EnsureOrderOwner.php` | unchanged — the authorization the controller "lacks" |
| `routes/web.php` | changed — where the middleware is actually applied |
| `app/Legacy/ReportBuilder.php` | unchanged — a real N+1 that predates the change |
| `app/Support/MoneyFormatter.php` | unchanged — the helper `InvoiceController` duplicates |
| `app/Support/EventRouter.php` | unchanged — builds event classes from runtime strings |
| `app/Events/OrderShipped.php` | changed — constructor now requires an `Order` |
| `app/Models/Customer.php` | unchanged — plain model, no null-safety of its own |
| `app/Observers/CustomerObserver.php` | unchanged — normalizes null → `''` on Eloquent saves |
| `app/Providers/AppServiceProvider.php` | unchanged — wires the observer |
| `database/seeders/LegacyCustomerSeeder.php` | unchanged — writes a null email straight to the table, bypassing the observer entirely |
| `resources/js/money.mjs` | new — `toCents()` rounds with `Math.round`, so the float claim is false |
| `tests/js/money.test.mjs` | new — the one filtered test (`node --test`) that settles case 11 |
| `app/Contracts/InvoiceNotifier.php` | new — an interface with no implementation and no binding anywhere |
| `app/Http/Controllers/InvoiceDispatchController.php` | new — calls `InvoiceNotifier::notify()` inline |

## The cases

| # | Severity | Expected | What it pins down |
|---|---|---|---|
| 1 | blocking | `real` | A concrete defect in added code must survive. Floor test. |
| 2 | blocking | `refuted` | The missing authorization exists as route middleware. |
| 3 | blocking | `refuted` | A real N+1 that the diff never touched — the introduced-by-this-change boundary. |
| 4 | non-blocking | `real` | A duplication claim that's only *partially* true — one path (negative totals) genuinely diverges from the helper. Must survive on the shared core, not be refuted for lacking byte-identity. |
| 5 | non-blocking | `refuted` | N+1 claimed where there is no loop — the premise is false. |
| 6 | question | `real` | A two-hop mitigation exists (an observer defaults null → `''`) but a legacy seeder bypasses it entirely — the invariant asked about is genuinely not guaranteed. |
| 7 | question | `refuted` | Answered by a `validate()` five lines up. |
| 8 | non-blocking | `real` + escalate | SQL injection filed as a style nit — keep it *and* raise the severity. |
| 9 | blocking | `refuted` | Breakage asserted through a runtime-built class name. Unfalsifiable by search. |
| 10 | blocking | `refuted`, blind `refuted` | Anchoring: case 2's claim with confident, specific, false reasoning (a misquoted `routes/web.php:12`, "two other reviewers agree"). The blind phase must refute from the code and Phase B must not flip it. |
| 11 | blocking | `refuted` + `empirical:` | Empirical gate: a float claim one allowlisted command settles; the dispatch opts in and the block must record the command and exit code. |
| 12 | blocking | `refuted`, reason `no-citation` | Citation rule: a runtime-behavior claim (SMTP, synchronous) resting on a method name; the interface has no implementation to cite. |

Cases 4, 6 and 8 exist because of the specific risk in this agent's design: a skeptic tuned
for bugs will happily delete every suggestion and every question, since neither can be
"proven" the way a defect can. Cases 4 and 6 were hardened once (see "Baseline" below) from
an initial version where the duplication was exact and the null risk had zero mitigation —
both too clear-cut to separate this agent from a single-rubric skeptic.

## Baseline (v1)

Sonnet, one run per case, run twice (original cases 4/6, then the hardened versions above):

- `agents/dtk-review-verifier.md` — **9/9 both times**, no over-pruning, no under-pruning.
- Single-rubric control (`transwest-review-verifier`, cases 4-8) — **4/5 both times**. It
  failed only case 8, by not escalating the mis-severed SQL injection, which it has no
  mechanism for.

The control result is worth reading carefully, because it contradicts the reasoning that
originally motivated the severity rubric. Even against the hardened case 6 — a real defect
hidden behind a plausible-looking two-hop mitigation (observer normalizes on save, but a raw
`DB::table()->insert()` seeder bypasses it) — the single-rubric verifier followed the chain,
found the bypass, and correctly kept the question as `real`. Its "default to refuted when
uncertain" instruction never fired, because from its own perspective nothing was uncertain:
it had concrete proof of a gap. The hardened case 4 (partial, not exact, duplication) didn't
separate the two designs either.

So across two rounds of hardening, the demonstrated, reproducible benefit of the per-severity
rubric is **only the escalation path** (case 8) — a single-rubric skeptic has no way to say
"this is real, but mis-labeled," so it either keeps the wrong severity or, in a differently
written variant, might refute a real finding rather than reclassify it. The "a bug-tuned
skeptic silently deletes legitimate suggestions and questions" risk that motivated the rest of
the rubric remains untested: both agents tried here are simply strong enough to reason past
their own default when they find concrete evidence either way. That doesn't mean the risk is
imaginary — a weaker model, a vaguer finding, or a longer evidence chain could still trigger
it — but this suite has not reproduced it, and claiming it has would be overstating the
result. Treat the per-severity rubric as cheap, well-motivated insurance with one proven
benefit (severity correction), not as a fix for a demonstrated defect.

## v2 — blind-first, citation rule, empirical gate, Sonnet critic (2026-10-28)

What changed in the agent: a two-phase method (Phase A judges from `severity + location +
claim + scope` and records `blind_verdict`; Phase B reads `reasoning` and may change the
verdict only on a new fact it verified, recorded in `changed_because`), the `no-citation`
rule for blocking behavior claims, the opt-in empirical gate, and `model: sonnet` in the
frontmatter.

**Why `model: sonnet`.** The review skills run in the session model, which for this repo's
author is Opus, so a pinned Sonnet makes the critic a different model tier from the reviewer
by default (the cross-model critic in Refute-or-Promote, arXiv 2604.19049) and is cheaper per
finding. If your session already runs Sonnet, set it to `opus`. Override per dispatch with the
Task/Agent tool's `model` parameter (it beats the frontmatter), per install by editing the
line, or `inherit` to go back to same-model verification. This suite now runs on the
frontmatter model by default; `--model` overrides it.

**Results.** Sonnet, one run per case.

| Run | Agent | Cases | Result |
|---|---|---|---|
| 0 | v1 | 10, 11, 12 only | **0/3** — the failing-first commit. All three verdicts were already right (`refuted`); every failure is the missing v2 contract (no `blind_verdict`, no `empirical:` line, reason not tagged `no-citation`). |
| 1 | v2, first draft | all 12 | **11/12** — **case 1 over-pruned**: the citation rule refuted a real N+1 as `no-citation` because the fixture has no `Order` model to "prove" the relation is lazy. |
| 2 | v2, citation rule clarified | all 12 | **12/12** — over-pruning 0, under-pruning 0. Blind verdict equalled final verdict in every case. |

Per case in run 2: 1 PASS, 2 PASS, 3 PASS, 4 PASS, 5 PASS, 6 PASS, 7 PASS, 8 PASS (escalated to
`blocking`), 9 PASS, 10 PASS (blind `refuted`, `changed_because` named the misquoted line), 11
PASS (`empirical: node -e '…' → exit 0`), 12 PASS (`no-citation — …`).

Read these results narrowly:

- **The anchoring case did not separate v1 from v2.** v1 also refuted case 10 (run 0); Sonnet
  was not fooled by the persuasive reasoning even without the blind phase. Case 10 now pins the
  two-phase *contract* and guards against a regression, but this suite has not shown that the
  blind phase prevents an anchoring failure that v1 would have made. Same honest status as the
  severity rubric above: well-motivated, not yet demonstrated here.
- **The citation rule was the risky part, and it bit.** Its first wording over-pruned the floor
  case. The fix (the citation is the line where the behavior happens, read with the framework's
  documented semantics; `no-citation` is only for behavior that depends on an unseen body filled
  in from a name) was written after seeing case 1 fail, so case 1 is no longer a blind test of
  it. The example in the agent deliberately does not use the fixture's names. A future case with
  a different real behavior claim would be the honest re-test.
- **Case 11 used `node -e`, not the filtered test.** Both are on the allowlist and the case only
  requires an `empirical:` line with an exit code, so it passes — but nothing here has yet
  exercised `node --test <file>` / `php artisan test --filter` end to end.
- Each figure is one run per case. Two full runs were the token budget for this change.
