# Peer Review — PR #102

## Recommendation: ⚠️ Approve with Comments

**Summary:** Small, focused PR. One edge in the coupon math and one question on the mailer.

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
