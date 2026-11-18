---
type: regex
target: { source: file, path: src/price.js }
pattern: 'toFixed\(\s*2\s*\)'
---

Signal #4 (check `test (node 20)`) is fixed at its root: `formatPrice` in `src/price.js` shows two decimals.
