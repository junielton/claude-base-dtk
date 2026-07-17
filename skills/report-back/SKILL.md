---
name: report-back
effort: low
description: "The shared final-report format for any multi-step run: a ✅/⏭️/❌ checklist (one line per executed step, with concrete outcomes) plus a summary of at most 3 lines. Use it whenever a task involved a pipeline or several sequential steps and you're about to write the wrap-up message — shipping a PR, reconciling branches, a deploy, a batch of file changes, a scaffold — or whenever the user asks 'what did you do?', 'give me the summary', 'where's the report?', or complains a final summary was a wall of prose. Other pipeline skills (e.g. `/dtk:ship`) reference this as their output contract. Do NOT use for simple Q&A — a question gets a direct answer, not a checklist."
---

# Report Back (final-report format)

The last message of a multi-step run is usually read by someone who walked away
while it ran. They don't want the story; they want to scan what happened, spot
the one thing that needs them, and move on. So the checklist IS the report —
prose only gets the 3 summary lines at the end.

## The format

```
✅ review-local: 2 safe fixes applied
✅ commit + push: 3 commits on ABC-231-fix-avatar-cache
✅ PR #142 opened → https://github.com/org/repo/pull/142
⏭️ reviewers: already assigned on the existing PR
✅ CI green (12 checks)
❌ review: 1 comment needs a product decision (retry config)

Shipped the avatar-cache fix as PR #142; CI is green.
One blocking comment about the retry config needs your call.
Everything else is resolved and replied to.
```

## Line rules

- **One line per step that was in the plan**, in execution order.
- **✅** step ran and succeeded. **⏭️** step skipped (say why in a few words).
  **❌** step failed or hit a red gate (one concrete reason). **⚠️** done, but
  with a caveat worth seeing.
- Each line carries a **concrete outcome**, not a restatement of the step name:
  counts, branch names, PR numbers, URLs, file paths. "✅ commit" says nothing;
  "✅ commit + push: 3 commits on ABC-231" is scannable evidence.
- A run that stopped early still lists the remaining steps — as ⏭️ with
  "stopped before this" — so the reader sees what did NOT happen.

## Summary rules

- **At most 3 lines**, below the checklist, in plain sentences.
- Line 1: what shipped / what the run produced. Then, only if needed: what still
  needs the user, and any caveat that changes what they'd do next.
- If a ❌ stopped the run, the summary's job is to say exactly what decision or
  fix is needed to resume.

## Scope

This format is for **multi-step work**: pipelines, batches, scaffolds, anything
where several actions ran and the user needs the trace. A simple question gets a
direct answer in prose — a checklist there is noise, and noise is exactly what
this format exists to kill.

## For other skills

A pipeline skill that wants this as its output contract just says "end the run
with a `/dtk:report-back` final report" in its finish step — don't re-specify the
format inline (it drifts). The checklist lines should mirror that skill's own
pipeline steps.
