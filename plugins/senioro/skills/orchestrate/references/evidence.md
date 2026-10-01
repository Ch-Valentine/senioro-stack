# orchestrate — evidence

Why each rule in SKILL.md exists. For maintainers; never loaded at runtime.

## Sources

- Official: skills (`hooks`, `effort`, `model` frontmatter; `${CLAUDE_SESSION_ID}`), sub-agents (per-call `model` beats frontmatter; `effort` pinned per seat; live reload of agent files), hooks (`agent_id` present only inside subagents; exit 2 blocks) — https://code.claude.com/docs/en/skills, /sub-agents, /hooks, /model-config.
- Anthropic engineering: the four-part task contract (objective, output format, tools/sources, boundaries) and 1–2k-token distilled reports — https://www.anthropic.com/engineering/multi-agent-research-system, /effective-context-engineering-for-ai-agents.
- Community: over-claiming and zero-tool-use reports — https://github.com/anthropics/claude-code/issues/39981, https://github.com/anthropics/claude-code/issues/67730.
- Community: inline reports overflowing the parent — https://github.com/anthropics/claude-code/issues/23463.
- Community: soft delegation rules ignored — https://github.com/anthropics/claude-code/issues/18352, https://github.com/anthropics/claude-code/issues/5528.
- Community: subagents never see memory/skills/history — https://github.com/anthropics/claude-code/issues/41356.
- Community: model discipline and file-based reports (obra/superpowers `subagent-driven-development`) — https://github.com/obra/superpowers/blob/8ca22db/skills/subagent-driven-development/SKILL.md

## Claude Code behaviour the rules rely on (docs, 2026-09-29)

Claude Code docs (v2.1.285, 2026-09-29) — https://code.claude.com/docs/en/sub-agents, /skills, /hooks, /model-config, /workflows, /context-window:
- A subagent's final message enters the parent in full; the parent's prompt stays in the parent's context.
- Skill bodies are re-attached after compaction (up to 5K tokens per skill, 25K total).
- `CLAUDE_CODE_EFFORT_LEVEL` overrides skill and agent `effort` frontmatter; skill `effort` likely applies only to the invoking turn.
- Only a Workflow's return value reaches the parent; an inline `script` enters it, `scriptPath`/`name` do not. Saved workflows may live in `~/.claude/workflows/`.
- Nested subagents default to 3 levels; seats without the `Agent` tool cannot spawn.
- Task tools are off by default on 5.x models (`CLAUDE_CODE_ENABLE_TODO_TOOLS=1`).

## Patterns from public orchestration skills

- obra/superpowers: append-only one-line progress log read only on resume; one canonical plan, per-task brief files passed by path; report files with ≤ 15-line returns; orchestrator-as-subagent measured cheaper at the median. https://github.com/obra/superpowers/blob/8ca22db/skills/subagent-driven-development/SKILL.md
- mattpocock/skills: no ledger (state = tickets + git); pointers in both directions; reviewers under 400 words; the orchestrator must not debug; seats spawning agents burned ~450K tokens; past ~100K tokens is the "dumb zone". https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60
- addyosmani/agent-skills: state = spec + plan checkboxes + git; one path per artifact; at most 3 review rounds, never re-review an unchanged artifact; skip parallel review at ≤ 2 files and < 50 lines; move sources out verbatim, not rewritten. https://github.com/addyosmani/agent-skills/tree/2686b620fc1fed2e8f60c704839c766b8594c6b6

## Rule → rationale

1. Hands off the tree — everything the TL reads stays in its context, and soft delegation rules get ignored, so a hook enforces it (hooks docs: exit 2 blocks; claude-code issues 18352, 5528).
2. One copy of every artifact — no repo path is TL-owned; TL files live in the run dir, and seats edit the canonical file in place (addyosmani/agent-skills: one path per artifact; obra/superpowers: one canonical plan).
3. No ledger — progress lives in the TL's context plus the real artifacts, which already hold the durable state (mattpocock/skills: state = tickets + git; addyosmani/agent-skills: spec + checkboxes + git; docs: skill bodies are re-attached after compaction).
4. Short briefs, capped reports in files — pointers instead of pasted content, full reports in files, a few lines back; a subagent's final message enters the parent in full (Anthropic engineering: task contract, distilled reports; claude-code issue 23463; obra/superpowers: brief files by path, ≤ 15-line returns; claude-code issue 41356: seats never see memory, so briefs must point at it).
5. Cheapest capable seat, `model` on every spawn, no built-in agents for work — per-call `model` beats frontmatter and effort is pinned per seat; built-in agents return uncapped reports; `senioro:architect` runs on opus at high effort, writes only its design file, and a blind critic reviews each design (sub-agents docs; obra/superpowers: model discipline).
6. Batch by shared reads; pipelines of 3 or more seats as a Workflow by `scriptPath` — only a Workflow's return value reaches the parent, and its script must sit where the session can read it, such as the run dir (docs: workflows, sub-agents).
7. One question at a time — decisions by proxy: a roster, then one question per decision, then one implementer applies them all and one verifier checks the diff.
8. Refute-by-default verification — seats over-claim and report without tool use, so no self-report ships; one sonnet verifier by default, a second blind opus verifier only for a refuted must_fix or a security-sensitive roster; a review of the rewrite with one reviewer seat confirmed findings this way (claude-code issues 39981, 67730; addyosmani/agent-skills: at most 3 review rounds).
9. Say seats × models before launching; stop escalating after two misses — seats spawning agents burn tokens fast, and nesting is capped (mattpocock/skills; docs: nested subagents default to 3 levels).
10. Never debug yourself; suggest `/compact` at phase boundaries — the orchestrator must not debug, and reasoning degrades past ~100K tokens (mattpocock/skills; docs: context-window).
