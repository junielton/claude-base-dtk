# Recovery cheat sheet

Nothing here is destructive to read. Use these when a rebase goes sideways.

## During a paused/conflicted rebase

```
git rebase --abort      # cancel the whole rebase, return to the pre-rebase state
git rebase --skip       # drop the commit currently causing trouble, continue
git rebase --continue   # resume after staging resolved files (git add)
git status              # see where you are and which files conflict
```

## After a finished rebase you want to undo

If `safe_rebase_onto.sh --execute` was used, a backup branch exists:

```
git branch | grep backup/          # find it (backup/<topic>-<timestamp>)
git checkout <topic>
git reset --hard backup/<topic>-<timestamp>
```

No backup? The reflog still has the old tip:

```
git reflog                         # find the line just BEFORE "rebase (start)"
git reset --hard HEAD@{N}           # N = the entry number before the rebase
# or reset to the explicit old hash shown in the reflog
```

`git reflog` keeps entries for ~90 days by default, so a "lost" commit after a
rebase is almost always still recoverable — look for its hash there and either
`git reset --hard <hash>` or `git cherry-pick <hash>`.

## Inspecting what changed before committing to anything

```
git range-diff <oldbase> <old-topic> <new-topic>   # did the rebase change content?
git diff backup/<topic>-<ts> <topic>               # net difference vs the backup
git log --oneline <newbase>..<topic>               # the replayed commits, in order
```

`range-diff` is the best sanity check: it compares the commit series before and
after the rebase and highlights any commit whose actual diff changed (which would
mean a conflict resolution altered the code). Ideally every commit shows `=`.

## Deleting backups once you're happy

```
git branch -D backup/<topic>-<timestamp>
```
