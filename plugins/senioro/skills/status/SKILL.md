---
name: status
description: "Prints a plain-language status digest of the current work: done (and how it was verified), in flight, left, next, and open decisions, from the session's progress or rebuilt from git and the spec. Use when the user asks where things stand or what is done, left, or next."
disable-model-invocation: true
user-invocable: true
argument-hint: "[spec-path]"
allowed-tools: Agent, Bash, Read, Grep, Glob
---

# Status

Tell the user where the work stands in at most 10 lines they can read cold. Never write a file: no ledger, no status file.

When a brief tells you to apply this file: do every step except talking to the user.
Return each user decision as an OPEN DECISIONS line (options, recommended first), and write files only where the brief says.
A step that spawns a subagent: do the reads yourself, and return each verification or spawn it needs as a NEEDS line for the TL.

## Step 1: From this session

If this session holds the progress (you are the TL, or the work happened in this session), print the digest from context. No reads, no tools. Go to step 3.

## Step 2: Rebuild

Otherwise (after a compaction, or in a fresh session) spawn one runner (agent `senioro:runner`, model haiku) to collect the following and return at most 15 lines:

- `git log --oneline origin/HEAD..HEAD`: this branch's commits not on the default branch.
- `git status --short`, as counts (modified, added, deleted, untracked), not the list.
- The spec at `$ARGUMENTS`, or the spec this session named: each Unit and its gate status, the open Decisions rows, and the Open questions. Without a spec, say so.
- The report **names** (never their content) in this session's run dir, `~/.cache/senioro-tl/runs/${CLAUDE_SESSION_ID}/reports/`.

## Step 3: Print

Exactly these fields, at most 10 lines in total, in plain words with no jargon, no IDs without their meaning, no file dumps:

```
DONE: <item> (verified by <how>); ...
IN FLIGHT: <item>; ...
LEFT: <item>; ...
NEXT: <one concrete action>
OPEN DECISIONS: <question>; ... (or "none")
```

- DONE lists only work with evidence; each item says how it was verified (a gate that passed, a verifier, a test run, the user). Work without evidence goes in IN FLIGHT or LEFT.
- NEXT is a single action, the most useful one now.
- An empty field reads "none".
