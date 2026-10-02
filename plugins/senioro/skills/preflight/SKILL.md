---
name: preflight
description: "Checks that a long run can start: agent seats and local services, auth, tools, and a baseline run of the project's gates, detected per project; reports READY or NOT READY with a fix hint per item and changes nothing. Use when a long or unattended build run is about to start."
disable-model-invocation: true
user-invocable: true
argument-hint: "[spec-path]"
allowed-tools: Agent, Bash, Read, Grep, Glob
---

# Preflight

Answer one question before a long run starts: can it start and finish without stopping on a missing worker, login or tool, or on a gate that was already red? The output is a table, never a file.

Read-only: never install, log in, edit, fix, or start or stop a service. A problem becomes a NOT READY row with a fix hint; the user decides.

When a brief tells you to apply this file: do every step except talking to the user.
Return each user decision as an OPEN DECISIONS line (options, recommended first), and write files only where the brief says.
A step that spawns a subagent: do the reads yourself, and return each verification or spawn it needs as a NEEDS line for the TL.

## Input

`$ARGUMENTS` is an optional spec path. With a spec, read its Units table: the gate commands it names, whether the run is a Workflow, and whether a PR is planned. Without one, check the project as it stands; the items that need a spec are SKIPPED.

## Step 1: Detect

Apply `references/project-tools.md` (in this skill's directory) to the repo. Add the gate commands the spec's Units name. Keep each tool's and gate's source `file:line`. When it is ambiguous which command is a gate, do not pick: list the candidates in the row (a seat returns them as an OPEN DECISIONS line).

## Step 2: Workers

Workers are both agent seats and local services.

- **Seats.** The run's seats can be spawned: one runner ping (agent `senioro:runner`, model haiku, prompt "Reply with the word pong") proves the spawn path. READY only on `pong`.
- **Workflow.** If the run is a Workflow, the Workflow tool is in your tool list.
- **Services.** The local services the gates need (DB, queue workers, dev server; found in the compose file, Procfile or README) answer their documented health command. A service that is down is NOT READY; do not start it.

In TL mode the TL makes the seat and Workflow checks itself (it spawns seats and holds the Workflow tool; seats do not), and a runner applies steps 1 and 3–7.

## Step 3: Auth

- Git remote: `git ls-remote --exit-code origin HEAD`.
- Forge CLI auth status (for example `gh auth status`, `glab auth status`), only if a PR is planned.
- Each detected tool's own documented status or doctor command.
- Each env var the detected tools and gates require is set: `[ -n "$VAR" ]`. Print the name only, never a value.

## Step 4: Tools

For each detected tool, `command -v <tool>` and its version against the project's pins (`.nvmrc`, `.tool-versions`, `engines` in package.json, toolchain files such as `rust-toolchain.toml` or `go.mod`). A version outside the pin is NOT READY with both versions as evidence. A CI-only tool is SKIPPED with "CI-only".

## Step 5: Gates (baseline)

Run each gate once, as the project runs it, and record pass or fail and its duration (`date +%s` before and after). This is the baseline the run is judged against. A red baseline is reported, not fixed: the row is NOT READY, the evidence names the failing checks, and the fix hint reads "red before the run: fix it first, or accept it as known-red".

## Step 6: Tree

`git branch --show-current` and `git status --short`: the branch, and clean or the dirty files listed (at most 5, then a count).

## Step 7: Report

Print at most 15 lines:

```
item | READY / NOT READY / SKIPPED | evidence | fix hint
```

Evidence is a command and its result, or a `file:line`. A SKIPPED row says why (no spec, no PR planned, CI-only). Then one verdict line:

```
VERDICT: READY — Next: start the run.
VERDICT: NOT READY (<n> items) — Next: <the first fix hint>.
```

Any NOT READY row makes the verdict NOT READY. Each NOT READY item is a question for the user before launch: fix it, or run anyway.
