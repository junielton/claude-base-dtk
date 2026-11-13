# Eval: `pr-story`

`pr-story` tells what a pull request brought in, and its whole value is that the story is
**true** and **usable**. This eval runs the skill end to end on two merged PRs of a public
repo and grades the story it saved.

## The two cases

| id | PR | why it is here |
|----|----|----------------|
| `small` | [`junielton/claude-base-dtk#28`](https://github.com/junielton/claude-base-dtk/pull/28) | 2 files, read inline. Its body states what was and was not run, so there are claims only the author backs. |
| `large` | [`junielton/claude-base-dtk#24`](https://github.com/junielton/claude-base-dtk/pull/24) | 32 files, over the 25-file threshold, so the skill must use the fact-gathering subagent. |

Both are merged, so the story is cached for good and a run is reproducible: `cases.json`
pins each PR's merge commit as the `ref` the grader's verifier reads.

## What is graded

For each run, on the story the skill saved in the run's own (empty) cache:

1. **gate**: `scripts/pr-story/check-story.sh` exits 0 (frontmatter, executive title, meta
   line, **Why**, the two closing sections in order, pinned file links, no bare URLs).
2. **links**: every `github.com` link in the story resolves through `gh` (a PR, a file at a
   sha, a review comment, a run). A 404 fails the run. A link to a shape the grader does not
   know is listed as a note, not failed. Links outside GitHub are not fetched here; an
   `auth-required` task link copied from the PR body counts as resolved.
3. **verifier**: a fresh `claim-verifier` (a new `claude -p` with the agent's own
   instructions, a `Context:` block at the merge commit, `clone: no`) checks up to 8 sentences
   sampled from the story. Any `wrong` fails the run. The sample is seeded by the PR number, so
   it is the same sample for every run of a case.
4. **author**: every sampled sentence the verifier marks `Basis: author-only` names the PR
   author in that sentence ("junielton says…"), so a claim that rests on the author's word is
   never stated as fact.

For `large`, the grader also prints whether the transcript shows a fact-gathering subagent
(any subagent other than `claim-verifier` and `link-finder`). That line is a note, not a grade.

The "title is not a narrative hook" property is the gate's `title` rule (no `?`, `!` or
ellipsis), so it is covered by check 1.

## Running it

```bash
bash skills/pr-story/evals/run.sh --runs 1            # both cases, one run each
bash skills/pr-story/evals/run.sh --case small        # one case, 3 runs
bash skills/pr-story/evals/run.sh --runs 1 --model opus
bash skills/pr-story/evals/run.sh --runs 1 --keep     # keep stories and transcripts
```

It calls the Claude CLI several times per run (the skill, its verifiers and link finder, then
the grader's verifier), so it costs tokens: run it when `skills/pr-story/SKILL.md` or the
agents it depends on change. It is never part of CI. Needs `claude`, `gh` (signed in), `jq`,
`git` and `python3`, plus network access. `--jobs` defaults to 1 and is refused above half
the cores.

Each run uses its own `XDG_DATA_HOME`, so your real story cache is never read or written.
Exit code is 0 only when every run passes all four checks.
