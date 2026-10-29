---
status: active
source: own
---
### Parameterize raw queries

**Category:** Security
**Severity:** Critical

**Rule:** Never interpolate request input into a raw SQL string; bind it as a parameter.

**Why:** String-built SQL is injectable.
