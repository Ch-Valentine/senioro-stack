---
type: regex
target: { source: file, path: src/cart.js }
match: not_contains
pattern: '<=\s*items\.length'
---

Finding #1 is fixed: the loop in `src/cart.js` no longer runs to `items.length` inclusive.
