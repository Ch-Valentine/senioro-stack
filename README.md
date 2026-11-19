# senioro-stack

A Claude Code plugin marketplace (`senioro-stack`) that ships one plugin, `senioro`: a Tech Lead mode for Claude Code. In TL mode the main session delegates every read, search, investigation and change to five seat agents with capped reports, keeps progress in its own compact context, routes each task to the cheapest model that cannot get it wrong, auto-decides reversible calls, and batches the user's decisions, up to 4 per ask. A strict-mode guard hook keeps the TL from touching the tree itself. The plugin also ships review and decision skills.

## Quick start

### Install

```bash
claude plugin marketplace add Ch-Valentine/senioro-stack
claude plugin install senioro@senioro-stack
```

You need Claude Code 2.1.271 or later, `bash` and `jq`. See [Prerequisites](#prerequisites) for the full list.

### Pick a wallet

A wallet picks the model each seat agent runs on. It is the plugin's `wallet` option, and it has three values. An unset wallet, or one with an unknown value, runs as `sushi`.

| Wallet | runner | verifier | investigator | implementer | architect | Pick it when |
|---|---|---|---|---|---|---|
| `ramen` | haiku | sonnet | sonnet | sonnet | opus, sonnet for a simple design task | You want the cheapest wallet. Only design stays on opus. |
| `sushi` (default) | haiku | sonnet, opus on a hard task | sonnet, opus on a hard task | sonnet, opus on a hard task | opus | You want sonnet for routine work and opus where a task is hard. |
| `omakase-bro` | sonnet | opus | opus | opus | opus | You want opus on every seat but the runner, whatever the task. |

To install with a wallet, pass it with `--config`:

```bash
claude plugin install senioro@senioro-stack --config wallet=ramen
claude plugin install senioro@senioro-stack --config wallet=sushi
claude plugin install senioro@senioro-stack --config wallet=omakase-bro
```

To change the wallet later, run `claude plugin configure senioro@senioro-stack` from the shell:

```bash
claude plugin configure senioro@senioro-stack                    # show the current options
echo '{"wallet":"omakase-bro"}' | claude plugin configure senioro@senioro-stack --values-stdin
```

After you change the wallet, run `/reload-plugins` or start a new session so the skills pick up the new value. Set the wallet at user scope. Claude Code does not read a value in a project's `.claude/settings.json`. [Wallet details](#wallet-details) lists the hard-task triggers and the extra seats.

### The workflow

Run each stage yourself, or start TL mode with `/senioro:orchestrate <goal>` and the TL runs the same stages through its seats. Most stages end with a `Next:` line that names the next command.

1. Frame the goal with `/senioro:frame-goal <goal>`. It sets a done predicate and a route: micro, spec, or PRD then spec.
2. On the PRD route, write the product requirements with `/senioro:write-prd <frame-path>`.
3. Write the technical spec with `/senioro:write-spec <frame-or-prd-path>`.
4. Review the spec with `/senioro:review-spec-plan <spec>`, then fix a failing stage with `/senioro:resolve-plan-issues <spec>` and review again.
5. Before a long or unattended build, check that it can start with `/senioro:preflight <spec>`.
6. Build the change. For a small change, build it directly. For a multi-unit build, run `/senioro:orchestrate`: TL mode runs preflight, then a Workflow. A micro goal skips steps 2 to 5, and its printed frame is the brief.
7. Review the code with `/senioro:review-implementation <feature>`, then fix the confirmed findings with `/senioro:resolve-review-findings`.
8. Ask for a PR, or run `/senioro:check-before-pr --pr`. The checks run, then commit, push and `gh pr create` follow.
9. `/senioro:babysit-pr` starts once the PR opens and fixes valid review comments and failing checks, at most 3 rounds.
10. Merge the PR yourself. No skill merges without a separate request.

Run `/senioro:status` at any time for what is done, left and next. After a hard session, run `/senioro:retro`.

## Prerequisites

- Claude Code 2.1.271 or later (the wallet picker; tested 2.1.319). Older versions cannot load the plugin.
- `bash` and `jq`. Without jq the guard fails open.
- Access to the opus, sonnet and haiku models.
- The Workflow tool, for pipelines.

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
| `/senioro:frame-goal` | Frame a goal: facts through subagents, open decisions one question at a time, a falsifiable done predicate, and the route (micro, spec, or PRD then spec). | No |
| `/senioro:write-prd` | Write a product requirements document (problem, users, user stories, success measure) from a framed goal. | No |
| `/senioro:write-spec` | Write the technical spec: decisions, cited facts, root cause, design with alternatives, test seams, gateable units; then a hygiene pass. | No |
| `/senioro:review-spec-plan` | Review a design spec or plan, with per-dimension ratings and a verdict. | No |
| `/senioro:preflight` | Check that a long run can start: seats and services, auth, tools, a baseline gate run; READY or NOT READY, read-only. | No |
| `/senioro:status` | Print a plain-language digest: done (how verified), in flight, left, next, open decisions. | No |
| `/senioro:check-before-pr` | Run the project's own static-analysis and AI-review tools, fix real findings at the root, re-run until clean. Asked for a PR, it then opens it with no further question; run on its own, it asks once whether to open one. | No |
| `/senioro:babysit-pr` | Watch an open PR: learn which review bots and CI checks recent PRs got, then triage new comments and failing checks, fix the valid ones and push, at most 3 rounds. Never merges and never writes on GitHub beyond the fix pushes, unless you approve the replies. | No |
| `/senioro:review-implementation` | Deep review of a feature's implementation, with a structured verdict. `--diff <base>` re-reviews only a fix diff. | No |
| `/senioro:resolve-review-findings` | Challenge a code review's findings, confirm the real ones, apply and verify the fixes. | No |
| `/senioro:resolve-plan-issues` | Resolve a plan's open issues: auto-fix trivial ones, walk through complex ones. | No |
| `/senioro:decide-step-by-step` | Resolve a plan's open decisions one by one, with a recommendation each. | No |
| `/senioro:retro` | Session retro: one architect seat finds the session's biggest struggles in its record and proposes changes that remove their causes; you settle them one at a time. | No |
| `/senioro:bro` | Restate the last message in plain language, with no jargon. | No |
| `/senioro:unslop` | Cut AI tells from any writing. | Yes |
| `/senioro:technical-writing` | Layered technical-writing standard for docs, RFCs, READMEs, PR descriptions and commit messages. | Yes |
| `/senioro:typescript-best-practices` | TypeScript type-safety rules, loaded when working with `.ts` and `.tsx` files. | Yes |

Agents (spawned as `senioro:<name>`):

| Agent | Role | Default model | Effort |
|---|---|---|---|
| `senioro:runner` | Run a command and digest it, locate files, run tests. No edits. | haiku | low |
| `senioro:verifier` | Rule on claims, findings or self-reports, refute-by-default. No edits. | sonnet | high |
| `senioro:investigator` | Research and root cause; facts separated from inferences. No edits. | opus | high |
| `senioro:architect` | Design: options, a recommendation, a split into gateable units. | opus | xhigh |
| `senioro:implementer` | Make exactly the briefed change and run the narrowest checks. | opus | high |

The TL passes a `model` on every spawn, taken from the wallet table, which overrides the agent's default model. `resolve-plan-issues` and `resolve-review-findings` read the same table for their own subagents. Effort stays pinned per agent, except sushi's no-trigger mechanical spawns, which pass `effort: medium`.

## Wallet details

The wallet table lives once, in `/senioro:orchestrate`; the skills that spawn seats read it from there. The [Pick a wallet](#pick-a-wallet) table gives the main seats. The rest of the rules:

- `sushi` moves the verifier, investigator and implementer to opus when a task is security-sensitive, touches shared state or a cross-file contract, is concurrent, changes a public API, or has failed twice.
- The second blind verifier and the split adjudicator run on sonnet in `ramen` and on opus in `sushi` and `omakase-bro`.
- A session retro's architect runs on sonnet in `ramen` and on opus in `omakase-bro`. In `sushi` it runs on sonnet, and on opus when the session was compacted or has more than 25 seat reports.
- The picker needs Claude Code 2.1.271 or later; older versions cannot load the plugin.

## TL mode

- Start it with `/senioro:orchestrate <goal>`. The guard hook registers only after `/senioro:orchestrate` has been invoked in the session.
- Run dir: `~/.cache/senioro-tl/runs/<session>/`. Seat reports, shared context files, workflow scripts, the handoff and the retro live there, never in the repo.
- Strict mode is the default. Its marker is `~/.cache/senioro-tl/<session>.strict`.
- Pruning at arm time: markers older than 1 day and run dirs older than 7 days are both deleted.
- `--soft` skips the marker: same rules, not enforced. To leave strict mode, `rm` the marker.
- The guard's allow list: `~/.cache/senioro-tl/`, `~/.claude/projects/*/memory/`, `*/scratchpad/` and `MEMORY.md`. Subagent tool calls are always allowed.
- The guard also denies `EnterWorktree` from the TL: the TL stays at the repo root, and seats create and remove worktrees.
- Recommended: add `~/.cache/senioro-tl` to the additional directories setting under permissions, so that Workflow `scriptPath` scripts are readable.
- Recommended (INFERRED, not tested live): on a GitHub install, also add the plugin cache dir `~/.claude/plugins/cache/senioro-stack` to the same additional directories setting, so that seats can read the review rubrics by path without a permission prompt. Add the parent dir: the versioned dir below it changes on every update.
- `/effort` changes are saved as that model's default.
- Seats never see memory. Point a seat at a memory file in its brief if it matters.
- Retro: at a spec or phase close in a session with a spec dir, one implementer appends a block of at most 10 lines to `retro.md` in the run dir, never in the repo and never rewriting old blocks: time on spec versus build, tokens and API-equivalent dollars, the seat count by model and up to three struggles. The layout is `plugins/senioro/skills/orchestrate/references/retro-template.md`; the figures come from `token-spend.sh --split` or `--phase`. `/senioro:retro` reads it and writes its proposals beside it, as `retro-proposals-<n>.md`. Both go when the run dir is pruned.
- The tl-guard is a guardrail that keeps the TL disciplined, not a security boundary: it allows any Bash command whose text contains an allowed path. It matches only the command's first word (after one leading `cd`) against a fixed list of file readers, so absolute paths such as `/bin/cat` and chained `cd`s are not caught.

## Pre-PR checks

`/senioro:check-before-pr` classifies the branch diff with `plugins/senioro/scripts/change-class.sh [<base>]` and runs only what the class needs:

| Class | Diff | Checks | PR hook: create |
|---|---|---|---|
| none | empty | nothing | silent |
| docs | only `*.md`, `*.mdx`, `*.rst`, images and `LICENSE*`, outside prompt paths | only linters the project scopes to those files | silent, no loop |
| code | anything else, including `*.txt` and file types it does not know | all detected gates, static analysis and AI review | denies once per HEAD while the loop has not passed, with a reminder to Claude; the retry passes |

Prompt paths (`.claude/{skills,agents,commands,rules}/**`, a plugin root's `skills/`, `agents/`, `commands/` and `hooks/` dirs, `CLAUDE.md`, `CLAUDE.local.md`, `AGENTS.md`) are code, and a diff that touches them also gets a prompt audit. `plugins/senioro/scripts/prompt-audit.sh <base> <report> <model>` starts a child `claude -p "/claude-api prompt-audit <paths>"` that runs non-interactively with `--permission-mode dontAsk` and only the tools Read, Grep, Glob and read-only git, and writes its findings to the report. The AI review and the audit each run once per tree. If the audit cannot run, the loop asks you to run it in another session or skip it.

The `pr-guard` hook takes the diff against `origin/HEAD` (else `origin/main`, `origin/master`); with no such base it treats the diff as code. It never asks, and it stays silent on every merge: `gh pr merge`, `glab mr merge`, an MCP merge tool, a create and a merge in one command, and any run without `jq`. CI still runs every gate, whatever the class.

Asking for a PR is the approval: the checks run, then commit, push and `gh pr create` follow with no question. A bare `/senioro:check-before-pr` asks once, "Open a PR now?". When you asked for a PR, the loop asks no questions: it decides reversible items itself, logs each as a `Noted:` line in its report, and stops only on a real blocker (red checks it cannot fix within its rounds, a secret, or an irreversible or outward-facing step beyond the requested PR). Items only you can decide do not stop it: they go under `Open decisions` in the PR body. A PR is never opened unasked, and never merged without a separate request. Only the skills' instructions guard merges; no hook does.

No hook or script grants permissions. `/senioro:check-before-pr` and `/senioro:babysit-pr` list Bash in their `allowed-tools`, which applies only when you run them as slash commands. In TL mode, or after a plain-language request for a PR, Claude Code's default permission mode still asks before `git commit`, `git push` and `gh pr create` unless your settings allow them. To open a requested PR with no prompt in those cases, add allow rules to your own settings (`~/.claude/settings.json`, or `.claude/settings.local.json` for one project):

```json
{ "permissions": { "allow": ["Bash(git commit:*)", "Bash(git push:*)", "Bash(gh pr create:*)"] } }
```

PR babysit (`/senioro:babysit-pr [<pr>]`, also started once a PR opens):
- Two runner seats survey the author's last 2 PRs (else the repo's) for review bots and CI checks.
- `plugins/senioro/scripts/pr-watch.sh` waits in one background call, never a sleep loop, until the checks settle and the expected bots post, then writes a digest.
- Each round fixes the valid comments and failing checks, verifies the fix and pushes it to the PR branch; at most 3 rounds. CI flakes are reported, not re-run.
- It never merges, rebases, resolves threads or writes on GitHub beyond the fix pushes. If some comments were judged invalid, it asks once at the end whether to post the drafted replies.

## Platform

Tested on macOS only. Linux and Windows are untested. On Windows the hook command runs `bash`, so it needs Git Bash (INFERRED from the hooks docs on shell form; not tested).

## Uninstall

```bash
claude plugin uninstall senioro@senioro-stack
claude plugin marketplace remove senioro-stack
rm -rf ~/.cache/senioro-tl   # optional: deletes the TL run dirs and markers
```

## Development

Install from a local clone:

```bash
claude plugin marketplace add <path-to-clone>
claude plugin install senioro@senioro-stack
```

A plugin from a local-directory marketplace loads in place: edit the files in the clone, then run `/reload-plugins` (or start a new session).

- `tests/check.sh [validate|guard|grep|lint|layout ...] [-- <path> ...]` runs the deterministic gates (all of them when none is named). It needs bash, jq, perl and claude; shellcheck is optional.
- `plugins/senioro/scripts/token-spend.sh <session.jsonl> [--until <ISO-8601 UTC>] [--split <ISO-8601 UTC> | --phase spec|build]` prints a session's token spend per group (TL, seats, workflow agents) and per model, the seat count by model, and its waste metrics (resumes, cache gaps, docs fetches, unnamed run-dir reads, big TL reads) from the transcripts; with `--split` or `--phase` it prints only the three retro lines (spec, build, seats). `tests/token-spend.test.sh` pins it on two fixture sessions. It needs bash and jq.
- `tests/smoke.sh` runs the model smoke tests (hook and agent) against the plugin in this clone. `tests/smoke.sh wallet` checks that a haiku session on `wallet=ramen` spawns a runner, a verifier and an implementer and uses only haiku and sonnet; `tests/smoke.sh effort` probes the per-spawn `effort` parameter (Claude Code 2.1.292 or later). `tests/smoke.sh hook` also checks that a PR create is denied once per HEAD and passes on the retry, that a docs-only diff passes with no deny, and that a merge on an unchecked code commit passes the hook silently. `tests/smoke.sh audit` runs the prompt audit on a throwaway plugin repo with one planted dated pattern (a nested `claude -p` on `$AUDIT_MODEL`, default sonnet).
- `tests/smoke.sh` spends model tokens (haiku), and its hook test runs the real `/senioro:orchestrate`, which creates `~/.cache/senioro-tl/` (strict marker, run dirs) and prunes old markers and run dirs there.
- CI (`.github/workflows/check.yml`) runs `tests/check.sh` and `tests/tl-guard.test.sh` on every push to `main` and on pull requests; it uses no API key, so `tests/smoke.sh` stays manual.
- `plugins/senioro/skills/orchestrate/references/evidence.md` explains why each TL rule exists (research 2026-09-16 and 2026-09-29). It is for maintainers and is never loaded at runtime.

## License

MIT. See [LICENSE](LICENSE).

The `bro`, `unslop`, `technical-writing` and `typescript-best-practices` skills are ported from [pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan (MIT). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
