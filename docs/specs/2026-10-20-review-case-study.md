# Case study: how reviews actually happen on transwest-web and summit-bodyworks-web

> **Correction, 2026-10-20.** An adversarial pass recomputed the numbers from the raw threads and refuted sections 4–7. The verified corrections are in section 8; read that first. Sections 1–3 stand. Sections 4–7 are kept as the record of what was wrong.

Last 50 PRs of each repo, pulled 2026-10-20 via GraphQL (reviews, inline threads, thread resolution, commits). Scripts and raw JSON in the session scratchpad (`tw.json`, `sbw.json`, `analyze.py`).

## 1. The two repos are mirror images

| | transwest-web | summit-bodyworks-web |
|---|---|---|
| PR author | dberri 49, junielton 1 | junielton 48, dberri 2 |
| Reviewer | junielton (+ Copilot) | dberri (+ Copilot) |
| Reviewer verdicts | APPROVE 63 · COMMENT 16 · **CHANGES_REQUESTED 0** | APPROVE 46 · COMMENT 7 · **CHANGES_REQUESTED 3** |
| Human inline threads | 168 | 66 |
| Threads per reviewed PR | mean 4.2, max 16 | mean 1.9, max 5 |
| PR size, median (add+del) | 945 | 642 |
| Copilot threads | 16 (10 led to a change) | 76 (52 led to a change) |

So this is a clean A/B: junielton reviewing dberri on one repo, dberri reviewing junielton on the other, same taxonomy, same two people.

## 2. Tag distribution per reviewer

| Tag | junielton @ transwest | dberri @ summit |
|---|---|---|
| CR | 6 (4%) | 3 (5%) |
| FFT | 104 (63%) | 38 (67%) |
| NIT | 1 | **13 (23%)** |
| Q | 52 (32%) | 3 (5%) |
| untagged | 2 | 0 |

Two things stand out.

**The CR rate is the same for both reviewers (4–5%).** dberri, the tech lead, is not more aggressive with CR than the skill is. His three CRs are all demonstrable defects: a Filament `in` rule that fails on unpublished ids, a loose `toEqual` that lets `null`/`false` drift pass in a parity fixture, `afterCommit` callbacks running before `DB::transaction()` returns. Junielton's six are the same shape: an architecture test that fails, a video that restarts on `seekTo(0)`, `defer()` never running without the middleware, a removed enum case that fatals a factory, a test suite CI never discovers, a panel raised while inactive.

**The lead uses NIT, and uses it a lot (23%). He almost never uses Q (5%).** Junielton has the inverse profile: 32% Q, one NIT in 168 threads. That is the single biggest structural difference between the two reviewers.

## 3. What each tag means in practice, from the lead's own usage

Derived from reading all 13 NITs, all 3 CRs and 15 of 38 FFTs by dberri.

- **CR** — a wrong result the reviewer can demonstrate in the diff. Blocks approval (he posts CHANGES_REQUESTED with an empty body; the inline carries everything).
- **NIT** — a small, concrete, *correct* fix with an obvious patch: a stale docblock, a `proposed` status that should be `accepted`, a tracking query string in a config URL, a missing `finally` restore, an enum instead of a literal, two identical helpers. Often shipped as a `suggestion` block. Not a learning point, a cleanup.
- **FFT** — a reasoned risk or design point where the author decides: a test that "stays green if the anchor stops rendering", a hard-coded generator key in a generic component, a Livewire state that lets a crafted update bypass `in()`, `fail-fast: true` cancelling shards. Several of these describe real defects, and he still tags them FFT.
- **Q** — rare. A genuine question about intent or history ("did the v1 table ever reach staging?").

So in the team's actual practice **FFT is not only "learning". It is "I see a risk, your call."** The lead files real defects as FFT when they are not a wrong result he can show on the diff today.

## 4. Do FFTs get acted on? Yes, most of them

"Acted on" = the thread is marked outdated by GitHub, meaning the author changed the lines the comment sits on.

