---
name: pr-story
description: >-
  Tell what a pull request brought in as a short, verified, readable story: why it
  exists, what changed, what changes for the reader and what was left open. Every
  statement is checked against the code, the review threads and the runs by an
  independent claim-verifier agent, and every file, PR, thread or run it mentions is a
  link that was checked. Works on open or merged PRs, with or without a local clone,
  and keeps a per-user cache so a merged PR is told once. With a date range or several
  PRs it writes a digest: a three-line header, then the PRs grouped into a few arcs.
  Use it when the user asks "tell me what this PR brought in", "story of PR #n", "what
  did #n change", "explain this PR without the diff", "what landed in #n", "what merged
  this week", "digest of the last 14 days", or pastes a PR URL with that intent, in any
  language. Do NOT use it to review a PR and give feedback (review-peer, review), or to
  write a PR description (create-pr).
argument-hint: "[PR number | owner/repo#n | PR URL] [optional: language]  |  --since <YYYY-MM-DD|Nd> [owner/repo] [language]  |  <ref> <ref> …"
---

# PR story: $ARGUMENTS

A reader who trusts their team and their review pipeline still loses track of what
entered the codebase. PR titles say too little and descriptions are templates. This
skill reads a pull request and tells it: what it is for, what changed, what changes for
the reader, what is still open. Short, plain, pleasant, and **proven**.

Two failures matter:

- **A story that reads well and is wrong.** One unverified claim costs more trust than the
  whole skill earns. Nothing reaches the reader before a verifier has tried to disprove it.
- **A retelling of the diff.** If the reader needs the diff to follow the story, it failed.
  The narrative lives in the flow of the paragraphs, never in a dramatic title.

Not a code review: the story never judges quality or proposes fixes. Not a PR description.
Read-only: the only things written are the cache files and, for a viewer, one copy in a
git-ignored folder. It never posts anywhere.

**Which mode.** One PR (a number, `owner/repo#n` or a URL) is the pipeline below. A range
(`--since <YYYY-MM-DD|Nd> [owner/repo] [language]`) or two or more PR references
(`<ref> <ref> …`) is the **digest mode**, after the pipeline: its steps reuse it.

## Step 0: Resolve scripts

```bash
# resolver idiom: docs/conventions/script-resolution.md
SCRIPTS="${CLAUDE_PLUGIN_ROOT}/scripts"; [ -d "$SCRIPTS" ] || echo "dtk: scripts dir not found: $SCRIPTS" >&2; echo "$SCRIPTS"
```

Use the output path as `$SCRIPTS` for all script commands below. If it printed
`dtk: scripts dir not found`, stop and tell the user the plugin did not load; do not guess.

GitHub is read through `gh`, signed in as the running user, so private repos work. Never
use unauthenticated `curl` against github.com (a private repo answers 404). Needs `gh`,
`jq`, `git`.

**Language.** The story is in English. It is written in another language only when the
user's prompt asks for it ("tell it in Portuguese", or the second argument). The language
the user chats in never switches it. Use the two-letter code (`pt`, `es`, `fr`) for the
cache and the `lang:` field; English is `en`.

## The pipeline

### 1. Resolve

```bash
"$SCRIPTS/pr-story/story-target.sh" "<first argument>"
```

It prints `{"owner","repo","number"}` (a bare number uses the current directory's GitHub
repo) and exits 2 with a message when it cannot tell which PR is meant: pass that message
to the user and ask for `owner/repo#n`. Then read the PR's state:

```bash
gh pr view <n> -R <owner>/<repo> --json number,title,state,url,author,body,baseRefName,baseRefOid,headRefOid,mergeCommit,mergedAt,additions,deletions,changedFiles
```

`ref` for everything below is `headRefOid`, or `mergeCommit.oid` when the PR is merged.

### 2. Cache

```bash
CACHE="$("$SCRIPTS/pr-story/story-cache.sh" path <owner> <repo> <n> [lang])"
"$SCRIPTS/pr-story/story-cache.sh" status "$CACHE" <headRefOid>
```

- Merged PR whose cache file exists and whose frontmatter says `merged: true`: show it
  (step 7, delivery) and stop. No agent is spawned.
- Open PR: `fresh` means the head sha is unchanged, so show it; `stale` or `missing` means
  regenerate. An open PR that gained commits must never be served from the old file.
- A cached story written while the PR was open (`merged: false`) is regenerated once the PR
  is merged.
- A story in another language is a separate file, never a translation on display: it runs
  through the whole pipeline.

### 3. Gather the facts

Collect, with `gh` only:

- the PR body, commits, file list and diff (`gh pr view --json commits,files`,
  `gh pr diff`);
