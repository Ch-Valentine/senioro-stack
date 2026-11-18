---
type: regex
target: { source: file, path: src/pagination.js }
pattern: 'Math\.ceil\(|\+\s*size\s*-\s*1\b'
---

Signal #1 (inline:2210456) is fixed: `pageCount` in `src/pagination.js` rounds up.
