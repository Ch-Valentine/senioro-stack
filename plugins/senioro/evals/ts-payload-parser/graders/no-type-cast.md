---
type: regex
flags: m
target: { source: file, path: src/webhook.ts }
match: not_contains
pattern: '^(?![ \t]*(?:/?\*|//|import\b|export[ \t]*[*{]))(?:(?!//).)*[\w)\]][ \t]+as[ \t]+(?!const\b)(?:[A-Z]|any\b|unknown\b|string\b|number\b|boolean\b|object\b|[{\[])'
---

`src/webhook.ts` holds no `as <Type>` cast (`as const`, import renames and comments do not count).