- review threads with replies and resolution
  (`gh api graphql` on `pullRequest.reviewThreads`: `isResolved`, and each comment's
  `databaseId`, `author.login`, `body`, `url`), plus the PR's issue comments and reviews;
- the linked task, when the body links one (keep its URL exactly as written);
- PRs that reference this one or that it references, and CI runs that matter
  (`gh pr checks`).

**Large PRs.** When the PR has more than **1,500 changed lines** (additions plus deletions)
or more than **25 files**, do not read it inline: spawn one fact-gathering subagent
(`general-purpose`) and give it the repo, the number, `ref` and the list above. It returns a
bounded fact sheet of at most about 1,200 words, every fact followed by its source (a path
at the sha, a commit, a comment URL), in exactly these seven sections:

1. Before: how things worked before the PR.
2. What entered: the new or changed pieces, by purpose rather than by file.
3. How it works now: the mechanism in a few sentences.
4. Decisions, each with the reason the PR or the thread states for it.
5. What changes for a developer: commands, behaviors, errors, files to touch.
6. Watch items: risks, untested parts, unconfigured pieces, values nobody measured.
7. Review discussion: open and resolved threads, who said what, with links.

Draft from that sheet. Smaller PRs are read inline.

### 4. Draft

Write the story in the format below, in plain words. Gloss any non-obvious term in a short
clause the first time it appears. Tell what happened and what entered, not file by file.
A small PR fits one screen, a large one two; there is no word cap.

- **Tone:** a readable, flowing report. The title is executive (what changed in the system,
  present tense, no suspense, never ending in `?`, `!` or an ellipsis); a bulleted
  "briefing" body reads worse and is not the format.
- **Attribution:** every statement that rests only on the author's word is attributed to
  them ("<author> says…", "according to <author>").
- **Reviewer-relative wording:** read `gh api user --jq .login`. When that user reviewed the
  PR, their notes are "your notes"; otherwise write "the review notes by <login>".
- Facts that come straight from the API (author, date, file count, line count, state) are
  copied from the `gh` output, not retyped from memory.

**Story format:**

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

### 5. Verify

Walk the draft sentence by sentence and extract **every factual sentence as a claim**: what
the code does now, what a command accepts, what a thread decided, what a run showed, what the
PR says it did or did not test. Nothing is exempt:

- the **Why** line, every paragraph and every bullet of **What changes for you**;
- **every `Left open` bullet**, whatever its source;
- **every "<author> says…" or "according to <author>" sentence**. Attribution does not make a
  sentence true: it is a claim about what the author wrote, so the verifier must read the
  author's text (the PR body, a comment) and confirm it says exactly that, and nothing more
  or less (a "not re-run" that the body limits to one part is `wrong`).

Only sentences with no checkable fact (pure transitions) and the meta line, whose figures are
copied from the `gh` output, are skipped.

Number the claims `c1`, `c2`, … Write each as one sentence that would read the same in the
story, with hints for where to look (path, PR, thread url). Do not say what you expect the
answer to be.

Batch **3 to 10 claims per `dtk:claim-verifier`**, never more than 10 in one batch: when there
are more claims, send more batches, not a bigger one (`subagent_type: "dtk:claim-verifier"`; if
that type is not listed, spawn `general-purpose` with the body of
`${CLAUDE_PLUGIN_ROOT}/agents/claim-verifier.md` as its prompt). Start each batch with:

```
Context:
repo: <owner/name>
ref: <ref from step 1>
clone: yes | no
```

`clone: yes` only when the current directory is a clone of that repo and has `ref`
(`git cat-file -e <ref>^{commit}`); otherwise `no`. Run batches in parallel, never more than
half the machine's cores at once (`nproc`, or `sysctl -n hw.ncpu` on macOS).

**Coverage check, before any verdict is acted on:** list the ids you sent and the ids that
came back with a `### <id>:` block. Every claim must have a verdict. Re-send any claim that
has none (in a batch of at most 10); do not move on, and do not deliver, while one is missing.

Act on each verdict:

- `confirmed`: keep it.
- `wrong`: correct it to what the verifier says is true, or drop it.
- `weak` with `Basis: author-only`: keep it, attributed to the author ("<author> says…",
  "according to <author>").
- `weak` for any other reason: drop it, or rephrase to what is proven.

Re-read the corrected draft once: a dropped claim must not leave a dangling sentence.

### 6. Link

List every mention of a file, PR, review thread, CI run, doc or task, counting each one.
Spawn one **`dtk:link-finder`** (`subagent_type: "dtk:link-finder"`; fallback
`general-purpose` with `${CLAUDE_PLUGIN_ROOT}/agents/link-finder.md`) with the mentions, the
repo, `ref`, the PR's `baseRefOid` (a file the PR deleted links at the base sha) and where the
links are recorded (PR body, comments).

