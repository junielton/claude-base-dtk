---
name: create-pr
description: "Use when creating a GitHub PR, opening a PR, or pushing changes for review. Generates a standardized title and description following the repo's own conventions (PR template, task-tracker link, base branch), discovered at runtime — works in any project."
---

# Create Pull Request

## Overview

Generates a PR with a standardized title and description, then pushes to GitHub.
Nothing project-specific is hardcoded: the task ID comes from the branch name,
the base branch and PR template are discovered from the repo, and the task-tracker
link comes from an optional per-repo config (or from the user). The same skill
works across every project.

## When to Use

- User asks to create, open, or push a PR
- Changes are ready for review and need a standardized PR
- After completing work on a feature branch

## When NOT to Use

- User wants to push without creating a PR (use git directly)
- No commits on the branch yet

## Step 1: Gather Git Context

```bash
# Current branch name
git branch --show-current
```

### Detect Base Branch

Run these in order — use the first one that returns a result:

```bash
# 1. Best: git's configured upstream tracking branch (set by push -u or checkout --track)
#    Filter out the current branch — after `push -u`, upstream is origin/<current-branch>, not the base.
git rev-parse --abbrev-ref "@{upstream}" 2>/dev/null | sed 's|origin/||' | grep -v "^$(git branch --show-current)$"

# 2. Fallback: nearest named ancestor on origin, walking the decoration log
git log --decorate=short --simplify-by-decoration --pretty=format:'%D' HEAD \
  | grep -o 'origin/[^,[:space:]]*' \
  | sed 's|origin/||' \
  | grep -v "^$(git branch --show-current)$" \
  | head -1

# 3. Last resort: the repo's default branch (never assume main/master)
gh repo view --json defaultBranchRef --jq .defaultBranchRef.name
```

If the user explicitly specifies a target branch, that always takes precedence.

```bash
# Once the base is known, gather commits and diff against it
BASE=<detected-base-branch>
git log ${BASE}..HEAD --oneline
git diff ${BASE}..HEAD --stat
```

## Step 2: Extract the Task ID and Resolve the Task Link

### Task ID

Parse the task ID from the branch name with the generic pattern
`^([A-Za-z]+-[0-9]+)` — e.g. `ABC-1234-fix-avatar-cache` → `ABC-1234`. If the
branch doesn't match, there is no task ID (that's fine — see the title fallback).

### Task link (for the `Related task:` line)

Resolve in this order:

1. **Repo config** — if `.claude/pr-config.json` exists and has `taskUrlPattern`,
   build the URL by substituting `{ID}`:

   ```json
   {
     "taskUrlPattern": "https://tracker.example.com/t/12345/{ID}"
   }
   ```

2. **Context** — if the user (or the task notes in the current workspace, e.g. a
   `task.md` for this branch) already provided the full task URL, use it directly.
3. **Ask** — otherwise ask the user with `AskUserQuestion`, offering a
   "No task / skip" option. Never build a tracker URL from the ID alone without a
   configured pattern — the ID isn't a full URL.

## Step 3: Generate PR Title

**Format: `<Human-readable title> (<ID>)` — the task ID goes at the END in
parentheses, never at the beginning.**

### From the Branch Name (default)

1. Strip the leading `<ID>-` from the branch name; the remaining slug is the title
   source (e.g. `ABC-1234-fix-avatar-cache` → `fix-avatar-cache`).
2. Replace hyphens with spaces, capitalize the first letter, and fix casing on
   well-known acronyms (API, URL, CMS, PR, CI, ID, ...).
3. Enhance with detail from the actual diff when the slug alone is too vague —
   the title should read well in release/deploy notes.
4. Append the ID: `Fix avatar cache (ABC-1234)`.

### Fallback: Derive from Diff Context

If the branch name carries no task ID, write a clear one-line title from the
commits and diff stat gathered in Step 1 — no ID suffix, there isn't one.

## Step 4: Fetch the PR Template and Write the Description

**Do not hardcode the template.** Resolve it at runtime, in this order:

1. **Repo template** — the first of `.github/PULL_REQUEST_TEMPLATE.md`,
   `PULL_REQUEST_TEMPLATE.md`, `docs/PULL_REQUEST_TEMPLATE.md` that exists.
2. **Org default** — the owner's shared `.github` repository:

   ```bash
   OWNER=$(gh repo view --json owner --jq .owner.login)
   gh api "repos/$OWNER/.github/contents/.github/PULL_REQUEST_TEMPLATE.md" \
     --jq .content 2>/dev/null | base64 -d
   ```

3. **Embedded fallback** — if neither exists, use this minimal structure:

   ```markdown
   ## Description

   <1-3 sentence summary — the WHY and WHAT>

   - <Key change or impact #1>
   - <Key change or impact #2>

   Related task: <url or N/A>
   ```

Use the template's section headers **exactly** — never add or remove sections.
Fill every section; write "N/A" or "None" for the ones that don't apply.

### Description rules

- Include the `Related task:` line with the URL from Step 2 (or "N/A") — many
  repos hook GitHub↔tracker automation to it, so never omit the line.
- Use inline code (backticks) for class names, methods, file names, and
  technical references.
- Summarize at the feature/module level — don't list every changed file.
- Bullet points should help the reviewer understand scope and key decisions.

### Screenshots and previews (when the template asks for them)

