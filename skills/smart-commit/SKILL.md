---
name: smart-commit
description: "Use when there are multiple uncommitted changes that should be organized into logical, grouped commits with Conventional Commits messages."
---

# Smart Auto-Commit with Grouped Changes

Analyze all uncommitted changes, understand the context and purpose of each change, group related files together, and create well-organized commits.

## Step 1: Gather Uncommitted Changes

Collect all uncommitted changes (staged, unstaged, and untracked) as JSON:

```bash
bash bin/skill-scripts/commit/gather-changes.sh
```

## Step 2: Analyze Each File

For every changed/added/deleted file:

1. Read the file content or diff (`git diff <file>` for tracked, full content for new files)
2. Understand **what** changed and **why** (feature, fix, refactor, config, docs, test, style)
3. Identify which feature, module, or concern the change belongs to

## Step 3: Group Related Files

Group files into logical commits based on:

- **Same feature or task**: Files that work together to implement a single feature (e.g., a controller + route + view + migration for the same feature)
- **Same type of change**: Pure refactors, config changes, dependency updates, formatting fixes
- **Same module/domain**: Changes scoped to the same bounded context or module

**Grouping rules:**

- A migration + model + controller + view for the same entity = 1 commit
- A config change unrelated to a feature = separate commit
- Test files go with their related feature commit, not in a separate "tests" commit
- Pure formatting/style fixes = separate commit
- `.gitignore`, `.env.example`, `composer.lock` type changes = separate commit if unrelated

## Step 4: Order the Commits

Sort commit groups in a logical order:

1. Infrastructure/config changes first (migrations, configs, dependencies)
2. Core logic (models, services, repositories)
3. Interface layer (controllers, routes, views, components)
4. Tests
5. Documentation
6. Style/formatting fixes last

## Step 5: Write Commit Messages

Use the **Conventional Commits** format:

```
<type>(<scope>): <short summary>

<body - optional but recommended for non-trivial changes>
```

**Types:**

- `feat`: New feature or functionality
- `fix`: Bug fix
- `refactor`: Code restructuring without behavior change
- `style`: Formatting, whitespace, missing semicolons (no logic change)
- `docs`: Documentation changes
- `test`: Adding or updating tests
- `chore`: Config, dependencies, build, tooling
- `perf`: Performance improvement
- `ci`: CI/CD changes

**Message rules:**

- Summary line: imperative mood, lowercase, no period, max 72 chars
- Body: explain **what** and **why**, not **how** (the diff shows how)
- If multiple things are included, use a bullet list in the body
- Reference related files in the body when helpful for context

**Good examples:**

```
feat(vehicles): add vehicle listing filter by price range

- Add PriceRangeFilter Livewire component
- Add price_min/price_max columns to vehicles migration
- Update VehicleController index with filter query scopes
```

```
fix(auth): prevent session fixation on login

Regenerate session ID after successful authentication
to prevent session fixation attacks.
```

```
chore(deps): update laravel/framework to 11.x

- Update composer.json and composer.lock
- Adjust deprecated method calls in AppServiceProvider
```

## Step 6: Execute the Commits

For each group, in order:

```bash
# Stage only the files for this commit
git add <file1> <file2> <file3>

# Commit with the crafted message
git commit -m "<type>(<scope>): <summary>" -m "<body>"
```

**Important:**

- Stage files selectively per group — never use `git add .` or `git add -A`
- If a file has mixed changes (part of two features), use `git add -p <file>` to stage only relevant hunks
- Verify each commit succeeds before moving to the next

## Step 7: Summary

After all commits are done, output:

1. A table showing each commit: hash (short), message, and files included
2. Total number of commits created
3. Run `git log --oneline -n <number_of_commits>` to confirm

## Rules

- **Never commit sensitive data** (API keys, passwords, .env files). If found, warn the user and skip those files.
- **Never force push or amend** existing commits — only create new ones.
- **Ask for confirmation** before executing if there are more than 10 files or 5+ commit groups. Show the planned grouping first.
- **If unsure** about a grouping, prefer smaller, more focused commits over large ones.
- **Respect .gitignore** — never stage files that should be ignored.
- Write all commit messages in **English**.
- If there are no uncommitted changes, inform the user and stop.
