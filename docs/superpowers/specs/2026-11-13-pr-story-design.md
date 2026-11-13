---
status: approved (2026-11-13)
date: 2026-11-13
topic: pr-story, and moving action-brief and its agents into dtk
commit-to: docs/superpowers/specs/2026-11-13-pr-story-design.md (docs-only PR before PR 1)
---

# pr-story: a verified, readable story of what a pull request brought in

## Intent and why

Developers increasingly merge code they did not read line by line: they trust their
teammates, the review skills and agent pipelines. The cost is that they lose track of
what entered the codebase. PR titles say too little, review reports are written for the
author, and PR descriptions are technical templates nobody enjoys reading.

`pr-story` reads a pull request and tells its reader what it brought in, as a short,
pleasant, executive text: why it exists, what changed, what changes for the reader, and
what was left open. Every statement in it is checked against the code, the threads and
the runs, and every page, file, thread or run it mentions is a working link. The reader
should be able to stay current on a codebase by reading stories instead of diffs.

The proving machinery already exists in two personal agents (`claim-verifier`,
`link-finder`) used by a personal skill (`action-brief`). They move into dtk so both
skills share them.

## Goals

- `/dtk:pr-story <PR>` produces one story for one PR, open or merged, in any GitHub repo
  the user can read, with or without a local clone.
- Every factual statement in the story is verified by an independent agent before the
  reader sees it. Statements whose only source is the PR author's own text are kept but
  attributed ("<author> says…").
- Every mention of a file, PR, thread, run, doc or task links to it, and every link was
  checked.
- A weekly (or any date range) digest that tells several PRs as a few arcs, reusing
  stories already generated.
- `action-brief`, `claim-verifier` and `link-finder` live in dtk, shared by any skill.

## Non-goals

- Not a code review. The story does not judge quality or propose fixes; that stays in
  `review-peer` / `review`.
- Not a PR description generator (`create-pr`).
- Never posts anywhere. The story is the reader's own reading material.
- No scheduling in this work. A user can wire the digest to a scheduler later.

## Anti-goals (a technically working result that is still a failure)

- A story that reads well and is wrong. One unverified claim costs more trust than the
  whole skill earns.
- A retelling of the diff file by file. If the reader needs the diff to follow it, it
  failed.
- Fantasy or chronicle styling that makes the reader decode the content. The narrative is
  in the flow of the paragraphs, never in the title.
- A digest that is N full stories pasted one after another.

## Constraints

- **English and white-label.** Every file shipped in dtk (skills, agents, references,
  examples, evals, trigger phrases) is in English and works for any user: no personal or
  client names, no dependency on a personal skill. Harnu and other environment features
  are optional ("when the environment has one"), never required. Evals use public repos.
- **Output language** is English. When the user's prompt asks for another language
  ("tell it in Portuguese"), that story is written in that language. The conversation's
  language alone never changes it.
- **GitHub through `gh`**, authenticated as the running user. Private repos must work, so
  no step may depend on unauthenticated `curl` against github.com.
- **Read-only** against GitHub and the repo. Only the story files are written.
- **CPU courtesy**: parallel agents never exceed half the machine's cores.
- dtk conventions apply: scripts under top-level `scripts/<domain>/` resolved with the
  idiom in `docs/conventions/script-resolution.md`; README tables updated; Conventional
  Commits (releases are automatic).

## Approaches considered

1. **A dtk skill with its own copy of the verifier.** Works for any PR. Duplicates the
   agent that `action-brief` already uses.
2. **A "Story" section inside `review-peer`'s report.** Cheapest, since the review already
   read the diff. Only exists for PRs the user reviewed, and mixes a text for the reader
   with a report written for the author. Fails the main case: PRs nobody reviewed.
3. **A personal skill in `~/.claude/skills`.** Fastest. Outside dtk and its versioning.

**Chosen (by the user):** a variant of 1. `action-brief`, `claim-verifier` and
`link-finder` move into dtk; `pr-story` is a new dtk skill that uses the shared agents.

## Delivery: three PRs, in order

### PR 1: move action-brief and its two agents into dtk

- `skills/action-brief/SKILL.md`, `agents/claim-verifier.md`, `agents/link-finder.md`,
  from the user's personal copies. Inside the plugin they are invoked as
  `dtk:action-brief`, `dtk:claim-verifier`, `dtk:link-finder`.
