---
name: review-spec-plan
description: "Reviews a spec or plan in four gated stages (need or root cause, solution design, impact, spec quality) with one reviewer seat per pass, stopping at the first failing stage; a passed stage is frozen. Use when a spec or plan should be reviewed before it is built or its issues are resolved."
disable-model-invocation: true
user-invocable: true
argument-hint: "[spec-or-plan-path] [base-sha]"
allowed-tools: Agent, Bash, Read, Edit
effort: high
---

# Spec/Plan Review

Runs one review pass on the spec or plan at `$0`. The stages, lenses, round rules and Status line live in orchestrate's Spec review section, which this file reads and does not copy. Read-only on the target except its Status line.

Wallet: ${user_config.wallet} (unset, unknown or still literal text: sushi). The pass seat gets `model` from the spec review pass row and the wallet's column in the table printed by `sed -n '/^## Route the seat/,/^## Brief/p' "${CLAUDE_PLUGIN_ROOT}/skills/orchestrate/SKILL.md"`.

1. Target: `$0` as an absolute path. Ask when it is missing; for a directory, list its `.md` files and ask. A base `$1` makes this a re-review: the pass reads only `git diff $1 -- <target>`, and an empty diff is BLOCKED, never a full review.
2. Print `sed -n '/^## Spec review/,/^## /p' "${CLAUDE_PLUGIN_ROOT}/skills/orchestrate/SKILL.md"` and follow it; in the printed text `$`+`{CLAUDE_PLUGIN_ROOT}` means ${CLAUDE_PLUGIN_ROOT}, so write resolved paths into the brief. The first unfrozen stage and the round come from this conversation (earlier passes, `Stage <n> frozen` or `fixed` lines), else from the target's `Review:` Status clause, else stage 1, round 1.
3. Spawn one `senioro:investigator` with a brief of MODEL, GOAL, READ, RULES, REPORT FILE and RETURN lines. READ names the target, the section's `sed` command, `${CLAUDE_PLUGIN_ROOT}/skills/orchestrate/references/stages.md`, the stage, the round and the base. The report file is `$HOME/.cache/senioro-tl/runs/${CLAUDE_SESSION_ID}/reports/spec-pass-<n>.md`, written absolute (`mkdir -p` its directory).
4. Print the report's roster. A failing stage ends with `Next: /senioro:resolve-plan-issues <spec>`.
5. When stage 4 passes, or the loop stops for the user, write the Status line once, as the section says.
