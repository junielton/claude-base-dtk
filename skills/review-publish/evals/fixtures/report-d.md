# Peer Review — PR #104

## Recommendation: ⚠️ Approve with Comments

**Summary:** Second pass after the author pushed fixes. CI is red on the phpcs job, so the author still has to rebase onto main and re-run it.

---

## 🔴 Blocking

None.

---

## 🟡 Non-blocking

### `resources/js/cart.js:8` — Coupon can push the total below zero
```js
return { ...cart, total: cartTotal(cart) - coupon.amount };
```
When `coupon.amount` exceeds the cart total the checkout shows a negative total. Clamping the result at 0 keeps it valid.

**Verifier:** kept

---

## 💬 Questions

### `app/Services/InvoiceMailer.php:17` — `sent_at` stamped right after `send()`
```php
$invoice->update(['sent_at' => now()]);
```
Is `sent_at` meant to mean "handed to the mailer" or "delivered"? If the mail is queued later, the invoice reads as sent before it left.

**Verifier:** kept

---

## Existing Review Comments

### @copilot — `app/Http/Controllers/OrderExportController.php:18` — eager load the customer relation
**Verdict:** Valid
Copilot is right that the relation is loaded per row; the author replied that it is fixed in the next push.

### @dberri — `resources/js/cart.js:3` — name the reducer
**Verdict:** Not applicable
Style preference, already resolved by the author.

## Lessons Applied
- Lesson 12 (money as integer cents) applied to the export total.

---

## Reconciliation with Previous Reviews

### Resolved since last review
- `app/Services/InvoiceMailer.php:12` — missing return type (was: peer-review-1, now: resolved)

### Still pending
- `app/Http/Controllers/OrderExportController.php:12` — export is empty without a status (since peer-review-1)

### New in this review
- `resources/js/cart.js:8` — coupon can push the total below zero

### Previous decisions respected
- `app/Models/Order.php:40` — "out of scope" (decided in peer-review-1)

## Final Summary
- Findings verified: 2 kept, 0 refuted by `dtk-review-verifier`
- CI: the phpcs job is failing on the PR branch; the author needs to rebase onto main.