| | resolved | acted on (outdated) | author replied |
|---|---|---|---|
| junielton FFT (n=104) | 93 | **49 (47%)** | 96 |
| dberri FFT (n=38) | 37 | **25 (66%)** | 36 |
| dberri NIT (n=13) | 13 | **12 (92%)** | 12 |
| junielton Q (n=52) | 46 | 14 (27%) | 46 |
| all CR (n=9) | 9 | 4 | 9 |

Half of junielton's FFTs and two thirds of dberri's get a code change at that exact spot. The "acted on" rate for CR is actually *lower* (4/9), because a CR is often answered by a change elsewhere (middleware, a different file).

The point for the taxonomy: **an FFT is already a soft request in this team. The author treats it as "fix unless I disagree".** That is what the lead's NITs are too, at 92%. Nobody is ignoring FFTs; the complaint "too much lands in FFT" is about the label, not about the outcome.

## 5. What is inside junielton's 104 FFTs

Keyword classification over the full body (rough, but the samples below are read by hand):

| nature | n | acted on |
|---|---|---|
| defect / risk (throws, never runs, stays green, overrides, restart…) | 18 | 7 |
| convention / refactor (lesson, helper, naming, `tests/Functions`) | 11 | 9 |
| test gap (not covered, missing dataset row) | 5 | 0 |
| other (design, docs, wording, wiring) | 70 | 33 |

Hand-read examples that would be CR under the lead's own CR definition (a wrong result, demonstrable):

- #3983 "the stamp gets saved before offers and disclaimers are written. If that part throws, the product is already visible" — acted on.
- #4002 "`??=` makes the query `makes` win over the path make, but the live page does the opposite" — acted on.
- #4013 "client `partition_id` wins over the search's own, and the beacon accepts any int, so rollups grow per made-up partition" — acted on.
- #3982 "`release()` consumes an attempt, five rate-limit releases end in `failed()` and strike every product in the batch" — **not** acted on.
- #4011 "the `finally` also clears the flag when the reconcile returns FAILURE, so the dropdown goes back to a half-filled collection" — not acted on.
- #4021 "`aria-label` overrides the visible 'Saved', WCAG 2.5.3" — not acted on.

The three "not acted on" ones are exactly the cost of the under-label: a demonstrated defect posted as "food for thought" was read as optional.

Examples that are genuinely FFT by anyone's definition: `HeaderNavBuilder` → `HeaderNavBuilderInterface` naming, moving helpers to `tests/Functions`, a footnote about an enum case that does not exist yet, a small helper on `CTSVDealer` to keep two checks in sync.

And the 52 Qs: 45 are not questions about intent, they are hedged findings ("does Typesense accept `q=*` with the embedding field? A 4xx would flip to degraded…", "the floated label overhangs by 13.6px, so 14px clears it by a hair"). The lead would file most of these as FFT or NIT. This is the "ask a question when uncertain" rule in review-peer producing Qs out of risks.

## 6. What this says about the proposal

1. **"Widen CR to rule violations" is not what the lead does, and the data does not support it.** His CR rate equals the skill's. Convention misses are NIT or FFT for him, never CR. A CR definition broader than "demonstrable wrong result" would make junielton's reviews stricter than the tech lead's on the same codebase. That is the wrong direction socially.

2. **The real gap is a missing middle tag, and the team already has it: NIT.** The lead uses it for 1 in 4 comments. It is in the team's taxonomy in practice even if juni-vox calls Q/CR/FFT "locked". Adding NIT to the skill is adopting the lead's convention, not inventing one.

3. **The under-label that costs something is defect → FFT and defect → Q.** About 18 FFTs and 6 Qs in 50 PRs describe a wrong result. Under the lead's usage those are CR when demonstrable on the diff (he has 3 in 50 PRs, so a handful, not dozens), and FFT when they depend on runtime (latency, a browser, a queue). The verifier's "not run in a browser, so non-blocking" demotion is therefore half right: the lead also files runtime-dependent risks as FFT. The fix is narrower than "remove the demotion": a defect whose mechanism is fully visible in the code (sync `showModal()` vs async round trip) is CR; one that needs a measurement to confirm stays FFT.

