import { test } from 'node:test';
import assert from 'node:assert/strict';
import { toCents, sumCents } from '../../resources/js/money.mjs';

test('toCents keeps the cent on .99 amounts', () => {
    assert.equal(toCents('19.99'), 1999);
    assert.equal(toCents('0.29'), 29);
});

test('toCents accepts a comma decimal separator', () => {
    assert.equal(toCents('19,99'), 1999);
});

test('toCents rejects non-numeric input', () => {
    assert.throws(() => toCents('abc'), TypeError);
});

test('sumCents multiplies by quantity', () => {
    assert.equal(sumCents([{ price: '19.99', qty: 3 }, { price: '0.29', qty: 1 }]), 6026);
});
