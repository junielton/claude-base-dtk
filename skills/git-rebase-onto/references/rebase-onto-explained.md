# `git rebase --onto`, explained with worked examples

## The command

```
git rebase --onto <newbase> <oldbase> <topic>
```

Read it as: "take the commits in the range `oldbase..topic` and replay them on
top of `newbase`." `topic` defaults to the current branch if omitted.

- `oldbase..topic` means "commits reachable from topic but NOT from oldbase" — i.e.
  everything *after* the cut point.
- `oldbase` itself is excluded. That is why, in a numbered log, you cut at the
  PARENT of the first commit you want to keep — the `^` in `abc1234^`.

## Why a stacked workflow needs it

Plain `git rebase <newbase>` uses the merge-base of HEAD and newbase as the
implicit oldbase. That is fine when you forked directly from newbase. But when you
forked topic from an intermediate branch B (which itself came from A), the
merge-base with your real target may sit far back and sweep in B's commits. `--onto`
lets you state the cut point explicitly so only *your* commits move.

## Worked example 1 — clean stack

```
A ── A1 ── A2            (branch: main)
       \
        B1 ── B2         (branch: feature-b, forked at A1)
               \
                C1 ── C2 (branch: feature-c, forked at B2 — current)
```

You want feature-c's commits (C1, C2) on top of main, dropping the feature-b
commits. The cut point is B2 (the last commit that isn't yours):

```
git rebase --onto main B2 feature-c
# result: A ── A1 ── A2 ── C1' ── C2'   (feature-c)
```

Here `oldbase = B2`, found as `git merge-base feature-c feature-b`.

## Worked example 2 — "contaminated" history

Earlier, someone rebased feature-c and B1/B2 got duplicated into it with new
hashes (B1', B2'). Now:

```
... B2 ── B1' ── C1 ── B2' ── C2     (feature-c)
```

`git rev-list --count main..feature-c` looks inflated because B1' and B2' are
counted too. `git cherry main feature-c` marks B1' and B2' with `-` (their patch
already exists in main via B1/B2) and C1, C2 with `+`.

If the duplicates were all below the fork, a single `--onto` with `oldbase = the
merge-base` cleanly excludes them. But here B2' sits *between* C1 and C2
(interleaved). A single range can't drop a commit from the middle, so the correct
fix is an interactive rebase that drops the `-`-marked commits:

```
git rebase -i --onto main <oldbase> feature-c
# in the editor, delete the lines for B1' and B2'
```

This is exactly the case where the skill should stop and confirm with the user
rather than force a single-range solution.

## Sanity-checking the result

```
git range-diff <oldbase> <old-topic-tip> <new-topic-tip>
```

Every replayed commit should show `=` (unchanged content). A commit shown with a
diff means a conflict resolution altered it — review that one carefully.
