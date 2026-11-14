---
name: pr-story
description: >-
  Tell what a pull request brought in as a short, verified, readable story: why it
  exists, what changed, what changes for the reader and what was left open. Every
  statement is checked against the code, the review threads and the runs by an
  independent claim-verifier agent, and every file, PR, thread or run it mentions is a
  link that was checked. Works on open or merged PRs, with or without a local clone,
  and keeps a per-user cache so a merged PR is told once. Use it when the user asks
  "tell me what this PR brought in", "story of PR #n", "what did #n change", "explain
  this PR without the diff", "what landed in #n", or pastes a PR URL with that intent,
  in any language. Do NOT use it to review a PR and give feedback (review-peer, review),
  to write a PR description (create-pr), or to summarize a date range of PRs.
argument-hint: "[PR number | owner/repo#n | PR URL] [optional: language]"
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
Read-only: the only things written are the cache file and, for a viewer, one copy in a
git-ignored folder. It never posts anywhere.

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
copied from the `gh` output, are skipped. Step 7 proves it, sentence by sentence, on the final
text.

Number the claims `c1`, `c2`, … and never reuse an id, not even in a later batch. Write each as one sentence that would read the same in the
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
failing file in the cache.

**Sentence coverage.** Step 5's coverage check proves that every claim got a verdict; this one
proves that every sentence got a claim, on the final text (after the verdicts and the link step
reworded it). Once the gate passes, map every sentence of the final story to a claim id:

```bash
"$SCRIPTS/pr-story/story-sentences.sh" list <temporary file>
```

It prints `s<N>/<checksum> <sentence>` for the Why line, every paragraph sentence and every
bullet. Write two more temporary files:

- **the map**, one line per listed sentence: `<key> c3`, or `<key> c3,c7` when several claims
  together state every fact of the sentence, or `<key> transition`. A transition carries no
  fact, no number, no attribution ("Here is what that means for you."). An author-attributed
  sentence is never a transition, and neither is a sentence with a link, inline code or more
  than 15 words. A claim that says less than the sentence does not cover it.
- **the verdicts**, one line per claim that came back: `<id> <verdict> [<basis>]`, copied from
  its `### <id>:` block, like `c3 confirmed primary` or `c7 weak author-only`.

Print both files in the conversation (`cat`), then run:

```bash
"$SCRIPTS/pr-story/story-sentences.sh" check <temporary file> <map> <verdicts>
```

It prints one `<rule>: <detail>` line per problem and exits 1:

- `unmapped`, `no-verdict`, `not-a-transition`: a factual sentence no verifier has seen, and
  every unmapped factual sentence goes to a verifier as a new claim, in batches of at most 10, with
  new ids and step 5's coverage check, before anything is saved.
- `unproven`: the sentence rests on a `wrong` or `weak` verdict. The corrected sentence is a new
  claim, verified like the others.
- `unattributed`: the sentence rests on a `weak` author-only claim and does not name the author.

Act on the new verdicts as in step 5, then run `list`, the map and `check` again after every
rewrite: a rewritten sentence gets a new key, and its old mapping is reported as `stale-map`.
Re-run the gate when the text changed. **Do not save a story whose sentence check has not
passed.** Only once `check-story.sh` and `story-sentences.sh check` both exit 0 on the same
file, `mkdir -p` the cache folder and move the file to `$CACHE`.

Show the story on the best display surface the environment offers, in this order:

1. a rich renderer the session has (a page or artifact publisher, a document viewer pane, an
   editor preview). Published pages stay private to the user unless they share them;
2. otherwise, print the story in the conversation.

Always give the cache path in one line. When a viewer can only open files inside the project,
a copy may go into an output folder that git ignores (confirm with `git check-ignore <path>`),
never into a tracked path.

When the story is served from the cache (step 2), skip straight to this delivery step.

## Rules that hold everywhere

- Never post, comment or review on GitHub. The story is the reader's own reading material.
- One unverifiable claim is dropped or attributed, never kept bare.
- A date range or several PRs at once is not handled by this skill: say so and offer to tell
  them one by one.
