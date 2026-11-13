---
repo: acme/shop
from: 2026-11-06
to: 2026-11-13
lang: en
generated_at: 2026-11-13T18:00:00Z
prs: [15, 22, 30]
---

## acme/shop: 2026-11-06 to 2026-11-13

**Headlines**
- Checkout now retries a failed payment call instead of showing an error.
- The retry shipped with one bug, fixed three days later.
- A docs change records why retries stop after three attempts.

### Checkout retries failed payment calls

The week's main change is a [retry loop](https://github.com/acme/shop/blob/2f3a3a8a4ab5a0809b7045754bffddf8ffbce2ad/src/retry.sh) around the payment call, introduced in [#15](https://github.com/acme/shop/pull/15). A follow-up, [#22](https://github.com/acme/shop/pull/22), fixed the loop so it stops after the third attempt instead of looping forever.

**What changes for you**
- A payment call that fails now retries up to three times before the error shows.

**Left open**
- Nobody has measured how long the retries add to a slow checkout.

### Retry limit decision

[#30](https://github.com/acme/shop/pull/30) records in the docs why three attempts was chosen.

### Also merged
- [#31](https://github.com/acme/shop/pull/31) bumps the linter to 9.1.
