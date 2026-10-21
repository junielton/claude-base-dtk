# Peer Review — PR #101

## Recommendation: ❌ Request Changes

**Summary:** Adds a CSV order export and an invoice mailer. The export drops its filter when `status` is absent; the rest is sound.

---

## 🔴 Blocking

### `app/Http/Controllers/OrderExportController.php:12` — Export is empty without a status
```php
$orders = Order::query()->where('status', $request->input('status'))->get();
```
When the request carries no `status`, `input('status')` is null and the query becomes `status IS NULL`, so the download is an empty file instead of every order. The filter should only apply when the param is present: `->when($request->filled('status'), fn ($q) => $q->where('status', $request->input('status')))`.

**Verifier:** kept

---

## 🟡 Non-blocking

### `app/Http/Controllers/OrderExportController.php:18` — Customer loaded once per row
```php
$order->customer->email,
```
The loop touches the `customer` relation on every order, one query each. `Order::with('customer')` loads them in one.

**Verifier:** kept

### `app/Services/InvoiceMailer.php:15` — Mail sent on the request path
```php
Mail::to($to)->send(new InvoiceReady($invoice));
```
`send()` is synchronous, so the request waits on the SMTP round trip and a mail failure fails the request. `queue()` moves it off the request path.

**Verifier:** kept

---

## 💬 Questions

None.

---

## Existing Review Comments

None.

## Lessons Applied
- None relevant.

## Final Summary
- Findings verified: 3 kept, 0 refuted by `dtk-review-verifier`
