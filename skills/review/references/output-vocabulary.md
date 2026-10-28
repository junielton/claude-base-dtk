# Review output vocabulary

The glyphs in `/dtk:review`, `/dtk:review-local`, `/dtk:review-peer` reports and the section
names `/dtk:review-publish` reads. The source of truth for the glyph set and its ban is
`skills/report-back/SKILL.md` ("The glyph vocabulary is frozen"); this file only maps review
concepts onto it and adds nothing to the set. If the two disagree, report-back wins.

Narrow text glyphs only, exactly one space after the marker, no emoji anywhere in a report.

## Severity buckets

| Bucket (review / review-local) | Bucket (review-peer) | Heading marker | Verifier severity | review-publish tag |
|---|---|---|---|---|
| Critical | Blocking | `✗` (red gate) | `blocking` | `CR` |
| Important | Non-blocking | `!` (caveat worth seeing) | `non-blocking` | `FFT` |
| Minor / Suggestion | — | none | `non-blocking` | — |
| — | Questions | `?` (open question) | `question` | `Q` |

Minor / Suggestion carries no marker: the rail has no glyph for "minor", and inventing one is
what the frozen set forbids.

## Verdicts

| Verdict | Marker |
|---|---|
| Approve · Ready to commit/push | `✓` |
| Approve with Comments | `!` |
| Request Changes · Needs fixes first | `✗` |

## Reading a report

A section is identified by its **word** (`Blocking`, `Non-blocking`, `Questions`,
`Recommendation`), never by the marker in front of it. Reports saved before this vocabulary
carry an emoji in that position; they read the same way.
