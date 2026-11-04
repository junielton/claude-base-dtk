# Spec: reviewer alerts in `create-pr`, TL;DR in `review-peer`

Date: 2026-11-02 · Repo: `junielton/claude-base-dtk` (the `dtk` plugin) · Branch: `feat/pr-alerts-review-tldr`
Evidence: `bythepixel/cooling-tower-depot#314`, reviewed with `/dtk:review-peer` → `/dtk:review-publish` on 2026-10-28.

## Problem

PR #314 added a CI step that runs every shard's test suite a second time on every pull
request. The author wrote the cost in the body ("about 1.5 to 6 minutes per shard") and wrote
"Not run on GitHub: the new step itself" under the AI Assistance heading. The review read all
of it, found three code-level notes, and the reviewer approved. A teammate caught the cost
with their own eyes the next day.

Two gaps, one on each side:

1. `create-pr` fills the template section by section and has no notion of "this is what the
   reviewer must see". A cost sits in a bullet list next to "Not touched: `.github`"; a
   "not tested" sits under a heading nobody reads.
2. `review-peer` has three buckets: Blocking, Non-blocking, Question. A cost, a risk, a claim
   the diff does not support or a declared gap is not a bug, so it never becomes a finding,
   and the gate in `review-publish` shows the verdict and the inline comments only.

## Changes

### 1. `create-pr`: alerts for the reviewer

A new block in Step 4, after the description is drafted and before the push. From the diff,
the commits and what the author said in the session, write GitHub alerts
(`> [!CAUTION]`, `> [!WARNING]`, `> [!IMPORTANT]`, `> [!NOTE]`) for what the reviewer must
weigh:

| Type | Trigger |
|---|---|
| `CAUTION` | irreversible or dangerous: a migration that drops or rewrites data, a deleted or skipped test, a change to auth, permissions, secrets or environment |
| `WARNING` | a cost or risk the reviewer decides on: CI time or a job that runs more often, a behaviour change users will see, a dependency bump, a performance trade-off, a public interface changed |
| `IMPORTANT` | not done or not proven: anything not run on CI, scope left out on purpose, a follow-up the merge depends on |
| `NOTE` | context with no risk: new identifiers, where to start reading |

Rules:

- At most 4 alerts, `CAUTION` and `WARNING` first. One or two sentences each: the concrete
  fact (number, file, duration), then what the reviewer should check or decide.
- Every alert is backed by the diff or by what the author said. No alert to fill a slot;
  with nothing to flag, none is written.
- A "not run", "not tested", "did not time it" sentence anywhere in the body also gets an
  `IMPORTANT`, so it never stays buried under a heading nobody reads.
- They go at the top of the template section that fits, matched on the header
  (case-insensitive): first `reviewer|review notes|where to look|onde olhar|impacted|areas|attention|risk`, else the first body section (Description, Summary, Contexto). Never a new section, never inside `<details>`, in the template's language.

### 2. `review-peer`: a TL;DR and a pass for critical facts

A new pass, 4b "Collect critical facts", after the analysis and before memory. It reads, in
order: the alerts the author wrote in the body; CI and infra files in the diff (workflows,
migrations, cron, queues, env); destructive or sensitive changes (deleted or skipped tests,
auth, secrets, dependency bumps, public interfaces); claims in the body that the diff does not
support and any "not run / not tested" sentence wherever it sits; files outside what the
title says. Each fact cites its source (`file:line` or the body sentence).

The report gets a `## TL;DR` section right after `## Recommendation`: one sentence on what the
PR does in plain words, then 2 to 5 lines, `✗` for a critical fact (irreversible, or a cost
the reviewer must accept), `!` for attention. Concrete fact first, then why it matters,
readable by a manager and a developer alike. With nothing critical, one line says so and why.

A fact that needs the author's answer also becomes a `? Question` finding and goes through
the verifier like any other; the TL;DR itself is not a finding and is never verified.

### 3. `review-publish`: the TL;DR above the gate

The TL;DR is read from the report and printed verbatim in the transcript right above the draft
and the `AskUserQuestion` gate. It never enters the payload: `tone-lint.sh` gains a
`tldr-leak` rule that refuses a body or a comment containing `TL;DR`.

## Non-goals

- `/dtk:review` and `/dtk:review-local` (the user's own PRs) are unchanged.
- The shared `references/workflow.md` is unchanged; the new pass lives in `review-peer` only.
- No change to what reaches GitHub from the review, beyond Questions that already existed as a bucket.

## Acceptance

- AC-1 On PR #314's body, `create-pr` would have written a `WARNING` for the CI cost and an
  `IMPORTANT` for "not run on GitHub", inside "Impacted Areas (Where)".
- AC-2 `review-peer` on #314 produces a TL;DR whose lines name the doubled CI time with the
  author's numbers and the unproven step, each with its source.
- AC-3 `review-publish` prints that TL;DR above the gate and `tone-lint.sh` refuses a payload
  whose body or comment contains `TL;DR`.
- AC-4 `bash skills/review-publish/tests/run-tests.sh` passes; `grade.py` still parses a
  report that carries the TL;DR section.
