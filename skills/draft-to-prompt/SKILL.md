---
name: draft-to-prompt
description: Transform a rough idea, voice-note-style draft, or vague request into a production-quality prompt for Claude models (Fable 5, Opus, Sonnet). Use this skill whenever the user shares a messy prompt draft and asks to improve/refine it, asks "help me write a prompt for X", asks which model or technique fits a task, or mentions prompt engineering, prompt refinement, or converting an idea into a prompt — even if they don't say the word "prompt" but are clearly describing a task they want to delegate to an AI model.
---

# Draft to Prompt (v2)

Turn a rough draft into a finished prompt through three phases: **Elicit → Route → Assemble & Critique**. Maintain a visible state block throughout so the user always knows what's decided and what's missing.

The core belief of this skill: the biggest quality lever is not "which technique" but **which model and which prompt shape that model wants**. Techniques are internal vocabulary, not a menu to show the user.

---

## Phase 1 — Elicit

Extract from the user's draft (and conversation history) before asking anything:

- **Goal**: the actual outcome wanted, in one sentence
- **Why**: what the result is for, who consumes it
- **Decided**: constraints, formats, sources already fixed by the user
- **Pending**: decisions that materially change the prompt
- **Inputs needed**: documents, data, research, examples — does the prompt need them attached, or should the target model fetch them?
- **Success criteria**: how the user will judge "this worked"

Then render the state block and keep it updated every turn:

```
## Prompt state
✅ Decided: ...
⏳ Pending (needs user): ...
🔎 Needs research/sources: ...
📎 Inputs to attach: ...
```

Rules for this phase:
- Ask only about pending items that **materially change the prompt**. For everything else, make a sensible assumption and declare it inline ("Assuming X — correct me if wrong"). Never ask more than 2-3 questions per turn.
- If the draft is already complete enough, skip straight to Phase 2 and say so.
- Do not advance to assembly while a critical pending item is open.

## Phase 2 — Route

Pick the target model, then the prompt shape. Decide silently and state the conclusion with a one-line justification — don't lecture about the matrix.

**Choose Fable 5 when** the task is long-horizon, ambiguous, multi-phase, agentic (codebase audits, migrations, deep research, multi-document synthesis), or was previously "too hard". Also recommend effort: `high` default, `xhigh` for the most capability-sensitive work.

**Choose Opus/Sonnet when** the task is short, well-defined, latency-sensitive, high-volume/cost-sensitive, or touches domains that trip Fable's classifiers (offensive security, biology/chemistry) — those fall back to Opus anyway.

**Prompt shape by model:**

| | Fable 5 | Opus / Sonnet |
|---|---|---|
| Structure | Goal + Why + Boundaries + Verification + Output | Role + Context + Task + Constraints + Format |
| Detail level | Direction, not steps. Short instructions, model fills gaps | More explicit steps and edge cases pay off |
| Reasoning | Never ask to show/explain reasoning (triggers `reasoning_extraction` refusal). Adaptive thinking is always on | CoT ("think step by step") still helps on hard problems |
| Examples | Few-shot for format/tone only | Few-shot broadly useful |
| Verification | Explicit self-verification via fresh-context verifier subagent at intervals | Ask for a final self-check pass |
| Scope control | Add "don't add features/refactor/abstract beyond the task" for coding | Usually unnecessary |

## Phase 3 — Assemble & Critique

Write the prompt using the shape from Phase 2, then run the anti-pattern checklist **before** showing it. Fix violations silently; mention only the interesting ones.

### Fable 5 anti-pattern checklist
- [ ] Asks the model to show/explain/output its reasoning or thought process → **remove** (refusal risk). Evidence citations (file + line, source + link) are fine — that's grounding, not chain of thought.
- [ ] Over-prescriptive step-by-step recipe where direction would do → collapse into goal + boundaries.
- [ ] Long-horizon task without a verification instruction → add fresh-context verifier subagent.
- [ ] Claims/findings without an evidence requirement → add "every claim must cite its source/file/session".
- [ ] Coding task without scope boundary → add the no-unrequested-refactor line.
- [ ] Missing "why" → add it; Fable uses purpose to make better judgment calls.
- [ ] Mentions of context budget/limits → remove or add "you have ample context remaining".

### Universal checklist (all models)
- [ ] Output format explicit (structure, length, what leads)?
- [ ] Boundaries stated (what NOT to do)?
- [ ] Inputs referenced by real paths/names, not "the file"?
- [ ] Success criteria expressible? If yes, in the prompt.
- [ ] Anything the target model can't know (dates, internal names, paths) filled in or flagged as `[FILL]`?

### Technique vocabulary (internal — apply, don't name-drop)
- **Few-shot**: the highest-ROI technique for format, tone, and edge-case behavior. Prefer 1-3 tight examples over paragraphs of description.
- **Direction stimulus**: hints, keywords, and constraints inside the prompt. Always cheap, always useful.
- **ReAct**: on modern Claude this is tool/agent design, not prompt phrasing. If the task needs it, recommend tools/subagents instead of writing "reason then act".
- **Manual CoT**: useful on Opus/Sonnet for hard reasoning; harmful on Fable 5 (redundant + refusal risk).
- **Self-consistency / ToT / SoT**: legacy scaffolding. On Fable 5, replace with a verifier subagent or a second review pass. On Opus, use only if the user explicitly wants multi-sample robustness and accepts the cost.
- **Zero-shot / in-context instruction**: the default; only worth mentioning when the user asks why no examples were included.

## Output format

Deliver in this order:
1. Updated **Prompt state** block (only if items are still pending; omit when everything is resolved)
2. The final prompt in a single fenced code block, ready to paste
3. A short "what I changed and why" — max 4-5 bullets in prose, tied to the routing decision
4. Run instructions: target model, effort level (if Fable), and anything to fill in before running

If critical items are still pending, deliver the best current draft anyway, with `[FILL: ...]` markers, and list the open questions after it. Never hold the draft hostage to questions.

## Examples

**Example 1 — routing:**
Input: "quero um prompt pro Claude auditar meu repo inteiro, achar código duplicado e coisas pela metade, e montar um backlog"
Route: Fable 5, xhigh. Long-horizon + ambiguous + codebase-wide.
Shape: Goal/Why/Boundaries ("analyze and propose only, don't modify code"; evidence = file+line for every finding) + verifier subagent + ordered backlog output.

**Example 2 — routing:**
Input: "prompt pra transformar release notes em post de LinkedIn, vou rodar toda semana"
Route: Sonnet. Short, repeatable, cost-sensitive.
Shape: Role + task + 2 few-shot examples of past posts (ask user for them → goes to 📎 Inputs) + format constraints (length, tone, no hashtags spam).

**Example 3 — anti-pattern fix:**
Draft contains: "explique seu raciocínio passo a passo antes da resposta final"
Target: Fable 5 → replace with "cite the evidence behind each conclusion (source + location)". Tell the user why in one line.