4. **Q is overused by 5×.** 52 vs 3. Most should become FFT (reasoned risk) or NIT (concrete fix). A Q should only be a question about intent or history that the code cannot answer.

5. **Volume, not severity, is the other asymmetry.** 4.2 threads per PR vs 1.9, max 16 vs 5. The lead's reviews are shorter and 66% of his FFTs land. Junielton's 16-thread review on one PR is where FFTs get skimmed. A cap at the publish gate (ranked, rest kept in the report) is justified by the data.

## 7. Recommended taxonomy, calibrated to the lead

| Tag | Rule | Blocks? | Expected rate |
|---|---|---|---|
| **CR** | A wrong result demonstrable from the diff and the code it touches. No runtime measurement needed to see it. | Yes (COMMENT + no approval, or CHANGES_REQUESTED as the lead does) | ~5% |
| **NIT** | A small, correct fix with an obvious patch. Stale doc, literal → enum, duplicate helper, missing restore. Ship a `suggestion` block when possible. | No, but expected to be taken | ~20% |
| **FFT** | A reasoned risk or design alternative where the author decides. Includes defects that depend on runtime to confirm. | No | ~60% |
| **Q** | A question about intent or history the code cannot answer. Never a hedged finding. | No | ~5% |

Pipeline changes this implies (replacing the earlier "widen CR" proposal):

- review-peer: four buckets (🔴 CR, 🟠 NIT, 🟡 FFT, 💬 Q). The "ask a question when uncertain" rule applies only to intent; a hedged finding is an FFT. Delete the step-8 hint that tells the reviewer non-blocking survives verification more easily.
- verifier: for `blocking`, the test is "mechanism fully visible in code", not "proven at runtime". Runtime-dependent → `real` + `suggested-severity: non-blocking`. Add a `nit` band: premise true and the fix is a local patch.
- review-publish: NIT row in the tag table; CR bodies name what unblocks and never carry "feel free to ignore"; at the gate pre-check CR + NIT + top 3 FFT by risk, keep the rest in the report under "Not posted".
- juni-vox: taxonomy becomes Q / CR / NIT / FFT, matching the lead.

Lesson severity (Critical/High/Medium/Low) maps to NIT or FFT, never CR on its own: the lead does not CR a convention miss, and neither should the skill.

## 8. Correction after adversarial review (verified against the raw threads)

### What was wrong in sections 4–7

