---
name: review-publish
description: "Use after /dtk:review-peer (or with any saved review report) to turn the report into the GitHub review: the verdict, a one-line body, one inline comment per verified finding, written through the user's own voice skill when one exists, validated against the PR diff, and posted only after an explicit confirmation. Also use when asked to post, publish or send a drafted review."
---

# Review Publish: PR #$ARGUMENTS

## Overview

Turns a saved review report into the exact payload that goes to GitHub, and posts it. The report decides WHAT is said; this skill decides WHERE each thing goes (body vs inline), the voice skill decides HOW it sounds, and nothing else gets in.

The one rule everything below enforces: **the GitHub text contains the verdict and the verified findings, and nothing else.** No CI status, no "thanks for the rebase", no narration of what was checked, no status of old threads, no recap of the author's work. The author sees CI and their own threads already.

## When to Use

- Right after `/dtk:review-peer` saved `peer-review-N.md`
- Asked to post, publish, or send a review that is already drafted
- Re-posting after the user asked for adjustments to a draft

## When NOT to Use

- The review has not been done yet (run `/dtk:review-peer` first)
- Reviewing your own PR (`/dtk:review` produces tasks, not a review to post)
- Replying to comments on a PR you authored

## Step 0: Resolve Scripts

```bash
# resolver idiom: docs/conventions/script-resolution.md
SCRIPTS="${CLAUDE_PLUGIN_ROOT}/scripts"; [ -d "$SCRIPTS" ] || echo "dtk: scripts dir not found: $SCRIPTS" >&2; echo "$SCRIPTS"
```

## Workflow

### 1. Load the report

```bash
bash $SCRIPTS/review/project-context.sh
ls -t memories/reviews/PR-$ARGUMENTS/peer-review-*.md | head -1
```

Read the latest `peer-review-N.md` (or the path the user gave). Take ONLY these sections into the payload:

- `## Recommendation`
- `## 🔴 Blocking`
- `## 🟡 Non-blocking`
- `## 💬 Questions`
- the verifier line in `Final Summary` (how many findings were kept)

Never carry into the payload: `Existing Review Comments`, `Lessons Applied`, `Reconciliation with Previous Reviews`, `Still pending`, `Resolved since last review`, CI state, rebase notes, or anything from `review-state.md`. Those are the reviewer's memory, not the author's business. An old item that is still pending already has an open thread; re-posting it is noise.

### 2. Decide the verdict

| Report | `event` |
|--------|---------|
| Any 🔴 finding survived verification | `REQUEST_CHANGES` |
| Only 🟡 and 💬, or nothing | `APPROVE` |

A CR is a request the author must answer, and under `COMMENT` it is one they can decline (they did, twice in 6). The inline carries the content; the verdict carries the block. `COMMENT` is never chosen here; it exists only for the gate's "no verdict, inline only" option, and only when no CR is posted.

A red CI, a pending rebase, or an open old thread never changes this. CI is the author's gate, not the reviewer's.

### 3. Build the payload

Write `memories/reviews/PR-$ARGUMENTS/publish-N.json` (same `N` as the report):

```json
{
  "pr": 0,
  "repo": "owner/repo",
  "commit_id": "<full 40-char head SHA from gh pr view --json headRefOid>",
  "event": "APPROVE | REQUEST_CHANGES",
  "body": "",
  "comments": [
    { "path": "app/File.php", "line": 29, "tag": "FFT", "body": "FFT: ..." }
  ]
}
```

**Inline comments.** One per finding that the verifier kept. Tag from the bucket: 🔴 → `CR`, 🟡 → `FFT`, 💬 → `Q`. Each body:

- starts with the tag and a colon (`CR: `, `FFT: `, `Q: `)
- is at most two sentences, and states the ask directly: "I'd …", "worth …", "this needs …", plus the reason. The humility lives in the reason and in the tag (FFT already says non-blocking), never in the ask
- for a CR, names what unblocks it
- names behaviour or the file, never a commit SHA, a line number in prose, or "non-blocking" (the tag already says it)
- is in English
- `line` is the finding's `file:line`; it must be a line ADDED by the PR, step 5 checks that

**No hedges.** Banned in every body (the review body and each inline), case-insensitive: `might be worth`, `maybe`, `could be worth`, `feel free to ignore`, `totally optional`, `take it or leave it`, `fine to leave`, `not a big deal`, `just a thought`. Do not mark a finding optional either; the tag says how much it blocks. `post-review.sh` runs `tone-lint.sh` on the final payload and refuses it, naming the phrase.

**Suggestion blocks.** When the fix is a local patch (a line or a few lines that replace the anchored ones), the comment ships it as a GitHub suggestion, after the one or two sentences:

````
FFT: This query runs once per order. I'd eager load the relation.

```suggestion
$orders = Order::with('customer')->get();
```
````

