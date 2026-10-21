# Peer Review — PR #105

## Recommendation: ⚠️ Approve with Comments

**Summary:** One edge in the coupon math, one question on the mailer, and an unverified note on the export loop.

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

### `app/Http/Controllers/OrderExportController.php:18` — Customer loaded once per row
```php
$order->customer->email,
```
The loop touches the `customer` relation on every order, one query each. `Order::with('customer')` loads them in one.

**Verifier:** not checked (the verifier was not dispatched for this finding)

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
- Findings verified: 2 kept, 0 refuted, 1 not checked by `dtk-review-verifier`