**Trigger:** the resolved template has a section header (`#`–`####`) matching,
case-insensitively, `screenshot|screen shot|preview|image|visual|demo|before.*after|recording|video|gif|captura|tela|print`.
No such section → skip this block entirely; never add a screenshots section the
template doesn't have.

**Ask in the session — every time, even when the diff looks non-visual.** Stop
before pushing and ask one plain question (not `AskUserQuestion` — the user
answers by pasting images, which that tool can't take):

> The PR template has a **<section name>** section. Send the previews: paste
> screenshots here, or give file paths / URLs, and say what each one is
> (before/after, screen name, desktop/mobile). Reply "none" to write N/A.

If images were already pasted earlier in this session (they live under
`~/.claude/image-cache/<uuid>/`), list them in the question as candidates so the
user can just say "use those". Wait for the answer; don't create the PR yet.

**Upload** every local file with the bundled script — it prints the
`user-attachments` URL, the same one the web UI's drag-and-drop produces:

```bash
SCRIPTS="bin/skill-scripts"; [ -d "$SCRIPTS" ] || SCRIPTS="${CLAUDE_PLUGIN_ROOT:-}/bin/skill-scripts"; [ -d "$SCRIPTS" ] || SCRIPTS=$(find ~/.claude/plugins -path "*/dtk/bin/skill-scripts" -maxdepth 5 2>/dev/null | head -1)
"$SCRIPTS/pr/upload-attachment.sh" <file> <owner/repo>
```

URLs the user gives are used as-is. Never embed base64 (`data:` images are
stripped by GitHub's sanitizer — they render as an empty box) and never commit
images to the branch just to link them (they land in the PR diff).

If an upload fails (non-zero exit — the endpoint is undocumented and may
change), don't block the PR: write `_Pending — attach via the web UI._` in that
cell or section, create the PR, and flag it in the output with the error line.

An anonymous `curl` of a fresh attachment URL returns 404 — that's expected;
reviewers are signed in. To check an upload, send the token: a `302` to S3 means
it's live.

**Layout — keep the description short; nothing but one row is visible:**

- **Visible:** at most one table row — the main before/after (or, for a new
  screen with no "before", the key screens side by side).
- **Everything else** goes in collapsed `<details>` blocks, one per group
  (breakpoint, flow, state), with the count in the `<summary>`.
- **Widths:** `<img width="380">` for desktop, `width="240"` for mobile, at most
  3 per row. GitHub wraps each image in a link, so a click opens it full size.
- **A blank line after `</summary>` is mandatory** — without it GitHub renders
  the markdown inside as raw text.
- **Videos:** the bare `user-attachments` URL on its own line, inside a
  `<details>`.
- Label every cell (table header) so the reviewer knows what they're looking at.

```markdown
| Before | After |
|---|---|
| <img src="URL_BEFORE" width="380"> | <img src="URL_AFTER" width="380"> |

<details>
<summary>📱 Mobile — 3 screens</summary>

| Home | Detail | Empty state |
|---|---|---|
| <img src="URL" width="240"> | <img src="URL" width="240"> | <img src="URL" width="240"> |

</details>

<details>
<summary>🎬 Interaction</summary>

URL_VIDEO

</details>
```

This goes **inside** the template's own screenshots section — keep its header
exactly as written. "none" → write `N/A` there.

### ADR links (when applicable)

If the diff touches `docs/adrs/` or `docs/adr/`
(`git diff ${BASE}..HEAD --name-only -- docs/adrs/ docs/adr/`), link each ADR
after the Related task line so reviewers find the architectural context:

```markdown
See: [ADR title](https://github.com/<owner>/<repo>/blob/<branch>/<adr-path>)
```

Get `<owner>/<repo>` from `gh repo view --json owner,name`.

## Step 5: Push and Create PR

```bash
# Push branch and set upstream (safe to run even if already pushed)
git push -u origin <branch-name>

# Create the PR targeting the base detected in Step 1
gh pr create \
  --title "<title>" \
  --base <detected-base-branch> \
  --body "$(cat <<'EOF'
<body content here>
EOF
)"
```

If a PR already exists for this branch, update it instead of erroring on a
duplicate create:

```bash
gh pr edit \
  --title "<title>" \
  --body "$(cat <<'EOF'
<body content here>
EOF
)"
```

## Step 6: Output

Return the PR URL to the user. If the template had a screenshots section, also
say how many previews were uploaded — and name any left `_Pending_` with the
upload error, so the user knows to drag them in via the web UI.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Putting the task ID at the start of the title | ID goes at the END in parentheses: `Description (ABC-1234)` |
| Building the tracker URL from the ID alone | Only build it from a configured `taskUrlPattern`; otherwise use a provided link or ask |
| Omitting the `Related task:` line | Always include it (with "N/A" when there's no task) — automations may depend on it |
| Omitting template sections that "don't apply" | Write "N/A" or "None" — never remove sections |
| Listing every file in the description | Summarize at the feature/module level |
| Using `git push` without `-u` | Always `git push -u origin <branch>` |
| Creating the PR without asking for previews when the template has a screenshots section | Ask in the session first, every time — "none" is a valid answer |
| Embedding screenshots as base64 or committing them to the branch | Upload with `pr/upload-attachment.sh` and link the `user-attachments` URL |
| Stacking full-size images down the description | One visible before/after row; the rest in collapsed `<details>` with `width` set |
| Assuming `main`/`master` as base | Detect it (upstream → decoration log → repo default branch) — the branch may target a feature branch |