- Links pin a commit sha (`/blob/<sha>/<path>`), never a branch, so they keep pointing at what
  the story describes.
- A review thread links to the first comment of the thread.
- Put each link on the words the reader clicks: "[the retry loop](…)", never "(link)".
- A link whose status is `auth-required` is kept only when it was copied verbatim from the PR
  body (typically the task tracker). Any other link that was not verified becomes plain text.
- A mention with no verifiable link is reworded or left as plain text. Never ship an unchecked
  link.

### 7. Save and deliver

Write the story to a temporary file first, with this frontmatter above the story:

```
---
pr: <owner>/<repo>#<n>
head_sha: <headRefOid, 40 hex>
lang: <en | pt | ...>
generated_at: <UTC time, like 2026-11-13T18:00:00Z>
merged: true | false
---
```

Then run the gate:

```bash
"$SCRIPTS/pr-story/check-story.sh" <temporary file>
```

It prints one `<rule>: <detail>` line per violation and exits 1. Fix every violation in the
story and run it again. **Do not deliver a story the gate has not passed**, and never leave a
failing file in the cache. Once it exits 0, `mkdir -p` the cache folder and move the file to
`$CACHE`.

Show the story on the best display surface the environment offers, in this order:

1. a rich renderer the session has (a page or artifact publisher, a document viewer pane, an
   editor preview). Published pages stay private to the user unless they share them;
2. otherwise, print the story in the conversation.

Always give the cache path in one line. When a viewer can only open files inside the project,
a copy may go into an output folder that git ignores (confirm with `git check-ignore <path>`),
never into a tracked path.

When the story is served from the cache (step 2), skip straight to this delivery step.

## Digest mode

A digest tells what a repo took in over a range as a few arcs, not as N stories pasted one
after another. It is built on the same pipeline and the same cache: it never re-derives a
story that already exists.

Invocations:

- `/dtk:pr-story --since <YYYY-MM-DD|Nd> [owner/repo] [language]`: every PR merged from that
  date (`7d` is seven days before today) to today. Without `owner/repo`, use the current
  directory's GitHub repo, as step 1 does for a bare number; if there is none, ask for
  `owner/repo`.
- `/dtk:pr-story <ref> <ref> …`: exactly those PRs, each resolved with `story-target.sh`. They
  must be in one repo; if not, say so and offer one digest per repo. `from` and `to` are the
  earliest and latest merge dates among them (today for an open PR). An open PR is told in
  the digest as open, never as merged.

The language rule is the one above: English unless the prompt asks for another, and the whole
digest, including its cached stories, is in that language.

### D1. List

```bash
"$SCRIPTS/pr-story/list-merged.sh" <owner/repo> <since>
```

It prints a JSON array, oldest merge first, of `{number,title,author,mergedAt,additions,
deletions,changedFiles,labels,files,refs}` (`refs` are the PR numbers the body names as
`#<n>`). For an explicit list of PRs, read the same fields with `gh pr view`. `from` is the
`since` date (as `YYYY-MM-DD`) and `to` is today; compute both from the date, not from the
log.

**Zero PRs:** answer in one line, `No PRs merged in <owner/repo> between <from> and <to>.`
Write no file, spawn nothing, and stop.

### D2. Tier

Give each PR one tier from its labels, its title prefix, its size and the files it touches.
These are the defaults; use judgement on the edges.

| Tier | What it is | Told as |
|---|---|---|
| One line | Chores, config, dependency bumps, CI-only changes, formatting, version bumps | One line in "Also merged" |
| One paragraph | Specs, plans, ADRs and docs only | A paragraph telling **what was decided**, not what was written |
| Full story | Features, fixes, infra, anything that changes behavior | The full PR story from the pipeline, folded into its arc |

A PR that sits between two tiers goes to the higher one.

### D3. Group into arcs

PRs that belong to one thread of work are told together. A PR joins another PR's arc when:

- its `refs` (or the task id in its title or body) names another PR in the range, or
- it fixes files that another PR in the range introduced (its `files` overlap that PR's, and it
  merged later), or
- the two share a task id.

A PR that joins no one is its own arc. An arc is told in the order things happened, and its
title is executive: what changed in the system, present tense, no suspense, never ending in
`?`, `!` or an ellipsis. One-line-tier PRs stay in "Also merged" and do not form arcs. Only
join on evidence you can point at; never join because two PRs touch the same area.

### D4. Reuse and generate stories

For every full-story PR:

```bash
CACHE="$("$SCRIPTS/pr-story/story-cache.sh" path <owner> <repo> <n> [lang])"
"$SCRIPTS/pr-story/story-cache.sh" status "$CACHE" <ref-sha>
```

(`<ref-sha>` is `headRefOid` from `gh pr view`; for a merged PR, `merged: true` in the
cached frontmatter is the same condition step 2 uses.)