1. **`isOutdated` is a bad proxy for "acted on".** Classifying the author's *reply* instead: ~80/104 of junielton's FFTs were accepted (77%), 11 declined with a reason, 8 no reply (most on PRs still open). `isOutdated` said 47% because fixes often land in another file, and 30 of the 65 outdated threads sit on rebased branches. dberri's FFTs: 36/38 accepted. The real gap is 95% vs 77%, and both are "FFT works as a request".
2. **The three "cost of the under-label" examples were misread.** #4011 (`finally` clears on FAILURE): fixed, "Good call, thanks!". #4021 (aria-label): fixed, "Nice catch, thanks!". #3982 (`release()` burns an attempt): refuted by the author on Laravel internals, "Keeping this one. `$maxExceptions` only counts unhandled exceptions". **There is no FFT in 50 PRs that the author agreed was a real defect and then dropped.**
3. **The keyword classifier (18 defect / 11 convention / 5 test / 70 other) is not reproducible.** Hand-reading, ~40 of the 104 FFTs describe a wrong result with a mechanism. 32 accepted, 3 ticketed, 3 declined because the finding was wrong, 4 pending on open PRs.
4. **NIT is a four-day habit, not the team taxonomy.** All 13 of dberri's NITs are dated 2026-10-07 to 10-09; zero before, zero on transwest. His FFTs span 09-24 to 10-13. Five NIT/FFT pairs are indistinguishable (same PR, same kind of fix, different tag). Acceptance is the same (92% vs 95%).
5. **CR parity means nothing at n=6 and n=3** (Wilson 95%: 1.6–7.6% vs 1.8–14.4%). What does differ: dberri posts CRs as **CHANGES_REQUESTED** and 3/3 landed; junielton posts them under **COMMENT** (0 CHANGES_REQUESTED in 50 PRs) and **2/6 were refused and merged over** (#3987 "Not for this PR", #3989 "stale review").
6. **"Mechanism visible in code → CR" does not work.** It demotes #4009 (YouTube `seekTo(0)` restarts, a runtime/third-party semantic, real bug, fixed) and promotes #3982 and #4021-Pennant (visible-looking mechanism, wrong). Applied to dberri it turns ~15/38 of his FFTs into CRs (#261 "entrypoint never runs `db:seed`, header renders empty on prod" is tagged FFT). The current verifier bar, prove the defect or refute, is what catches the wrong ones.
7. **Qs are the most productive tag**: 31/52 led to a change (60%), and 8 were answered "intended / client asked", exactly where an FFT would have been a wrong assertion.
8. **The volume cap would cut good findings.** Per review round (30-min grouping) junielton's mean is 3.1, max 9; the "16-thread PR" is 10 days and 2+ rounds. A top-3 cap would have dropped ~13 of ~32 accepted FFTs in big rounds, including #4000 "`@push` into a `@yield` renders nothing". Normalised by PR size the lead comments **twice as densely** (0.44 vs 0.22 threads per KLOC); the 4.2 vs 1.9 per-PR gap is a PR-size artefact (741 KLOC vs 130 KLOC reviewed).
9. **Copilot is not taking the nits on summit.** Its 76 threads come from `.github/copilot-instructions.md` and are High/Medium findings; dberri overlaps on 19 (pr, path) pairs and says "agree with Copilot" 3 times. Nothing to skip.

### The gap the data does show

| | junielton @ transwest (n=165) | dberri @ summit (n=57) |
|---|---|---|
| "might be worth / maybe / could be worth" | **56** | 0 |
| "feel free to ignore / fine to leave / totally optional" | **9** | 0 |
| `suggestion` blocks | 0 | **12** |
| "I'd …" | 0 | **19** |
| CR posted as CHANGES_REQUESTED | 0/6 | 3/3 |
| CR refused and merged over | 2/6 | 0/3 |

The reviews find the same things and get nearly the same acceptance. The difference is **tone and verdict**, not taxonomy: the lead states what he would do and ships the patch; the pipeline hedges and marks its own findings optional. And a CR posted under COMMENT is a request the author can decline.

### Corrected recommendation

Keep Q / CR / FFT. Do not add NIT. Do not widen CR. Do not cap volume. Change four things:

1. **CR posts as `CHANGES_REQUESTED`**, as the lead does. The inline carries the content; the verdict carries the block. (`review-publish` step 2.)
2. **Strip hedging from every body.** Ban "might be worth", "maybe", "could be worth", "feel free to ignore", "totally optional", "fine to leave". Write "I'd …" + the reason. Keep the humble register in the *reason*, not in the ask. (`review-publish` step 3 banned list; `juni-vox` review section.)
3. **Ship `suggestion` blocks** whenever the fix is a local patch, the way 12 of the lead's 57 comments do. (`review-publish` step 3, new rule; `post-review.sh` already posts multi-line bodies.)
4. **Delete the step-8 hint** in `review-peer` ("the verifier demands proof for blocking, only checks premise for non-blocking"). It leaks the rubric into the reviewer's choice. The verifier's proof bar for blocking stays.

Lesson severity never maps to CR by itself: the only convention-based CR in 50 PRs (#3987, test directory) was refused and merged over.
