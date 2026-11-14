---
pr: junielton/claude-base-dtk#28
head_sha: add2d2d9df06478c740363cce28891fad091cc6f
lang: en
generated_at: 2026-11-13T18:00:00Z
merged: true
---

### What happens after a rebase finishes?

*Feature · [PR #28](https://github.com/junielton/claude-base-dtk/pull/28) · junielton · merged on 2026-11-09 · 2 files, +85*

**Why:** The skill used to stop after the rebase, so the reader still had to push by hand and watch the pipeline.

The skill now finishes what it starts. After a rebase it pushes the branch with `--force-with-lease` (a push that refuses to overwrite commits someone else added), then watches the checks on the pull request, as [step 7 and step 8](https://github.com/junielton/claude-base-dtk/blob/2f3a3a8a4ab5a0809b7045754bffddf8ffbce2ad/skills/git-rebase-onto/SKILL.md) of the skill describe.

A new step 0 asks whether the branch needs a rebase at all and stops when it has no conflicts and is already up to date.

**What changes for you**
- `/dtk:git-rebase-onto` pushes by default; `no-push` opts out, and the old `push` argument is accepted and ignored.

**Left open**
- junielton says the skill evals and the new CI-follow step were not run against a real pull request.