- `status` = `fresh` and the file is a merged story: **reuse it**. Do not regenerate it and do
  not send any of its claims to a verifier again; they were verified when it was written.
- `missing` or `stale`: generate it with the whole pipeline above (steps 1 to 7), saving it to
  the cache. Run these in parallel, never more than half the machine's cores at once, counting
  the verifier batches each one starts. Give each generator its PR, `owner/repo`, the
  language, and nothing else it has to guess.

The digest tells each arc from its stories' facts, not from the diffs again.

### D5. Write the digest

Draft it in the format below, then verify it, then save it.

**Format:**

```
---
repo: <owner>/<repo>
from: <YYYY-MM-DD>
to: <YYYY-MM-DD>
lang: <en | pt | ...>
generated_at: <UTC time, like 2026-11-13T18:00:00Z>
prs: [<number>, <number>, ...]
---

## <owner/repo>: <from> to <to>

**Headlines**
- <one to three bullets: the changes a reader must not miss>

### <Arc title: executive, what changed>

<Paragraphs telling the arc; every PR in it linked inline, on the words the reader clicks.>

**What changes for you**
- <what the reader will see or must do>

**Left open**
- <what the arc's stories left open, linked; "Nothing." when nothing>

### Also merged
- [#n](https://github.com/<owner>/<repo>/pull/n) <one line>
```

- `prs` lists every PR in the digest, the one-liners and paragraphs included. Each must be
  linked in the body, because the gate checks it.
- At most three headlines, ordered by what matters most. A one-paragraph spec/docs PR is told
  inside the arc it belongs to, or as its own arc titled by what was decided.
- A digest with only one-line PRs has no arc to write: tell the biggest of them as an arc of
  one, so the gate's "at least one arc" rule still holds.
- The same tone as a story: a flowing report, plain words, any new term glossed, statements
  that rest only on a PR author's word attributed to them. Facts like counts and dates are
  copied from the `gh` output.

**Verify only what is new.** A claim that a story already holds keeps that story's verdict and
is never sent to a verifier again, whether the story came from the cache or was generated a
minute ago in D4. That includes a sentence of the digest that restates a story's fact in other
words: what PR #28 made the default, what a command accepts, what a thread decided.

Sort every sentence of the draft before extracting claims:

- **Taken from a story** (a fact the PR's own story states and verified): copy it, keep its
  attribution (an author-only claim stays attributed), and send nothing.
- **New to the digest**: send it. These are only: the **arc relation** (that one PR fixes,
  follows or builds on another, that they belong together), a **headline** that states something
  no story verified (a comparison, a ranking, a claim across PRs), a **one-line summary** of a
  one-line-tier PR, and the **paragraph on a docs PR**.

For an arc relation, write the claim as the relation alone, with the evidence it rests on:
"PR #28 follows PR #26: both edit `skills/git-rebase-onto/SKILL.md`, #26 merged on <date> and
#28 on <date>." Never add the facts either story already proved to make it read better; if a
sentence mixes a relation with a copied fact, split it and send only the relation.

Send what is left under the rules of step 5: number the claims `c1`, `c2`, …, batch them at
most 10 per `dtk:claim-verifier` (3 to 10 each, more batches rather than a bigger one) with the
context block (`ref` being the head or merge sha of the PR the claim is about), parallel within
the same cap, run the coverage check (every id sent must come back with a verdict; re-send any
that did not) and act on the verdicts the same way. Every new claim gets a verdict. When nothing is new (a digest of one-line PRs apart, say), no
verifier runs. Then run `dtk:link-finder` as in step 6 over the digest's links that no verified
story already holds; the PR links of the digest are `https://github.com/<owner>/<repo>/pull/<n>`.

**Save and gate.**

```bash
DIGEST="$("$SCRIPTS/pr-story/story-cache.sh" digest-path <owner> <repo> <from> <to> [lang])"
```

Write the digest to a temporary file first, run `"$SCRIPTS/pr-story/check-story.sh" --digest
<temporary file>`, fix every violation it prints and run it again. Once it exits 0, `mkdir -p`
the folder and move the file to `$DIGEST`. Never deliver a digest the gate has not passed and
never leave a failing file in the cache. Deliver it as in step 7 and give the cache path in
one line.

The saved digest is an output, not an input: a second call over the same range rebuilds it
from the cached stories, which is cheap, so a late-merged PR is never missing from it.

## Rules that hold everywhere

- Never post, comment or review on GitHub. The story is the reader's own reading material.
- One unverifiable claim is dropped or attributed, never kept bare.
- A digest is a mode of this skill, not a different skill. It reuses the cache and never
  regenerates or re-verifies a story that is `fresh`.
