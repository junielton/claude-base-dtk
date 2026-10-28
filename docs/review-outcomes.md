# Review outcomes

How reviews posted through `/dtk:review-peer` → `/dtk:review-publish` behave in production: tone (hedges, `suggestion` blocks), verdicts, and whether the author accepted the comment. Produced by `bin/skill-scripts/review/outcomes.py`; background and the reasoning behind the four tone changes are in [`specs/2026-10-20-review-case-study.md`](specs/2026-10-20-review-case-study.md) §8 and [`specs/2026-10-20-review-tone-and-evals.md`](specs/2026-10-20-review-tone-and-evals.md).

## Run it

```bash
python3 bin/skill-scripts/review/outcomes.py owner/repo --limit 50 [--since YYYY-MM-DD] [--reviewer login] [--json]
python3 bin/skill-scripts/review/outcomes.py --self-test   # offline check of the classifiers
```

Python 3 stdlib plus `gh` (already logged in with `gh auth login`). No token is read or stored. It reads the most recent `--limit` PRs of any state, one GraphQL query per PR (reviews, review threads with comments, commits). The full 50-PR run takes about 1–2 minutes per repo.

How it counts:

- **Comment** = the first comment of a review thread, written by someone other than the PR author. The tag is the leading `Q:` / `CR:` / `FFT:` / `NIT:`; anything else is `untagged`.
- **Hedges** = comments containing `might be worth`, `maybe` or `could be worth`. **Marked optional** = `feel free to ignore`, `totally optional`, `take it or leave it`, `fine to leave`, `not a big deal` or `just a thought` (the case study's 9 are the first three of these). Both lists are the banned list of the tone spec, Changes 2.
- **CR as CHANGES_REQUESTED** = CR comments whose own review has that state, over all CR comments.
- **Acceptance** comes from the PR author's reply text, not from `isOutdated` (fixes often land in another file, and rebased branches mark threads outdated). `accepted`: "good catch", "done", "fixed", "added", or a 7-hex sha. `declined`: "keeping", "intended", "not for this PR", "already". Declined wins inside one reply; the last reply carrying a marker decides the thread. A thread on an open PR with no reply is `pending`, not `no reply`.
- `agreed (opener only)` is an addition to the spec's marker list: a reply that opens with "Good call", "Nice catch", "Agreed", "Makes sense", "Yeah", etc. and names no marker. It is a loose signal, kept in its own column so the strict numbers stay the spec's.

## Definitions

Each metric below is one signal, spelled out, so two people running the script on the same PRs get the same number. No review vendor publishes neutral, reproducible definitions (Signal65's comparison is vendor-commissioned; Cursor counts an unresolved comment as a false positive), which is why they are written down here. `--json` emits exactly these keys under `metrics`, per reviewer (`total`) and per tag (`by_tag`: `Q`, `CR`, `FFT`, `NIT`, `untagged`); a metric the script cannot measure is `null`, never a guess.

| Metric | JSON key | Exact signal | Status |
|---|---|---|---|
| posted | `posted` | First comment of a review thread, written by someone other than the PR author, over the last `--limit` PRs of any state. The tag is the leading `Q:` / `CR:` / `FFT:` / `NIT:`, else `untagged`. | measured |
| refuted-by-verifier | `refuted_by_verifier` | A finding `dtk-review-verifier` returned as `refuted` before anything was posted. A refuted finding never reaches GitHub, so nothing in the PR data carries it. | not measured yet (always `null`; needs the review report to persist verifier verdicts) |
| accepted | `accepted` | Intended: a suggestion applied, or the thread resolved by the author with a change. Measured today: the last author reply carrying a marker has `good catch`, `done`, `fixed`, `added` or a 7-hex commit sha, and no declined marker (`keeping`, `intended`, `not for this PR`, `already`) won. The looser "agreed" opener ("Good call", "Makes sense") is not counted here; it stays in `outcomes.<tag>.agreed`. | measured by reply text; suggestion applied and resolved-by-author-with-a-change are not measured yet (the query does not read who resolved a thread or whether a suggestion commit landed) |
| resolved-by-merge | `resolved_by_merge` | Thread on a `MERGED` PR where the author never replied. Weak by design: the merge shows the comment did not block, not that it was addressed or ignored. Never added to `accepted`. Unanswered threads on open or closed-unmerged PRs are not counted. | measured |
| marked-wrong | `marked_wrong` | Thread where any author reply starts with a `wrong:` tag, contains a thumbs-down emoji, or contains "not an issue" (case-insensitive). | measured for replies; a thumbs-down reaction on the comment is not measured yet (reactions are not fetched) |
| hedges | `hedges` | First comment contains `might be worth`, `maybe` or `could be worth`. The optional-marker phrases (`feel free to ignore`, ...) stay in the separate `optional` key. | measured |
| CR-as-CR | `cr_as_cr` | A `CR:` comment whose own review state is `CHANGES_REQUESTED` (GitHub's request-changes). Always 0 on non-CR tags; the rate is `cr_as_cr` over `posted` of tag `CR`. | measured |

Reading them honestly:

- There is no false-positive rate here. `marked_wrong` over `posted` is a lower bound: only comments the author explicitly called wrong. A declined comment (`declined` in the acceptance table) or an unanswered one is not a false positive, it is a disagreement or silence.
- `accepted` over `posted` is a floor for the same reason: fixes without a marker word land in `other reply`, and threads on open PRs are `pending`.
- Compare strict to strict between runs; the metrics are only comparable when `--limit` and `--since` match.

JSON shape (existing keys `comments`, `hedges`, `optional`, `suggestions`, `cr_verdicts`, `verdicts`, `outcomes` are unchanged; the new block is added per reviewer):

```json
{
  "reviewer-a": {
    "metrics": {
      "total": { "posted": 0, "refuted_by_verifier": null, "accepted": 0, "resolved_by_merge": 0, "marked_wrong": 0, "hedges": 0, "cr_as_cr": 0 },
      "by_tag": { "Q": {}, "CR": {}, "FFT": {}, "NIT": {}, "untagged": {} },
      "not_measured": ["refuted_by_verifier"]
    }
  }
}
```

Every `by_tag` entry has the same seven keys as `total`.

## Baseline, 2026-10-20 (before the tone changes)

Last 50 PRs of each repo, read 2026-10-20. Reviewer verdict names are GitHub's (`APPROVED`, `COMMENTED`, `CHANGES_REQUESTED`).

### owner/repo-a, reviewer `reviewer-a`

```bash
python3 bin/skill-scripts/review/outcomes.py owner/repo-a --limit 50 --reviewer reviewer-a
```

#### reviewer-a  (n=165 inline comments)

| Tag | Comments |
|---|---|
| Q | 52 |
| CR | 6 |
| FFT | 104 |
| NIT | 1 |
| untagged | 2 |

| Metric | Count |
|---|---|
| hedges (might be worth / maybe / could be worth) | 56 |
| marked optional (feel free to ignore / fine to leave / totally optional / ...) | 9 |
| `suggestion` blocks | 0 |
| CR posted as CHANGES_REQUESTED | 0/6 |
| review verdicts | APPROVED 63, COMMENTED 15 |

Acceptance by the author's reply (open PRs without a reply are `pending`, not `no reply`):

| Tag | n | accepted | declined | agreed (opener only) | other reply | no reply | pending (open PR) | accepted % of n | accepted+agreed % of n |
|---|---|---|---|---|---|---|---|---|---|
| Q | 52 | 22 | 10 | 3 | 11 | 4 | 2 | 42% | 48% |
| CR | 6 | 3 | 1 | 1 | 1 | 0 | 0 | 50% | 67% |
| FFT | 104 | 60 | 5 | 17 | 14 | 2 | 6 | 58% | 74% |
| NIT | 1 | 0 | 0 | 0 | 0 | 1 | 0 | 0% | 0% |
| untagged | 2 | 0 | 0 | 0 | 0 | 2 | 0 | 0% | 0% |


### owner/repo-b, reviewer `reviewer-b` (the human reference)

```bash
python3 bin/skill-scripts/review/outcomes.py owner/repo-b --limit 50 --reviewer reviewer-b
```

#### reviewer-b  (n=57 inline comments)

| Tag | Comments |
|---|---|
| Q | 3 |
| CR | 3 |
| FFT | 38 |
| NIT | 13 |
| untagged | 0 |

| Metric | Count |
|---|---|
| hedges (might be worth / maybe / could be worth) | 0 |
| marked optional (feel free to ignore / fine to leave / totally optional / ...) | 0 |
| `suggestion` blocks | 12 |
| CR posted as CHANGES_REQUESTED | 3/3 |
| review verdicts | APPROVED 46, CHANGES_REQUESTED 3, COMMENTED 4 |

Acceptance by the author's reply (open PRs without a reply are `pending`, not `no reply`):

| Tag | n | accepted | declined | agreed (opener only) | other reply | no reply | pending (open PR) | accepted % of n | accepted+agreed % of n |
|---|---|---|---|---|---|---|---|---|---|
| Q | 3 | 0 | 2 | 0 | 1 | 0 | 0 | 0% | 0% |
| CR | 3 | 2 | 0 | 1 | 0 | 0 | 0 | 67% | 100% |
| FFT | 38 | 19 | 3 | 15 | 1 | 0 | 0 | 50% | 89% |
| NIT | 13 | 9 | 0 | 3 | 1 | 0 | 0 | 69% | 92% |


### Reading the baseline

| | reviewer-a @ repo-a | reviewer-b @ repo-b |
|---|---|---|
| hedges | **56** | 0 |
| marked optional | **9** | 0 |
| `suggestion` blocks | 0 | **12** |
| CR as CHANGES_REQUESTED | 0/6 | 3/3 |

These match the case study §8 table exactly (hedge 56, optional 9, suggestion 0 / 12, CR 0/6 / 3/3; tag counts 52/6/104/1/2 and 3/3/38/13/0). The target for the new skill: hedges, optional → 0, `suggestion` blocks > 0, every CR under `CHANGES_REQUESTED`.

Caveats when comparing:

- The case study's hand-read acceptance (~80 of 104 FFTs, 77%) is higher than the script's strict markers (60 of 104, 58%; 74% with the `agreed` opener column). Many authors answer "Good call, thanks! It now …" without any marker word. Compare strict to strict between runs; do not compare the script to the hand count.
- The case study counts 16 `COMMENT` reviews on repo-a; the script reads 15 `COMMENTED`. The script ignores reviews written by the PR author and `PENDING` ones. Tags, hedges and CR numbers are not affected.
- Threads on PRs still open when the baseline ran are `pending`; they shift into accepted/declined in a later run, so acceptance for the newest PRs is a floor.
- Small n: 6 CRs on repo-a, 3 on repo-b. Read CR rates as counts, not percentages.

## When to rerun

After about 10 reviews have been posted with the new skill (tone lint, `REQUEST_CHANGES` for a CR, `suggestion` blocks), rerun both commands with `--since <date the new skill shipped>`, so the old reviews do not dilute the numbers, and add the result below under a dated heading. Expected movement: hedges and optional at 0 (the lint enforces it, so anything else is a bug), `suggestion` blocks above 0, CR as CHANGES_REQUESTED at N/N, and the share of CRs declined by the author down from 2/6. Acceptance should hold or improve; if it drops while hedges are gone, the direct tone is costing something and the spec's Changes 2 needs another look.
