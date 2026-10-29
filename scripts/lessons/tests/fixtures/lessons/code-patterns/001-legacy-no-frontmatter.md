### Return early on guard clauses

**Category:** Code Patterns
**Severity:** Low

**Rule:** Return early from a function when a guard fails instead of nesting the happy path.

**Why:** Deep nesting hides the main path.
