---
status: candidate
source: peer
---
### Validate empty payloads

**Category:** QA
**Severity:** Medium

**Rule:** Reject an empty request body with a 422 before touching the service layer.

**Why:** Empty payloads reach code that assumes fields exist.
