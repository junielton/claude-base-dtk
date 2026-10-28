// Checkout amounts arrive from the form as strings ("19.99", "19,99", "20").
export function toCents(input) {
    const normalized = String(input).trim().replace(',', '.');
    const amount = Number(normalized);

    if (!Number.isFinite(amount)) {
        throw new TypeError(`not a money amount: ${input}`);
    }

    return Math.round(amount * 100);
}

export function sumCents(items) {
    return items.reduce((total, item) => total + toCents(item.price) * item.qty, 0);
}
