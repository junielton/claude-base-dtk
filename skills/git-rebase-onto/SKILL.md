---
name: git-rebase-onto
description: >-
  Guides a safe, scripted `git rebase --onto` when moving a topic branch from one
  base onto another. Use this skill whenever the user wants to rebase, reparent,
  move, or transplant a branch onto a different branch — especially in stacked-PR
  workflows where branches are forked from other feature branches (not just main/
  master), or after a parent/ancestor PR was squash-merged and the branch now
  shows commits that are already on main (duplicate commits, an inflated
  `rev-list --count`, a "contaminated"/"dirty" history, duplicate-content
  conflicts on files the user never touched). Also trigger on mentions of a "cut
  point", "fork point", `rebase --onto`, "which commits are mine", a rebase stuck
  mid-way on conflicts while reparenting, or when the user only describes the
  symptom ("my branch has commits that aren't mine", "I want my commits on top of
  another branch with fewer conflicts") without naming the command. Do NOT use it
  for a plain `git rebase main` refresh of an up-to-date fork, interactive
  history cleanup unrelated to reparenting, or merge-based workflows.
argument-hint: "[target branch to land on, e.g. origin/main] [optional: topic branch, defaults to the current one]"
---

# git rebase --onto, scripted and safe

## What this skill is for

`git rebase --onto <newbase> <oldbase> <topic>` moves the commits in the range
`oldbase..topic` and replays them on top of `newbase`. The hard part is never the
command — it is finding the correct **oldbase** (the "cut point"): the last commit
your topic shares with the branch it was forked from. Get it wrong and you either
drag along commits that aren't yours (conflicts) or drop commits that are.

This is especially fiddly in **stacked workflows**, where a branch is forked from
another feature branch which was forked from another — main/master is rarely the
direct parent. Histories also get "contaminated": the same change appears in two
branches with different hashes (from an earlier rebase or cherry-pick), so a plain
`git rev-list --count origin/<branch>..HEAD` looks inflated or "dirty".

The skill's job: find the cut point with confidence, preview the move, run it
behind guardrails, and help resolve conflicts — auto-resolving only what is
unambiguous, researching when unsure, and asking the user when a real judgment
call remains.

## The mental model (keep this straight)

- **newbase** — where you want the commits to LAND (the target branch).
- **oldbase** — the CUT POINT. Everything *after* this, up to topic, gets replayed.
  In shorthand this is `<first-commit-that-is-mine>^`, i.e. the parent of the
  first commit that belongs to the topic branch. The graph merge-base
  between topic and its source branch is the same commit.
- **topic** — the branch being moved (defaults to the current branch / HEAD).

`git rebase --onto newbase oldbase topic`  ⇒  take `oldbase..topic`, put it on `newbase`.

## Workflow

Work through these steps in order. Create a to-do list mirroring them so the user
can follow along.

1. **Identify the three refs.** Resolve the fork/stack relationship from the PR
   graph BEFORE anything else: `gh pr list --head <topic>` plus
   `gh pr view <n> --json baseRefName,headRefName,state` on the topic and its
   sibling branches. Branch names, worktree layout, and backup branches all lie
   about parenthood — PRs don't (trusting branch naming is how the parent/child
   direction gets read backwards). Only ask the user when there is no PR
   to read; in stacked setups, never assume main/master is the direct parent.
   Confirm the conclusion with the user: target branch (newbase) and the source
   branch the topic was forked from (used to find oldbase).

   Two ref rules, both learned the hard way:
   - **`origin/<x>` means the remote ref, literally.** When the user names
     `origin/main`, fetch and rebase onto `origin/main` — never update the local
     `main` and rebase onto that instead — the user asked for the remote ref
     for a reason. A bare branch name in a stacked setup
     almost always means the remote one too: resolve it, say which ref you
     resolved to, and don't stop on a missing local branch.
   - **The topic must not be behind its own remote.** Assert
     `git rev-list --count <topic>..origin/<topic>` is 0 before anything else; if
     it is not, fast-forward to `origin/<topic>` and rebase that. The PR's code is
     whatever `origin/<topic>` holds, never what a stale worktree has checked out.
     `--force-with-lease` does NOT protect here — this exact gap can force-push
     away a merged PR's work without any warning.

