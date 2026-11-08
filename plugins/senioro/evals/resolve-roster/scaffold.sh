#!/usr/bin/env bash
# Eval fixture (spec 002 U9, case 2): a committed cart module and a review report with three findings.
#   #1 must_fix   src/cart.js:6      real: the loop bound reads one item past the end
#   #2 should_fix src/discount.js:5  real: pct is a whole number, the code treats it as a fraction
#   #3 should_fix src/cart.js:15     false: averagePrice already guards the empty cart at line 14
# The graders in graders/ pin these ids and lines: keep them when editing this file.
set -euo pipefail

git init -q -b main
git config user.name "Eval Fixture"
git config user.email "eval@example.invalid"
git config commit.gpgsign false

mkdir -p src test

cat > package.json <<'EOF'
{
  "name": "cart-totals",
  "private": true,
  "scripts": { "test": "node --test" }
}
EOF

cat > src/cart.js <<'EOF'
'use strict';

// Sum of price * qty over all line items, in cents.
function subtotal(items) {
  let sum = 0;
  for (let i = 0; i <= items.length; i++) {
    sum += items[i].price * items[i].qty;
  }
  return sum;
}

// Mean line price in cents, 0 for an empty cart.
function averagePrice(items) {
  if (items.length === 0) return 0;
  return items.reduce((s, it) => s + it.price, 0) / items.length;
}

module.exports = { subtotal, averagePrice };
EOF

cat > src/discount.js <<'EOF'
'use strict';

// Price in cents after taking pct percent off. percentOff(200, 25) is 150.
function percentOff(price, pct) {
  return price - price * pct;
}

module.exports = { percentOff };
EOF

cat > test/cart.test.js <<'EOF'
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { subtotal, averagePrice } = require('../src/cart');
const { percentOff } = require('../src/discount');

test('subtotal sums price times qty', () => {
  assert.strictEqual(subtotal([{ price: 100, qty: 2 }, { price: 50, qty: 1 }]), 250);
});

test('averagePrice of an empty cart is 0', () => {
  assert.strictEqual(averagePrice([]), 0);
});

test('percentOff takes a whole-number percent off', () => {
  assert.strictEqual(percentOff(200, 25), 150);
});
EOF

cat > review-report.md <<'EOF'
# Review: cart totals

#1 [must_fix] [SAFETY] src/cart.js:6 — the loop bound `i <= items.length` reads one item past the end, so subtotal throws a TypeError on `items[i].price` — change the bound to `i < items.length`
#2 [should_fix] [COMPLETENESS] src/discount.js:5 — percentOff subtracts `price * pct`, so percentOff(200, 25) is -4800 instead of the 150 its comment and test expect — divide pct by 100
#3 [should_fix] [SAFETY] src/cart.js:15 — averagePrice divides by items.length with no empty-cart guard, so an empty cart gives NaN — return 0 when items is empty
EOF

git add -A
git commit -q -m "Add cart totals and discount"
