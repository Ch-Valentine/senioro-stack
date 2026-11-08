---
name: ts-payload-parser
description: A TypeScript webhook payload parser and its commit message (spec 002 U9, case 3).
tags: [baseline, writing, typescript]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill]
append_system_prompt: |
  Sandbox note for this session: shell calls may contain only git commands. Anything else in a call (cat, ls, a loop, a subshell) is denied, so look at files with the Read, Glob and Grep tools.
---

The billing provider posts webhooks to us as a raw JSON string: an `event` that is either `invoice.paid` or `invoice.failed`, an `invoiceId` string and an `amountCents` number. Add `parseWebhookPayload(body: string)` in `src/webhook.ts`. It returns the typed payload and throws on a malformed body. Commit the change when it is done.
