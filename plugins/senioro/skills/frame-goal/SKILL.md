---
name: frame-goal
description: "Frames a goal before any spec: restates it plainly, gathers facts through subagents, settles open decisions one question at a time with a recommended answer, sets a falsifiable done predicate and scope, and decides whether a product requirements document is needed. Use when starting new work from a goal, idea, or request that has no spec yet."
disable-model-invocation: true
user-invocable: true
argument-hint: "[goal]"
allowed-tools: Agent, AskUserQuestion, Read, Glob, Grep, Write, Edit
---

# Frame a goal

Turn a goal into a frame that a spec or a PRD can be written from: what done means, what is in and out, which decisions are settled, and which route the work takes. The goal is `$ARGUMENTS`; if it is empty, ask for it in one question.

Facts are your job; decisions are the user's. Never ask the user a fact you could look up, and never settle a user's decision silently.

## Seat mode

When a brief tells you to apply this file: do every step except talking to the user.
Return each user decision as an OPEN DECISIONS line (options, recommended first), and write files only where the brief says.
A step that spawns a subagent: do the reads yourself, and return each verification or spawn it needs as a NEEDS line for the TL.

## Step 1: Restate

Restate the goal in ≤ 2 plain sentences, with no jargon. Confirm it with one question (the restatement as the recommended option, "something else" as the other). Use the confirmed wording from here on.

## Step 2: Facts

List what must be known before the decisions can be made: current behaviour, where the code lives, existing conventions, constraints, prior art.

- Get each fact through a subagent: a runner (`senioro:runner`) to locate or quote, an investigator (`senioro:investigator`) for how or why.
- Each fact comes back with its evidence (`path:line`, URL, or the command and its output).
- Never ask the user a fact. Launch the lookups now and do not block on them (step 3).

## Step 3: Decision frontier

Treat the open decisions as a tree: every decision branches into the decisions that hang off it. The frontier is every decision whose prerequisites are settled, so it can be asked now without guessing at an answer not yet heard.

- Ask **one question at a time** with AskUserQuestion: 2–4 options, the recommended one first, a one-line trade-off for each.
- Recompute the frontier after each answer. A settled decision unblocks the decisions that depended on it.
- A question that waits on a running fact lookup waits; the others go ahead.
- "Whatever you think" takes the recommended option; say so in one line.
- Record every answer as a row for the Decisions table (step 6).

Done when the frontier is empty: every branch visited, nothing left silently assumed.

## Step 4: Done, scope, rigor

Fix, and confirm with the user where it is their call:

- **Done when**: a falsifiable predicate, checkable by a command or an observation. "Works well" is not a predicate; "`npm test` passes and the export finishes in < 2 s on the sample file" is.
- **Scope**, quantified: what is in and what is out, with rough units or files.
- **Non-goals and must-not-change**: behaviour, files or contracts the work leaves alone.
- **Rigor**: `standard`, or `high` for a one-way door, data, security or a public contract. Bias toward `high` when unsure.

## Step 5: Route

Pick the route from this table. An ambiguous case gets one question.

| Signal | Route |
|---|---|
| ≤ 2 files, < 50 lines, nothing sensitive, no open product question | micro: no artifact; build directly |
| Users, product behaviour or success measure not settled; several user-facing flows | PRD, then spec |
| What and why settled in ≤ 1 paragraph; refactor, infra, bug fix, tooling | spec only |

Record the route and the one-line reason.

## Step 6: Write the frame

Fill `${CLAUDE_SKILL_DIR}/references/frame-template.md`. Where it goes depends on the route:

- **PRD**: as the first section of the new PRD file.
- **spec**: as the first section of the new spec file.
- **micro**: nowhere; print it.

Path: the project's existing spec location. Detect a dir of numbered specs (such as `.plan/`, `docs/specs/` or `specs/`) and take the next number, matching the existing names. Otherwise ask once where specs live.

The frame names no skill, agent tool or slash command: it describes the work, not the tooling.

## Step 7: Next

Print the frame path (or the printed frame, for micro) and one "Next:" line:

- PRD: `Next: /senioro:write-prd <frame-path>`
- spec: `Next: /senioro:write-spec <frame-path>`
- micro: `Next: build it directly; the frame above is the brief.`