2. **Analyze and find the cut point.** Run `analyze_branches.sh`:

   ```bash
   SCRIPTS="${CLAUDE_PLUGIN_ROOT}/scripts"; [ -d "$SCRIPTS" ] || echo "dtk: scripts dir not found: $SCRIPTS" >&2; echo "$SCRIPTS"
   "$SCRIPTS/git-rebase-onto/analyze_branches.sh" <source-branch> [<topic=HEAD>] --newbase <target-branch>
   ```

   Use the output path as `$SCRIPTS` for all script commands below.

   It prints the merge-base (recommended oldbase), numbered logs of both branches,
   a contamination report (`git cherry`: `-` = already in base by patch-id), and a
   confidence level. Read it and decide:
   - **confidence HIGH (clean history):** the merge-base is the cut point. Show the
     user the recommended oldbase and the commit list that will move, and confirm.
   - **confidence REVIEW (contamination):** explain *why* the counts differ. The
     merge-base is still a safe oldbase when duplicates sit below the fork. If
     duplicates are interleaved with real commits, see "When the cut point is
     ambiguous" below before proceeding.
   - **Squash-merge caveat — distrust even HIGH.** If any ancestor PR in the
     stack was squash-merged into newbase, `git cherry` is blind to it: a squash
     gives the patches a new identity, so already-merged commits show as `+` and
     confidence reads "HIGH / clean" falsely — "0 contaminated" while a dozen
     of the commits are already on main. The script's
     SQUASH-MERGE CHECK flags suspects, but the PR graph is authoritative. In
     that case set oldbase to the squashed ancestor branch's OLD TIP (from the
     merged PR's `headRefName`, confirmed with
     `git merge-base --is-ancestor <tip> <topic>`) and validate the cut with
     `git diff --stat <tip> <newbase>` — it must show only files foreign to the
     topic's work.

3. **Confirm the cut point with the user.** Always show the proposed oldbase +
   the exact commits that will be replayed, and get a yes before executing. A
   numbered log is what a human reads to find the cut by hand; reproduce that
   clarity — never silently pick and run.

4. **Preview the rebase (dry run).** Run `safe_rebase_onto.sh` WITHOUT
   `--execute`. It validates refs, checks the working tree, and prints the commit
   list and exact command. Show this to the user.

   ```
   "$SCRIPTS/git-rebase-onto/safe_rebase_onto.sh" --newbase <target> --oldbase <cut> --topic <branch>
   ```

   The preview also flags two silent hazards — decide them with the user before
   executing:
   - **Merge commits in the range:** a plain rebase linearizes them without
     warning. If any exist, add `--rebase-merges`.
   - **Stacked children:** branches forked from commits inside the range will be
     left stranded on the old history. If a child's tip is itself in the range,
     `--update-refs` (git ≥ 2.38) carries it along; otherwise plan to move each
     child afterwards with this same skill.

5. **Execute.** Re-run the same command with `--execute`. The script creates a
   timestamped `backup/<topic>-<ts>` branch first, then rebases. If it pauses on a
   conflict, go to step 6.

6. **Resolve conflicts** following the policy below.

7. **Verify and publish.** After a clean finish:
   - `git log --oneline <newbase>..<topic>` must show your commits and nothing
     foreign.
   - `git range-diff <oldbase>..backup/<topic>-<ts> <newbase>..<topic>` must
     show the same changes, just reparented. (The bases differ after `--onto`,
     so use the explicit two-range form — the three-argument shorthand assumes
     a shared base and compares the wrong ranges here.)
   - Move any stranded children the preview flagged (branches forked from
     rewritten commits, still on the OLD history) with this same skill — the
     success output repeats the list. Note `git branch --contains <backup>`
     is NOT enough: it misses children forked mid-range.
   - If the branch has an upstream/PR, publish with
     `git push --force-with-lease` — never plain `--force`. The lease is NOT a
     safety net for a stale topic: it only proves the remote has not moved since
     your last fetch, so a branch that was behind `origin/<topic>` when you
     rebased it force-pushes over those commits without complaint. That is why
     step 5's script refuses to run on a topic that is behind its own remote —
     never bypass that check, fast-forward and rebase again instead.

   Report the backup branch name so the user can discard it when satisfied.

   **Close with a two-line plain-language report — always.** The user should
   never have to ask "did you push?" or "explain again, simply, what is going
   on?". Line 1: what moved, in words — "your N commits moved from X and now sit
   on top of Y; nothing was lost". Line 2: the push state, stated even when you
   did nothing — **"pushed with --force-with-lease"** or **"NOT pushed — this is
   the irreversible step, confirm?"**. Write both lines in the user's language.
   Never end a successful rebase silently sitting on
   an unpushed branch.

## Landing a stack (do this BEFORE merging any parent)

Merging a parent is what destroys the information the children need. Two moves,
both before the merge button:

1. **Tag every branch tip:** `git tag cut/<pr>-tip origin/<branch>`. Merging with
   `--delete-branch` destroys the remote ref, and the parent's old tip is the only
   correct oldbase for each child. A tag is also often the only way to recover a
   commit that was force-pushed away.
2. **Retarget every child PR first:** `gh pr edit <child> --base main` BEFORE its
   parent merges. GitHub **auto-closes** a PR whose base branch is deleted and does
   not reliably retarget for you. This is unrecoverable: `gh pr reopen` fails with
   `422: state cannot be changed` once the head was force-pushed, and the work has
   to be re-opened as a brand-new PR.

Also: badges saying "N behind" measure against the *parent*, not main — a stack
that is parked does not need rebasing. Don't churn a stack nobody is landing.

## Conflict resolution policy

