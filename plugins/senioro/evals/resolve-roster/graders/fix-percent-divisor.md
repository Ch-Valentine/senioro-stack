---
type: regex
target: { source: file, path: src/discount.js }
pattern: '/\s*100\b|\*\s*0?\.01\b'
---

Finding #2 is fixed: `src/discount.js` divides the percent by 100.
