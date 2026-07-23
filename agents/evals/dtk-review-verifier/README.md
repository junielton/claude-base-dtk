# Eval — `dtk-review-verifier`

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
./run.sh                    # every case
./run.sh --model opus       # pin a model (default: session default)
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
   stripped) and injected via `--append-system-prompt-file`.
3. Each case's finding is sent as the user prompt, in the same shape the review skills use.
4. The returned `verdict:` (and `suggested-severity:` where the case expects one) is compared
   to the label.

**What this does not cover:** it runs the agent's instructions directly rather than through
the Task dispatch in the review skills. It verifies the rubric, not the wiring — if a skill
stops dispatching, this suite stays green. It also runs each case once, so a borderline case
can flip between runs; re-run before trusting a single failure.

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

Cases 4, 6 and 8 exist because of the specific risk in this agent's design: a skeptic tuned
for bugs will happily delete every suggestion and every question, since neither can be
"proven" the way a defect can. Cases 4 and 6 were hardened once (see "Baseline" below) from
an initial version where the duplication was exact and the null risk had zero mitigation —
both too clear-cut to separate this agent from a single-rubric skeptic.

## Baseline

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
