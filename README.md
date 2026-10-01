# senioro-stack

## What it is

A Claude Code plugin marketplace (`senioro-stack`) that ships one plugin, `senioro`: a Tech Lead mode for Claude Code. In TL mode the main session delegates every read, search, investigation and change to five seat agents with capped reports, keeps progress in its own compact context, routes each task to the cheapest model that cannot get it wrong, and asks the user one decision at a time. A strict-mode guard hook keeps the TL from touching the tree itself. The plugin also ships review and decision skills.

## Install

From GitHub:

```bash
claude plugin marketplace add Ch-Valentine/senioro-stack
claude plugin install senioro@senioro-stack
```

Local development:

```bash
claude plugin marketplace add <path-to-clone>
claude plugin install senioro@senioro-stack
```

A plugin from a local-directory marketplace loads in place: edit the files in the clone, then run `/reload-plugins` (or start a new session).

## Update

```bash
claude plugin update senioro@senioro-stack
```

Updates are manual. Auto-update is off by default for third-party marketplaces, and the plugin has no `version` field: the commit SHA tracks it.

## Components

Skills (three are model-invocable: Claude loads `technical-writing`, `typescript-best-practices` and `unslop` on its own when they apply; you invoke every other one yourself):

| Skill | Purpose | Model-invocable |
|---|---|---|
| `/senioro:orchestrate` | Tech Lead mode: delegate to the seats, decide, ask the user; arms the strict-mode guard. | No |
| `/senioro:review-implementation` | Deep review of a feature's implementation, with a structured verdict. | No |
| `/senioro:resolve-review-findings` | Challenge a code review's findings, confirm the real ones, apply and verify the fixes. | No |
| `/senioro:review-spec-plan` | Review a design spec or plan, with per-dimension ratings and a verdict. | No |
| `/senioro:resolve-plan-issues` | Resolve a plan's open issues: auto-fix trivial ones, walk through complex ones. | No |
| `/senioro:decide-step-by-step` | Resolve a plan's open decisions one by one, with a recommendation each. | No |
| `/senioro:bro` | Restate the last message in plain language, with no jargon. | No |
| `/senioro:unslop` | Cut AI tells from any writing. | Yes |
| `/senioro:technical-writing` | Layered technical-writing standard for docs, RFCs, READMEs, PR descriptions and commit messages. | Yes |
| `/senioro:typescript-best-practices` | TypeScript type-safety rules, loaded when working with `.ts` and `.tsx` files. | Yes |

Agents (spawned as `senioro:<name>`):

| Agent | Role | Model | Effort |
|---|---|---|---|
| `senioro:runner` | Run a command and digest it, locate files, run tests. No edits. | haiku | low |
| `senioro:verifier` | Rule on claims, findings or self-reports, refute-by-default. No edits. | sonnet | high |
| `senioro:investigator` | Research and root cause; facts separated from inferences. No edits. | opus | high |
| `senioro:architect` | Design: options, a recommendation, a split into gateable units. | opus | xhigh |
| `senioro:implementer` | Make exactly the briefed change and run the narrowest checks. | opus | high |

The TL passes a `model` on every spawn, which overrides the agent's default model. `resolve-plan-issues` hard-codes sonnet and opus for its own subagents.

## Prerequisites

- Claude Code (tested 2.1.286).
- `bash` and `jq`. Without jq the guard fails open.
- Access to the opus, sonnet and haiku models.
- The Workflow tool, for pipelines.

## TL mode

- Start it with `/senioro:orchestrate <goal>`. The guard hook registers only after `/senioro:orchestrate` has been invoked in the session.
- Run dir: `~/.cache/senioro-tl/runs/<session>/`. Seat reports, shared context files and workflow scripts live there, never in the repo.
- Strict mode is the default. Its marker is `~/.cache/senioro-tl/<session>.strict`.
- Pruning at arm time: markers older than 1 day and run dirs older than 7 days are both deleted.
- `--soft` skips the marker: same rules, not enforced. To leave strict mode, `rm` the marker.
- The guard's allow list: `~/.cache/senioro-tl/`, `~/.claude/projects/*/memory/`, `*/scratchpad/` and `MEMORY.md`. Subagent tool calls are always allowed.
- Recommended: add `~/.cache/senioro-tl` to the additional directories setting under permissions, so that Workflow `scriptPath` scripts are readable.
- Recommended (INFERRED, not tested live): on a GitHub install, also add the plugin cache dir `~/.claude/plugins/cache/senioro-stack` to the same additional directories setting, so that seats can read the review rubrics by path without a permission prompt. Add the parent dir: the versioned dir below it changes on every update.
- `/effort` changes are saved as that model's default.
- Seats never see memory. Point a seat at a memory file in its brief if it matters.
- The tl-guard is a guardrail that keeps the TL disciplined, not a security boundary: it allows any Bash command whose text contains an allowed path. It matches only the command's first word (after one leading `cd`) against a fixed list of file readers, so absolute paths such as `/bin/cat` and chained `cd`s are not caught.

## Platform

Tested on macOS only. Linux and Windows are untested. On Windows the hook command runs `bash`, so it needs Git Bash (INFERRED from the hooks docs on shell form; not tested).

## Uninstall

```bash
claude plugin uninstall senioro@senioro-stack
claude plugin marketplace remove senioro-stack
rm -rf ~/.cache/senioro-tl   # optional: deletes the TL run dirs and markers
```

## Development

- `tests/check.sh [validate|guard|grep|lint|layout ...] [-- <path> ...]` runs the deterministic gates (all of them when none is named). It needs bash, jq, perl and claude; shellcheck is optional.
- `tests/smoke.sh` runs the model smoke tests (hook and agent) against the plugin in this clone.
- `tests/smoke.sh` spends model tokens (haiku), and its hook test runs the real `/senioro:orchestrate`, which creates `~/.cache/senioro-tl/` (strict marker, run dirs) and prunes old markers and run dirs there.
- CI (`.github/workflows/check.yml`) runs `tests/check.sh` and `tests/tl-guard.test.sh` on every push to `main` and on pull requests; it uses no API key, so `tests/smoke.sh` stays manual.

## License

MIT. See [LICENSE](LICENSE).

The `bro`, `unslop`, `technical-writing` and `typescript-best-practices` skills are ported from [pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan (MIT). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
