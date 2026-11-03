# Peer Review — PR #106

## Recommendation: ⚠️ Approve with Comments

**Summary:** Small, focused PR. One edge in the coupon math and one question on the mailer.

## TL;DR

Applies a coupon to the cart total and stamps an invoice as sent once the mailer returns.

- ! Not proven: the coupon path has no test; the author only clicked through it on staging (body, Testing)
- ! Risk: invoices read as sent before the queue delivers them, so the finance export counts undelivered mail (`InvoiceMailer.php:17`; raised as a Question)

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

None.

## Lessons Applied
- None relevant.

## Final Summary
- Findings verified: 2 kept, 0 refuted by `dtk-review-verifier`
- TL;DR lines: 2, of which 1 raised as Questions
