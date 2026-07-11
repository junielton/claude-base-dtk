# Harness routing — facts, citations, and boot templates

Read this when Phase 2b picks a harness, or when you need the documented mechanics
behind the "Model mechanics" section of SKILL.md.

## Documented facts (verified 2026-07-11)

### Session model — who controls it

The session model is controlled ONLY by: the `/model` slash command (user gesture),
the `--model` CLI flag at launch, the `ANTHROPIC_MODEL` environment variable, or the
`model` key in settings.json. Prompt text has no authority over it.
→ https://code.claude.com/docs/en/model-config.md ("Setting your model")

Consequence for generated prompts: model choice lives in the RUN INSTRUCTIONS
(how to boot/switch), never as an instruction inside the prompt body.

### Subagent model — resolution order

1. `CLAUDE_CODE_SUBAGENT_MODEL` environment variable (if set)
2. Per-invocation `model` parameter on the Agent tool call
3. Agent definition frontmatter `model` field — valid values: `haiku`, `sonnet`,
   `opus`, `fable`, a full model id (e.g. `claude-opus-4-8`), or `inherit`;
   omitted = `inherit`
4. The main conversation's model (the default fallback)

Built-in agents (Explore, Plan, general-purpose) inherit; Explore is capped at Opus
on the Claude API (a Fable parent gets Opus Explore agents).
→ https://code.claude.com/docs/en/sub-agents.md ("Choose a model")

Consequences:
- Fable/Opus session fanning out = every subagent bills at the parent's rate unless
  pinned down. Generated prompts for big-model sessions that will spawn workers MUST
  pin cheaper models per call ("spawn the sweep agents with model: haiku").
- A cheap session can spawn one targeted expensive subagent for the hard core —
  often the best cost/quality shape ("Sonnet session + one Opus subagent").

### Slash commands vs. skills-as-tools

A slash command is only recognized at the START of a user message; text inside a
prompt ("then run /loop 10m") does not self-execute.
→ https://code.claude.com/docs/en/commands.md

But skills ARE invocable by the model through the Skill tool, unless the skill sets
`disable-model-invocation: true`. So boot prompts should phrase harness bootstrapping
as tool instructions: "invoke the loop skill", "invoke the goal skill with
`set <objective>`" — not as bare slash text. Alternative: when the boot mechanism
pastes a literal user message (Capy prePrompt, `claude -p`), the message may simply
START with the slash command.

### Pricing snapshot (per MTok in/out — re-verify occasionally)

| Model | Input | Output |
|---|---|---|
| Haiku 4.5 | $1 | $5 |
| Sonnet 5 | $3 | $15 (intro $2/$10 through 2026-08-31) |
| Opus 4.8 | $5 | $25 |
| Fable 5 | $10 | $50 |

→ https://platform.claude.com/docs/en/about-claude/models/overview

Effort levels don't change per-token price — higher effort spends MORE tokens.
Docs do not publish effort-tier pricing; treat effort as a smaller cost lever
inside the model choice.

## The mission stack — boot-prompt template

Use when the task is multi-executor coordination with gates/approvals that must
survive interruptions. The three pieces and why each exists:

- **orchestrator skill** — enters the coordination-only contract (the session plans
  and delegates; never touches product code). Without it the coordinator drifts
  into implementing.
- **goal skill** — `set <objective>` persists mission state to a file
  (`.capy/GOAL.md` or equivalent); every tick reads it, acts on what's unblocked,
  updates it. The file is the thread that survives compaction and restarts.
- **loop skill** — self-paced re-invocation drives the ticks. Without it the
  mission stalls the moment the turn ends.

Template block to embed in the generated boot prompt (adapt the bracketed parts):

```
Execution harness — set this up before any dispatching:
1. Invoke the orchestrator skill and stay inside its contract for the whole
   mission: you coordinate and verify; executors implement.
2. Invoke the goal skill with: set [one-sentence mission objective, the executors
   you'll dispatch, the done-criteria, the gates where the operator must decide].
3. Invoke the loop skill (self-paced) to drive goal ticks until done-criteria are
   met, then close with goal done and stop the loop.
Pin executor/subagent models explicitly when you dispatch: [e.g. workers on
sonnet, file sweeps on haiku]. Escalate a single subagent to a bigger model only
when its specific task demonstrably needs it.
```

Availability check: before prescribing this stack, confirm the skills exist in the
target session's available-skills list (they may be personal/user-level skills). If
they don't, generate the equivalent inline: instruct a persistent state file with
the mission's executors/gates/log + a self-scheduled check cadence, and say
explicitly that the named skills were unavailable so the user can install them.

## Calibration examples (harness axis)

- "resume os últimos 20 commits" → none. One sitting, one output.
- "fica de olho no deploy e me avisa se quebrar" → /loop alone, interval matched to
  how fast the deploy state changes.
- "coordena 4 executores em worktrees até a feature fechar, me chama nos gates" →
  the full mission stack.
- "troca a cor do botão" → none, and Haiku low. If you're reaching for the
  orchestrator here, you've mistaken ceremony for rigor.
