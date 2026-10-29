# Worktree manifest

This plugin has no build step and no runtime dependencies. A fresh worktree is usable as-is.

## Verify

```bash
bash skills/review-publish/tests/run-tests.sh      # tone-lint + post-review (offline, stub gh)
node --test scripts/design-panel/tests/*.test.mjs  # design-panel scripts
python3 scripts/review/outcomes.py --self-test
claude plugin validate --strict .                  # manifest + frontmatter lint
```

## Notes

- `agents/evals/dtk-review-verifier/run.sh` and `skills/*/evals/` call the Claude CLI and cost tokens; run them only when the unit changes what they cover.
- Never install node/python packages into this repo; scripts use built-ins only.
