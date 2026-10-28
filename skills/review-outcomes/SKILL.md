---
name: review-outcomes
effort: low
description: "Use to measure how posted code reviews actually land on a repo: per reviewer and per tag (Q / CR / FFT / NIT), how many comments were posted, accepted by the author, resolved only by the merge, marked wrong, hedged, and how many CRs were posted as REQUEST_CHANGES — each with an explicit, reproducible definition. Reads the last N PRs through the GitHub CLI and renders a compact table plus a 3-line read. Triggers on 'how are my reviews doing', 'review metrics', 'review outcomes', 'taxa de falso positivo', 'quantos comentários foram aceitos', 'métricas de review', 'did the tone changes work', 'are my reviews being accepted', or a request to rerun the review baseline. Do NOT use to run a review (review, review-local, review-peer), to read or answer one PR's comments (address-review), or to post a review (review-publish)."
---

# Review Outcomes

Answers one question with numbers: what happened to the comments this reviewer
posted? Every number comes from `outcomes.py`, and every metric has one written
signal in [`docs/review-outcomes.md`](../../docs/review-outcomes.md#definitions).
Read that section before explaining a number; do not improvise a definition.

## Step 0: Resolve Scripts

```bash
SCRIPTS="bin/skill-scripts"; [ -d "$SCRIPTS" ] || SCRIPTS="${CLAUDE_PLUGIN_ROOT:-}/bin/skill-scripts"; [ -d "$SCRIPTS" ] || SCRIPTS=$(find ~/.claude/plugins -path "*/dtk/bin/skill-scripts" -maxdepth 5 2>/dev/null | head -1); echo "$SCRIPTS"
```

Use the output path as `$SCRIPTS`.

## Inputs

- Repo as `owner/repo`. If not given, take it from `gh repo view --json nameWithOwner -q .nameWithOwner`.
- Reviewer login: `--reviewer <login>`. If not given, ask for it once, or use the authenticated user (`gh api user -q .login`) when the question says "my reviews".
- Window: `--limit 50` by default; `--since YYYY-MM-DD` to measure only reviews posted after a change (the tone skill, a new lesson set).

## Run

```bash
python3 $SCRIPTS/review/outcomes.py owner/repo --limit 50 --reviewer <login> --json
```

Needs `gh` already authenticated; nothing is posted or written. A 50-PR run takes
1–2 minutes: say so before starting. A `gh` failure or an empty reviewer is
reported as it came, never filled in from memory.

## The metrics

Full definitions, edge cases and the JSON shape are in
[`docs/review-outcomes.md`](../../docs/review-outcomes.md#definitions). Summary:

| Metric | JSON key | Signal | Status |
|---|---|---|---|
| posted | `posted` | first comment of a review thread by someone other than the PR author | measured |
| refuted-by-verifier | `refuted_by_verifier` | finding the verifier returned `refuted` before posting | not measured yet |
| accepted | `accepted` | author reply with `good catch` / `done` / `fixed` / `added` / a commit sha, no decline marker winning | measured by reply text; suggestion-applied and resolved-with-a-change not measured yet |
| resolved-by-merge | `resolved_by_merge` | thread on a merged PR the author never answered | measured |
| marked-wrong | `marked_wrong` | author reply starting `wrong:`, containing a thumbs-down, or "not an issue" | measured for replies; reactions not measured yet |
| hedges | `hedges` | comment contains `might be worth`, `maybe` or `could be worth` | measured |
| CR-as-CR | `cr_as_cr` | a `CR:` comment posted under a `CHANGES_REQUESTED` review | measured |

`null` in the JSON means not measured. Print it as `n/m` (not measured), never
as `0`.

## Render

Build the report from the `metrics` block of the JSON, one block per reviewer,
inside one fenced code block. No emoji; columns are plain text so they align on
any font. Use the report-back glyph set (`✓ ✗ ! - ⚑ ?`) only where a marker is
needed, never as decoration.

```
owner/repo · reviewer-a · last 50 PRs
tag        posted  accepted  by-merge  wrong  hedges  CR-as-CR
Q              52        22         4      0      20         -
CR              6         3         0      0       2       0/6
FFT           104        60         2      1      30         -
NIT             1         0         1      0       0         -
untagged        2         0         2      0       4         -
total         165        85         9      1      56       0/6
refuted-by-verifier   n/m (not measured yet)

hedges are 34% of posted; target is 0 (tone lint should hold it there).
0 of 6 CRs went out as REQUEST_CHANGES; target is every CR.
accepted is a floor (strict reply markers); marked-wrong is a lower bound, not a false-positive rate.
```

Layout only: every number above is made up. Real output uses the real JSON, and the read cites real counts.

Rules for the table:

- Columns, in this order: `posted`, `accepted`, `by-merge` (`resolved_by_merge`), `wrong` (`marked_wrong`), `hedges`, `CR-as-CR`. Rows: the tags that have at least one `posted`, then `total`.
- `CR-as-CR` prints `cr_as_cr/posted` on the `CR` row and the total, `-` on every other tag.
- `refuted-by-verifier` is always the line under the table while it is `null`.
- With several reviewers, one block each, blank line between.

Rules for the 3-line read (plain sentences, no bullets, exactly three):

1. The headline: the metric that moved or that is furthest from its target, with its counts.
2. The second-most important gap or win (CR-as-CR and hedges are the two targets in the baseline).
3. The honesty line: which numbers are floors or lower bounds, and what is not measured. When comparing to an earlier run, state that the window (`--limit` / `--since`) matches or does not.

## Do not

- Do not report a false-positive rate. The script has none; `marked_wrong / posted` is a lower bound and a declined or unanswered comment is not a false positive. If the user asks for "taxa de falso positivo", give `marked_wrong` and `declined` separately and say why they are not one number.
- Do not add `resolved_by_merge` to `accepted`.
- Do not compare against the case study's hand-read acceptance; compare strict to strict between runs of the script.
- Do not invent a value for a metric marked `not measured yet`.