The guiding principle: **only resolve what you are certain about; otherwise gather
evidence; if a real decision remains, hand it to the user with clear options.**
A wrong "confident" resolution silently corrupts code, which is far worse than
pausing to ask. Be conservative.

Run `"$SCRIPTS/git-rebase-onto/conflict_status.sh"` to see the conflicted files and, for each, the
three versions available:

- `git show :1:<file>` — common ancestor (base of the conflict)
- `git show :2:<file>` — *ours* = the new base / target side
- `git show :3:<file>` — *theirs* = the commit being replayed (your change)

**Resolve automatically (high certainty) when** the conflict is mechanical and the
correct merge is unambiguous, e.g.: both sides added imports/dependencies (keep
both, deduplicated); pure formatting/whitespace differences; a lockfile or
generated file that should be regenerated; non-overlapping additions in different
regions that git only flagged due to adjacency. State what you did and why.

**Append-only files (CHANGELOG and friends) are a union resolve, then a format
pass.** Keep every bullet from both sides — picking a side silently drops a
shipped entry. But union is dumb concatenation: it re-emits both `### Section`
headings and butts them against the previous bullet with no blank line, which
fails the repo's format gate *after* the rebase looked clean. Run the formatter
and a dedupe scoped to the CURRENT release block only — a dedupe that reaches
into historical blocks rewrites history that was never yours to touch.

**Research first (medium certainty) when** intent is unclear. Use the repo to
recover it before deciding: `git log -p <file>` on both sides, `git blame`, the
commit messages of the replayed commit and the conflicting newbase commit, related
tests, and how the surrounding code is used elsewhere. Often this resolves the
ambiguity — then proceed and explain your reasoning.

**Ask the user (low certainty) when** both sides encode a real, conflicting intent
(e.g. the same function changed two different ways, a value changed to different
numbers, logic that can't be mechanically reconciled). Do not guess. Present:
the file and hunk, a plain-language summary of what each side wants, the
trade-offs, and 2–3 concrete options (take ours / take theirs / a specific
combined version), with a recommendation if you have a justified lean. Let the
user choose. Prefer `AskUserQuestion` so the options are clickable.

Never run `git rebase --continue` until every conflicted file is resolved and
`git add`-ed. After each commit applies, more conflicts may appear — re-run
`conflict_status.sh` and repeat.

## When the cut point is ambiguous

If `analyze_branches.sh` reports contamination interleaved with real commits, or
the user isn't sure which commits are theirs:

1. Compare the two branches' numbered logs and match by subject + author + patch
   (the `git cherry` `-` lines are equivalent commits). The cut point is the last
   commit shared by content, even if hashes differ.
2. If the duplicates come from a **squash-merged ancestor PR**, `git cherry`
   won't mark them at all (see the squash caveat in step 2) — the cut point is
   the squashed ancestor branch's old tip, recovered from the merged PR's
   `headRefName`, not anything the contamination report shows.
3. If a clean single cut point doesn't exist (duplicates interleaved), the right
   tool is usually an **interactive rebase** that drops the duplicate commits,
   rather than a single `--onto` range. Explain this to the user and, if they
   agree, walk through `git rebase -i` dropping the `-`-marked commits.
4. If still unsure, present the candidate cut points to the user with the commit
   lists each would produce, and let them pick. Always err toward asking — a wrong
   cut point is the costliest mistake here.

## Recovery (always available)

Every `--execute` run leaves a `backup/<topic>-<timestamp>` branch. To undo:

```
git checkout <topic> && git reset --hard backup/<topic>-<timestamp>
```

Mid-rebase escape hatches: `git rebase --abort` (back to the start), `git rebase
--skip` (drop the current commit), and `git reflog` to find any prior state. See
`${CLAUDE_SKILL_DIR}/references/recovery.md` for a fuller cheat sheet.

## Scripts

All scripts are read-only except `safe_rebase_onto.sh --execute`. They live in
`$SCRIPTS/git-rebase-onto/` — the plugin's scripts folder (resolved in step 2),
not the repo you are rebasing — and print usage with `-h`. Run them with the repo as the working
directory.

- `analyze_branches.sh <base> [topic] [--newbase ref] [--limit N]` — find the cut
  point; numbered logs; contamination report; squash-merge check (with
  `--newbase`); merge-commit warning; recommended command.
- `safe_rebase_onto.sh --newbase <ref> --oldbase <ref> [--topic <ref>]
  [--rebase-merges] [--update-refs] [--execute]` — preview by default (flags
  merge commits and stranded child branches); with `--execute`, backs up then
  rebases.
- `conflict_status.sh` — summarize the current conflict state during a paused rebase.

## References

- `${CLAUDE_SKILL_DIR}/references/recovery.md` — reflog / abort / reset recovery recipes.
- `${CLAUDE_SKILL_DIR}/references/rebase-onto-explained.md` — deeper explanation of the three-ref model
  and worked examples, for when you or the user want the full picture.
