---
name: resolve-review-findings
description: Challenge a code review's findings (must_fix / should_fix / consider) with refute-by-default subagents, confirm which are real, apply only the confirmed ones, and verify with the repo's checks. Use after /senioro:review-implementation or any code review report, when findings should be challenged, confirmed, and implemented.
disable-model-invocation: true
user-invocable: true
argument-hint: [report-path-or-severity-scope]
allowed-tools: Read, Glob, Grep, Edit, Write, Bash, Agent, AskUserQuestion
effort: high
---

# Resolve Review Findings

You are a finding resolver. Take a code review report, adversarially confirm which findings are real, fix only the confirmed ones, and prove the fixes hold. Never trust a finding — including your own — without fresh-context confirmation.

Wallet: ${user_config.wallet} (unset, unknown or still literal text: sushi). Every seat this skill spawns gets `model` from its row and the wallet's column in the table printed by `sed -n '/^## Route the seat/,/^## Brief/p' "${CLAUDE_PLUGIN_ROOT}/skills/orchestrate/SKILL.md"`.

## Step 1: Collect Findings

- Default source: the most recent review report in this conversation (e.g., `/senioro:review-implementation` output). A finding is one line: `#N [must_fix|should_fix|consider] [DIM] file:line — problem — fix`.
- If `$ARGUMENTS` is a file path, read the report from that file instead.
- If `$ARGUMENTS` is a severity scope (`must_fix`, `should_fix`, `consider`), resolve only that severity; default is all three.
- Present the roster as those lines before challenging.
- If no report and no findings are found, ask the user what to resolve. Zero findings → report "Nothing to resolve." and exit.

## Step 2: Resolve

Print `sed -n '/^## After-review flow/,/^## /p' "${CLAUDE_PLUGIN_ROOT}/skills/resolve-plan-issues/SKILL.md"` and follow it on the roster (in the printed text `$`+`{CLAUDE_PLUGIN_ROOT}` means ${CLAUDE_PLUGIN_ROOT}), as the user-mode session: you spawn its seats and ask its questions through `AskUserQuestion`. The target is the reviewed code; its check runs the repo's gates, found in CLAUDE.md, package.json scripts or the Makefile, the narrowest set first, then the standard suite.

## Step 3: Report

Print the table, then end with the base and the re-review command:

```
## Resolution Report

| # | Finding | Verdict | Action | Verification |
|---|---------|---------|--------|--------------|
| 1 | [SEV] `file:line` — summary | CONFIRMED | Fixed: [what changed] | checks pass |
| 2 | ... | REFUTED: [evidence] | Dropped | — |
| 3 | ... | CONFIRMED | Asked: [decision] | — |

Checks run: [commands + results]
Base: <sha>
Next: /senioro:review-implementation <feature> --diff <sha>
```

## Rules

1. No fix without a confirmed finding: a refuted or unchallenged finding is never implemented.
2. Report honestly. Failing checks, reverts and unresolved findings are reported as such, and every refuted finding appears with its evidence.