The block replaces the anchored line(s), so it holds the full replacement text. Never write the replacement code into the sentence: when the patch is code it goes in the block and the sentence gives the reason. A fix that spans files or needs a design choice stays prose. The fence does not count toward the two sentences.

Findings marked `refuted` or `not checked` never reach GitHub. If a finding was not verified, it is not posted; send it back through `/dtk:review-peer` step 8 instead of posting it with a hedge.

**Body.** Exactly one of these shapes, nothing appended:

| Situation | Body |
|-----------|------|
| `APPROVE`, no inline comments | `LGTM` or a bare `👍` |
| `APPROVE`, with inline comments | `Approving, a few notes inline.` (no emoji: a positive emoji next to real notes reads as "nothing to see") |
| `REQUEST_CHANGES` (has CR) | `A couple of things to sort before merge, inline.` |
| Inline only, no verdict (user's choice at the gate, never with a CR) | empty string, event `COMMENT` |

Banned in the body, with no exceptions: CI or check status, "thanks for the <act>", any file/class/method name, any count or preview of what the inline comments say, "non-blocking", the state of a previous thread, any sentence that narrates a check ("verified", "went through", "grepped", "traced").

### 4. Voice pass

```bash
bash $SCRIPTS/review/voice-resolver.sh
```

The resolver returns the user's writing-voice skill, if they have one (see [Voice skill resolution](#voice-skill-resolution)). Then:

- **`voice_skill` found:** call the `invoke` line the resolver printed (a `Skill` tool call with that name; never rewrite "in that style" from memory) once per message (body, then each inline body) with this exact brief:

  > Rewrite the wording of the message below in the user's voice. Content is frozen: do not add, remove, soften or reorder any fact, keep the leading `Q:`/`CR:`/`FFT:` tag, keep the file reference, keep any ```suggestion block byte for byte, stay within two sentences for an inline comment and one line for a body. Never add a hedge or mark anything optional: state the ask directly ("I'd …"), whatever your usual register says. Output only the message.

  Replace the payload text with what comes back. If the voice skill added a fact, a thanks for an act, a CI mention or a status of another thread, drop that sentence; the voice skill shapes words, it does not own content. **If it added a hedge** (the banned list in step 3), rewrite that sentence as a direct ask yourself: many voice skills prescribe "could" and "might be worth", and the brief does not always win. The lint in step 5 runs after this pass and is what holds.

- **`candidates` has more than one entry:** ask the user once which one to use, then persist it (see below) so the question is never asked again.

- **No voice skill:** keep the neutral register already in the payload (English, direct, courteous, a stated ask with its reason) and say once in the transcript: "No writing-voice skill found, using the neutral register. Mark yours with `voice: true` in its SKILL.md frontmatter or set `voice_skill` in `~/.claude/dtk.local.md`." Never name a specific skill as the expected one.

### 5. Validate anchors

```bash
bash $SCRIPTS/review/post-review.sh --payload memories/reviews/PR-$ARGUMENTS/publish-N.json --dry-run
```

The dry run runs `tone-lint.sh` first, on the payload as it stands after the voice pass. It fails, and names the rule and the comment, on a banned hedge, a body without a `Q: `/`CR: `/`FFT: ` prefix, an inline over two sentences, or a CR under any event but `REQUEST_CHANGES`. Fix the wording (or the event) and run again; never edit the lint or the list to make a payload pass.

It also fails, and names the offender, when: `commit_id` is not the current head (the author pushed; re-anchor or re-review), it is not 40 characters, or an inline `line` is not an added line in the PR diff. GitHub rejects the WHOLE review with a 422 on any of these, so nothing is posted until the dry run is clean.

### 6. Confirmation gate

The draft lives INSIDE the gate, in each option's `preview`. The question dialog covers the transcript, so a draft printed above it (or worse, a one-line summary of it) is never what the user reads before choosing. End the turn with `AskUserQuestion`, never with a plain-text question:

```
header:   "PR #$ARGUMENTS"
question: "Review ready: <APPROVE|REQUEST_CHANGES>. Post it?"
options (single-select, every option carries a preview):
  - "Post <approve|request changes>"   preview: the full draft (below)  → step 7
  - "Pick what goes"           preview: the numbered inline comments  → step 6b
                               (omit this option when there are no inline comments)
  - "Post, with changes"       preview: the full draft; the user says what to change → step 4
  - "Hold"                     preview: the payload path; post nothing
```

The full-draft preview is the payload rendered verbatim, never summarized, and dense: the preview box shows only about 5 lines before it cuts the rest ("N lines hidden"), so no blank lines, no labels like `BODY:`, no commit SHA, one line per comment:

```
REQUEST_CHANGES · "A couple of things to sort before merge, inline."
CR · File.php:42 — <full comment text, tag prefix dropped>
FFT · x.js:17 — <full comment text, tag prefix dropped>
```

Because long drafts still overflow the box, also print the same draft as plain text as the last thing in the transcript, right before the `AskUserQuestion` call. The dialog renders below it, so the full draft stays readable above the options.

"Type something" and "Chat about this" are added by Claude Code itself; do not add them as options. Nothing goes to GitHub before a choice here. The gate is on posting, not on drafting.

### 6b. Pick what goes

One `AskUserQuestion` call. `AskUserQuestion` takes at most 4 questions with at most 4 options each, and `preview` works only on single-select, so:

- **Question 1**, header `Verdict`, single-select: `"<APPROVE|REQUEST_CHANGES> + body"` or `"No verdict, inline only"` (event `COMMENT`, empty body). Offer the second only when no CR is among the comments; a CR carries the block, so it never posts under `COMMENT`.
- **Questions 2–4**, `multiSelect: true`, header `Comments 1/3` and so on: up to 4 inline comments each, ordered CR → FFT → Q. Label `<TAG> · <file basename>:<line>`; description is the full comment text. A checked box means "post it".
- **More than 12 comments:** after the answer, ask the next batch in a new call (up to 4 multiSelect questions, 16 comments). Never truncate or merge comments to fit.

Rewrite `publish-N.json` with the chosen verdict and only the checked comments. If every CR was unchecked, the verdict follows step 2 again (`APPROVE`). Keep the dropped ones in `publish-N.dropped.json` so a later "put that one back" needs no redraft. Re-run the step 5 dry run, then go straight to step 7: what the user checked is the explicit choice. With no verdict and no comment checked, post nothing and treat the result as Hold.

### 7. Post

```bash
bash $SCRIPTS/review/post-review.sh --payload memories/reviews/PR-$ARGUMENTS/publish-N.json
```

The script re-runs the dry-run checks, then submits one review via `gh api`. On a 422 it prints GitHub's message and leaves the payload untouched; fix the anchor and run again.

### 8. Record

Append to `memories/reviews/PR-$ARGUMENTS/review-state.md` under `## Notes`:

```
- Posted peer-review-N as <event> at <commit_id short>, <count> inline (YYYY-MM-DD)
```

## Voice skill resolution

The plugin ships no voice of its own and names no user's skill. `voice-resolver.sh` looks, in order, and stops at the first tier that yields something:

1. **Setting.** `voice_skill:` in the frontmatter of `.claude/dtk.local.md` (project), then `~/.claude/dtk.local.md` (user).
2. **Marker.** Any `SKILL.md` under `.claude/skills/*/`, `~/.claude/skills/*/` or an installed plugin's `skills/*/` whose frontmatter has `voice: true` (or `metadata.role: voice`).
3. **Heuristic.** A skill directory named `*-vox`, `*vox` or `*-voice`, or a description that mentions a writing voice ("in <their> voice", "sounds like", "personal voice"). Skills about spoken output (speak, read aloud, TTS) are excluded.
4. **None.** Neutral register.

A plugin skill resolves to its invoke name `<plugin>:<skill>`; a user or project skill to its bare name. To persist a choice, write `~/.claude/dtk.local.md`:

```markdown
---
voice_skill: <name>
---
```

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Body mentions CI ("CI is green now, so approving") | CI is the author's gate; the body is the verdict only |
| Body thanks for an act ("thanks for the rebase/fixes") | Drop it; "nice work" is the only praise allowed and only on a clean approve |
| Body reports an old FFT/Q as "still open" | The thread is already open; never re-post reconciliation |
| Posting a finding marked `not checked` | Only `verified` findings reach GitHub |
| Letting the voice skill add content | Its brief freezes content; strip anything it adds |
| A hedged ask ("might be worth", "could we", "feel free to ignore") because the voice skill prescribes it | Rewrite it as a direct ask ("I'd …" + the reason); the lint in step 5 rejects what survives |
| A CR posted as `COMMENT` | `REQUEST_CHANGES`: under `COMMENT` the author can decline it, and `tone-lint.sh` refuses the payload |
| A CR body marked optional or with no word on what unblocks it | A CR names what unblocks it and is never optional; if it is optional it is an FFT |
| Prose where the fix is a local patch | Ship a ```suggestion block with the replacement lines |
| Hardcoding a voice skill name in this plugin or a boot prompt | Resolution is by setting, marker or heuristic, never by name |
| Abbreviated `commit_id`, or an inline `line` on a context line | Run the dry run; GitHub 422s the whole review |
| Ending the turn with a prose question | `AskUserQuestion` is the last call of the turn |
| Summarizing the draft above the gate ("approve with LGTM, no inline") | The verbatim draft goes in the transcript right above the gate AND, dense, in the options' `preview` |
| A roomy preview (`BODY:` label, blank lines, SHA) | The box cuts at ~5 lines; the comments are what got hidden |
| Squeezing 10 comments into one 4-option question | Paginate: 4 per question, 3 comment questions per call, then a new call |