- White-label pass:
  - `action-brief` description: drop the Portuguese trigger phrases (keep "in any
    language"); `.harnu/out` stays only as an example of an ignored output folder;
    `skill-learn` stays only as "when it is available"; the fallback that loads the agent
    from `~/.claude/agents/<name>.md` points to the plugin's `agents/` folder instead.
  - `claim-verifier`: drop the `rtk proxy curl` example (keep the generic "if a shell hook
    rewrites `curl`, use the raw binary").
  - `link-finder`: links to github.com are checked with `gh` (`gh pr view`,
    `gh api repos/<o>/<r>/contents/<path>?ref=<sha>`, `gh run view`, a review comment by
    id), never with `curl`, because private repos return 404 to an unauthenticated
    request. Found during the smoke test. A link outside GitHub that answers 401/403 or
    redirects to a login page (a private tracker, a private doc) is reported with status
    `auth-required`: it exists but could not be read. It may be kept only when the URL
    was copied verbatim from a primary source (for example the PR body), never when it
    was derived.
- Contract extension for both agents, additive so `action-brief` keeps working:
  - input may carry a context block: `repo` (`owner/name`), `ref` (the sha or branch the
    claims are about) and `clone` (`yes` | `no`). With a ref, the verifier reads code at
    that ref (`git show <ref>:<path>` with a clone, `gh api …/contents/<path>?ref=<ref>`
    without one) instead of the deployed branch;
  - `claim-verifier` output gains `Basis: primary | author-only | indirect`, so a caller
    can tell "the only source is the author's own text" from other `weak` verdicts.
    `action-brief` may ignore it.
- README: new rows for `action-brief` (a new "Communication" table, or the closest existing
  one) and a short paragraph on the two shared agents, next to the existing
  `dtk-review-verifier` paragraph.
- This design document and its plan land on main in a docs-only PR before PR 1
  (`docs/superpowers/specs/2026-11-13-pr-story-design.md`,
  `docs/superpowers/plans/2026-11-13-pr-story.md`).
- **After PR 1 is merged and the new dtk version is installed** (outside the repo, by the
  orchestrating session, user already approved): delete `~/.claude/skills/action-brief/`,
  `~/.claude/agents/claim-verifier.md`, `~/.claude/agents/link-finder.md`, and point the
  user's personal `step-by-step` skill to `dtk:link-finder`. Two installed copies would
  let the model call the stale one.

### PR 2: `/dtk:pr-story <PR>`

**Input.** A PR number (repo from the current directory), `owner/repo#n`, or a PR URL.

**Pipeline.**

1. **Resolve** owner, repo and number; read the PR's state, head sha, merge commit.
2. **Cache.** Look for `~/.local/share/dtk/stories/<owner>/<repo>/PR-<n>.md`
   (`$XDG_DATA_HOME` when set), or `PR-<n>.<lang>.md` when another language was asked
   for. Its frontmatter
   records the head sha it was written from and the language. A story in another
   language is never translated on display: it is a new story, run through the pipeline. Merged PR with a cached story → show it, done. Open PR whose head sha changed →
   regenerate.
3. **Gather facts.** PR body, review threads with replies and resolution, commits, file
   list and diff, linked task, and PRs that reference this one or that it references.
   A large PR (rule of thumb: more than ~1,500 changed lines or ~25 files, builder may
   tune) is read by one fact-gathering subagent that returns a bounded, sourced fact
   sheet: before, what entered, how it works now, decisions with their stated why, what
   changes for a developer, watch items, review discussion. Small PRs are read inline.
4. **Draft** the story in the format below.
5. **Verify.** Extract every factual claim from the draft, batch 3 to 10 claims per
   `dtk:claim-verifier` with the context block (`repo`, `ref` = the PR head sha, or the
   merge commit when merged; `clone`), run the batches in parallel within the CPU cap.
   Act on verdicts:
   - `confirmed` → keep;
   - `wrong` → correct to what is true, or drop;
   - `weak` with `Basis: author-only` → keep, attributed to the
     author ("<author> says…", "according to <author>");
   - `weak` for any other reason → drop, or rephrase to what is proven.
6. **Link.** Every mention gets a link, checked by `dtk:link-finder`. Links pin a commit
   sha (`/blob/<sha>/…`) so they keep pointing at what the story describes. Review threads
   link to the first comment of the thread. An `auth-required` link copied verbatim from
   the PR body (typically the task tracker) is kept; any other unchecked link becomes
   plain text.
7. **Save and deliver.** Write the cache file, then show the story on the best display
   surface the environment offers, in this order:
   1. a rich renderer the session has (a page/artifact publisher, a document viewer
      pane, an editor preview). Published pages stay private to the user unless they
      share them;
   2. otherwise, printed in the conversation.
   The cache path is always given in one line. When a viewer can only open files inside
   the project, a copy may be written into an output folder that git ignores (checked
   with `git check-ignore`), never into a tracked path.

**Story format** (validated in a smoke test on three real PRs):

```
### <Executive title: what changed in the system, present tense, no suspense>

*<Kind> · [PR #n](url) · <author> · <merged on date | open> · <files> files, +<added> · [<task id>](url, when the body links one)*

**Why:** <one line: the problem or need that motivated the PR>

<2 to 6 short paragraphs telling what happened and what entered. Plain words; any
non-obvious term glossed in a short clause the first time. Links on the words the reader
clicks.>

**What changes for you**
- <commands, behaviors, errors the reader will now see, files to touch>

**Left open**
- <unanswered review notes, unconfigured pieces, unmeasured values, known limits;
  each linked to its thread or doc. "Nothing." when nothing.>
```

- Tone: a readable, flowing report (the smoke test's "chronicle" tone), but the title is
  executive. A bulleted "briefing" tone was tested and rejected.
- Length: a small PR fits one screen, a large one two. No hard word cap.
- Reviewer-relative wording: when the running `gh` user reviewed the PR, their notes are
  "your notes"; otherwise "the review notes by <login>".
- Every statement that rests only on the author's word is attributed to the author.

**Hand-off.** `review-peer`'s final step mentions that `/dtk:pr-story <n>` tells the PR as
a story. One line, no behavior change.

**Evals.** A small eval set in `skills/pr-story/evals/` in the shape of `review-peer`'s
(paid, never in CI), on merged PRs of a public repo. Graded properties at least: every
URL resolves (an `auth-required` task link counts as resolved); no claim graded `wrong` by a fresh verifier; author-only claims are
attributed; the four sections exist; the title is not a narrative hook.

### PR 3: the digest

`/dtk:pr-story --since <date|7d> [owner/repo]` or `/dtk:pr-story <n> <n> …`.

1. List the PRs merged in the range (`gh pr list --state merged --search "merged:>=…"`),
   or take the given list.
2. **Tier** each PR: one line (chores, config, dependency bumps), one paragraph (specs and
   docs: what was decided), full story (features, fixes, infra). The builder chooses the
   signals (labels, title prefix, size, files touched).
3. **Group into arcs.** PRs that belong to one thread of work are told together: a
   follow-up fix of a PR in the range, a shared task id, PRs that reference each other.
   Example from the smoke test: an infrastructure PR and the two fixes that followed it
   the same day read as one arc.
4. **Reuse** cached stories in the digest's language (English unless asked); generate the missing full ones with the PR 2 pipeline,
   in parallel within the CPU cap.
5. **Write the digest:** a three-line "this week" header (the headlines), then one section
   per arc, each with its PRs, then the one-liners. Verify the claims that are new in the
   digest (arc framing, one-liners); claims taken from verified stories are not
   re-verified. Save it next to the stories (`…/<owner>/<repo>/digest-<from>-<to>.md`).

## Calls made by the designer, not by the user (check these)

- Cache location `~/.local/share/dtk/stories/…` (per user, never in a repo), one file per
  PR (plus one per extra language asked for). Losing it only costs a regeneration.
- The shared agents get an additive contract (context block in, `Basis` out) in PR 1.
- `auth-required` links are kept only when copied verbatim from a primary source.
- Delivery uses the best display surface available (artifact/page, viewer pane), falling
  back to the conversation; a viewer copy only ever goes into a git-ignored folder.
- The digest is a mode of the same skill, not a second skill.
- Links pin commit shas.
- The large-PR threshold and the tiering signals are left to the builder.
- `review-peer` gets a one-line hand-off; nothing else in existing skills changes.

## Left to the builder

- Exact thresholds (large PR, batch sizes, number of parallel verifiers within the cap).
- Whether claim extraction is a separate step or done while drafting, as long as every
  claim reaches a verifier.
- How the eval grader detects a "narrative hook" title.
- Script support under `scripts/pr-story/` if any step is better as a script (cache
  path, PR resolution).
