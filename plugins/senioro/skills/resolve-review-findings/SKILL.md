---
name: resolve-review-findings
description: Challenge a code review's findings (Must Fix / Should Fix / Consider) with refute-by-default subagents, confirm which are real, design and pre-validate fixes, apply only the confirmed ones, and verify with the repo's checks. Use after /senioro:review-implementation or any code review report, when findings should be challenged, confirmed, and implemented.
disable-model-invocation: true
user-invocable: true
argument-hint: [report-path-or-severity-scope]
allowed-tools: Read, Glob, Grep, Edit, Write, Bash, Agent, AskUserQuestion
effort: high
---

# Resolve Review Findings

You are a finding resolver. Take a code review report, adversarially confirm which findings are real, fix only the confirmed ones, and prove the fixes hold. Never trust a finding — including your own — without fresh-context confirmation.

## Step 1: Collect Findings

- Default source: the most recent review report in this conversation (e.g., `/senioro:review-implementation` output with `### Must Fix` / `### Should Fix` / `### Consider` sections).
- If `$ARGUMENTS` is a file path, read the report from that file instead.
- If `$ARGUMENTS` is a severity scope (`must-fix`, `should-fix`, `consider`), resolve only that severity; default is all three.
- Number every finding and present the roster before challenging:
  ```
  #N [SEVERITY] [DIMENSION] `file:line` — one-line summary
  ```
- If no report and no findings are found, ask the user what to resolve. Zero findings → report "Nothing to resolve." and exit.

## Step 2: Challenge the Findings (batched)

Spawn ONE batch challenge subagent for the whole roster — `model: "opus"`, refute-by-default. It reads the target files once and rules on every finding in a single session. Never spawn one subagent per finding: subagents share no prompt cache, so per-finding sessions re-pay the same file reads N times, and the independence that matters lives between *voters* (and between challenger and reviewer), not between *findings*. Do NOT challenge findings in-session: the context that produced or read the review defends its own conclusions; fresh context does not. Split the roster across parallel batch challengers only when findings live in unrelated file clusters with no shared reading.

Batch challenge prompt template:

> A code review of [feature/repo context] flagged the numbered findings below. For EACH finding independently, your default position is that it is WRONG. Read the referenced files plus related code, tests, and docs — read shared files once, then rule on every finding that cites them. Try to refute each: the code may already handle it, the behavior may be intentional and documented, the evidence may be misread, or the concern may be unreachable on any real path. Specs and docs win over reviewer opinion. Rule each finding on its own evidence — never let one verdict influence another, and do not drift into confirm-all or refute-all patterns. Respond with exactly one line per finding:
> - `#N CONFIRMED: [concrete evidence the problem is real]`
> - `#N REFUTED: [concrete evidence it is not]`
>
> [numbered roster — per finding: dimension, file:line, problem, evidence, suggested fix]

- **REFUTED** → drop the finding; keep the refutation evidence for the report. Never drop silently.
- **CONFIRMED** → continue to Step 3.
- Missing or hedged verdicts → re-ask the same subagent (SendMessage, context intact) for committed verdicts on just those findings; still ambiguous → treat as CONFIRMED but mark low-confidence and prefer escalation in Step 3.
- When a severity tier warrants a **double-check** (e.g. a stricter severity policy that double-checks `should_fix`), spawn a SECOND batch challenger, blind to the first, with the roster in REVERSE order (anchoring guard); such a finding is confirmed only if BOTH confirm it.

## Step 3: Design & Pre-Validate Fixes

For each confirmed finding:

1. **Design** the minimal fix that resolves it. No scope creep — fix the finding, not the neighborhood.
2. **Pre-validate before touching code:**
   - Does it actually resolve the confirmed problem?
   - Blast radius: Grep for callers/usages of everything the fix touches; check affected tests and contracts.
   - Does it introduce new issues — behavior changes, broken callers, contradictions with docs/specs?
3. **Route:**
   - Pre-validation clean → queue for Step 4.
   - Fix changes architecture, public contracts, or user-visible behavior (RECONSIDER-grade), or the confirmation is low-confidence → do NOT apply; escalate via AskUserQuestion with options and a recommendation.
   - No safe fix found → report as confirmed-but-unresolved with the reason.

## Step 4: Implement & Verify

- Apply queued fixes in severity order (Must Fix → Should Fix → Consider) with Edit/Write. Related findings touching the same code may be applied together; keep unrelated fixes separate.
- Run the repo's standard checks — discover them from CLAUDE.md, package.json scripts, or the Makefile (typecheck, tests, lint). Run the narrowest set covering the changed code first, then the standard suite.
- Re-read each fixed site and confirm the original finding no longer holds.
- On a failing check: fix forward if your change caused it and the correction is obvious; otherwise revert that fix and report it confirmed-but-unresolved. Never finish with failing checks.

## Step 5: Report

```
## Resolution Report

| # | Finding | Challenge | Action | Verification |
|---|---------|-----------|--------|--------------|
| 1 | [SEV] `file:line` — summary | CONFIRMED | Fixed: [what changed] | checks pass |
| 2 | ... | REFUTED: [evidence] | Dropped | — |
| 3 | ... | CONFIRMED | Escalated: [decision needed] | — |
| 4 | ... | CONFIRMED | Unresolved: [reason] | — |

Checks run: [commands + results]
```

If any fixes were applied, suggest re-running `/senioro:review-implementation` for a fresh verdict.

## Rules

1. **No fix without a confirmed finding.** Refuted or unchallenged findings are never implemented.
2. **Fresh-context challenges only.** Subagents challenge; the main session never confirms its own findings.
3. **Refute-by-default.** Challengers start from "this finding is wrong"; docs and specs beat reviewer opinion.
4. **Drop loudly.** Every refuted finding appears in the report with its refutation evidence.
5. **Minimal fixes.** Resolve the finding; don't refactor around it.
6. **Escalate architecture.** RECONSIDER-grade fixes and low-confidence confirmations need the user's decision — never auto-apply.
7. **Verified means checks pass.** A fix isn't done until the repo's checks pass and the fixed site re-reads clean.
8. **Batched challenges, deliberate fixes.** One challenger rules on the whole roster (two blind ones, second roster reversed, when double-checking); apply fixes sequentially in severity order.
9. **Report honestly.** Failing checks, reverts, and unresolved findings are reported as such — never smoothed over.
