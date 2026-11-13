# Eval: `claim-verifier`

> Named `README.markdown`, not `README.md`, on purpose: every `*.md` under `agents/` is loaded
> as an agent definition, so a `README.md` here fails `claude plugin validate --strict .` for
> missing frontmatter. GitHub still renders it. Same reason as `../dtk-review-verifier/`.

The verifier returns a verdict (`confirmed | wrong | weak`) and, since the shared-agent
contract, a `Basis` (`primary | author-only | indirect`). Callers such as `pr-story` rely on
the pair: a `weak` claim whose basis is `author-only` is kept and attributed to the author,
any other `weak` claim is dropped. This eval checks that the agent tells those apart.

## The three cases

All three are claims about one merged public PR,
[`junielton/claude-base-dtk#28`](https://github.com/junielton/claude-base-dtk/pull/28),
read at its merge commit (`ref` in `cases.json`). Each was checked by hand against the
skill file and the PR text at that ref before it was committed.

| id | claim is about | label |
|----|----------------|-------|
| c1 | the publish step skips the force-push on a default or protected branch (step 7) | `confirmed` / `primary` |
| c2 | step 8 stops after 5 fix cycles on one check (the file says 3) | `wrong` / `primary` |
| c3 | the PR author ran `claude plugin validate --strict .` before opening the PR (only the PR body says so) | `weak` / `author-only` |

The batch is sent with a `Context:` block (`repo`, `ref`, `clone: no`) from an empty working
directory, so the agent has to read through `gh`, which is the path private repos need.

## Running it

```bash
bash agents/evals/claim-verifier/run.sh --runs 1     # one run, agent's frontmatter model
bash agents/evals/claim-verifier/run.sh --runs 3 --model opus
bash agents/evals/claim-verifier/run.sh --keep       # keep raw outputs
```

It calls the Claude CLI, so it costs tokens: run it only when you change
`agents/claim-verifier.md` or the contract callers depend on. It is never part of CI. It
needs `claude`, `gh` (signed in), `jq` and `python3`, plus network access. `--jobs` defaults
to 1; keep any parallelism under half the machine's cores.

Exit code is 0 only when every run matches every label.

## If a case fails

First decide whether the case is ambiguous. If two careful readers could label it
differently, fix the case (the claim or its label), never the grader. If the case is clear
and the agent is wrong, fix `agents/claim-verifier.md`.

## Files

- `cases.json`: the context, the claims and their labels, each with a `why`.
- `run.sh`: builds the payload, runs `claude -p` with the agent body as system prompt.
- `grade.py`: parses each `### <id>:` block and compares verdict and `Basis`.
