---
name: write-prd
description: "Writes a product requirements document (problem, users, solution, user stories, success measure, out of scope) from a framed goal, recording only decisions the user made or confirmed. Use when a framed goal needs its product what and why settled before a technical spec."
disable-model-invocation: true
user-invocable: true
argument-hint: "[frame-path]"
allowed-tools: Agent, AskUserQuestion, Read, Glob, Grep, Write, Edit
---

# Write a PRD

Settle the product what and why for a framed goal: whose problem it is, what they get, how success is measured, and what is out. The PRD is a record of decisions the user made or confirmed. Anything it asserts that the user never said or confirmed is a defect.

The technical how (modules, interfaces, files, tests) belongs to the spec that follows, not here.

## Seat mode

When a brief tells you to apply this file: do every step except talking to the user.
Return each user decision as an OPEN DECISIONS line (options, recommended first), and write files only where the brief says.
A step that spawns a subagent: do the reads yourself, and return each verification or spawn it needs as a NEEDS line for the TL.

## Step 1: Load the frame

Read the frame at `$ARGUMENTS`. If no path was given, or the file has no Frame section, stop and print: `No frame found. Run /senioro:frame-goal <goal> first.`

Take the frame's Goal, Done when, Scope, Route and Decisions as settled. Do not re-ask them.

## Step 2: Settle the product questions

List what the PRD needs that the frame left open: who the users are and what job they are doing, the user-facing flows, the success measure, the edges of scope.

- Ask **one question at a time** with AskUserQuestion: 2–4 options, the recommended one first, a one-line trade-off for each.
- Ask only questions whose prerequisites are settled; recompute after each answer. Done when no product question is left open.
- Facts come through subagents (a runner, `senioro:runner`, to locate or quote; an investigator, `senioro:investigator`, for how or why), never from the user.
- A question the user defers goes to Open questions, not into a guess.

## Step 3: Write the PRD

Fill `${CLAUDE_SKILL_DIR}/references/prd-template.md` in the frame's file. The frame stays its first section, unchanged. In seat mode, move the frame in from the brief's context file.

Write in the user's view and in the project's own nouns. Every section is backed by the frame, a user statement or a decision; a section with nothing to say says "none" rather than inventing content.

The Success measure is falsifiable: a number, an observable behaviour, or a check a person can run, with the threshold that counts as success. Tie it to the frame's Done when; do not restate it.

## Step 4: User stories

- Numbered, each as "As a <actor>, I want <capability>, so that <benefit>".
- Their count scales with the scope: enough to cover every flow in scope, no padding.
- Each traces to a user statement or a decision (cite the Decisions `#N` or the frame).
- No implementation decisions, file paths or code.

## Step 5: Hygiene pass

Apply `${CLAUDE_PLUGIN_ROOT}/skills/write-spec/references/hygiene.md` to the PRD and fix what it finds. Report one line: `Hygiene: clean` or `Hygiene: fixed <n> (<what>)`.

## Step 6: Confirm and hand off

Ask one question: "Does this state anything you did not say or confirm?" Fix every item the user names, then print the PRD path and:

`Next: /senioro:write-spec <prd-path>`
