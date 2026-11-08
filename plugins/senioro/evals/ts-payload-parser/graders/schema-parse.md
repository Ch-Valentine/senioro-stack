---
type: regex
target: { source: file, path: src/webhook.ts }
pattern: '(?<!JSON)\.parse\('
---

`src/webhook.ts` calls a schema `.parse(` (the `JSON.parse(` call does not count).
