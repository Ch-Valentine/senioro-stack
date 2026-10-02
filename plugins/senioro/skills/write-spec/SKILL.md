---
name: write-spec
description: "Writes the technical spec for a framed goal or a product requirements document: decisions table, cited facts, root cause for fixes, design with alternatives, agreed test seams, and gateable units, then runs a hygiene pass. Use when a goal is framed and the technical how must be designed before building."
disable-model-invocation: true
user-invocable: true
argument-hint: "[frame-or-prd-path] [spec-path]"
allowed-tools: Read, Glob, Grep, Write, Edit, Agent, AskUserQuestion
effort: high
---

# Write a spec

Turn a framed goal, or a product requirements document (PRD), into the technical how: a spec an implementer can build from in one pass, split into units that each pass or fail on a deterministic gate.

**Seat mode.** When a brief tells you to apply this file: do every step except talking to the user. Return each user decision as an OPEN DECISIONS line (options, recommended first), and write files only where the brief says. A step that spawns a subagent: do the reads yourself, and return each verification or spawn it needs as a NEEDS line for the TL.

## Step 1: Load

- Read the frame or PRD at `$0`. Without a path, ask for it once.
- No frame (no Goal, Done when and Scope), and no PRD: stop and say the goal must be framed first.
- The PRD is linked, never restated. The spec carries only the technical how.
- Spec path: `$1` if given; otherwise the file that already holds the frame (the frame was written into the spec file); otherwise the project's existing spec location (a dir of numbered specs such as `.plan/`, `docs/specs/` or `specs/`, next number). If none is found, ask once.

## Step 2: Ground

- List the facts the design rests on: current behaviour, call sites, contracts, limits, versions.
- Get each fact through a subagent, with a citation: `path:line`, a URL, or a command and its output. A runner locates or quotes; an investigator explains how or why. Never ask the user a fact.
- A verifier checks each load-bearing fact (a fact whose being wrong would change the design) before the design builds on it.
- A fact nobody could verify stays in the spec labelled INFERRED.

## Step 3: Root cause (bug or regression goals only)

Skip this step for new features, refactors and tooling. For a fix, the spec needs all four:

- **Repro.** A red-capable command (it drives the real code path and asserts the user's exact symptom) that has already been run, with its output. "Runs without erroring" is not red-capable.
- **Cause chain.** Ask "why" from the symptom down to the source, and say why the fix sits there and not at the symptom. A guard that silences a crash is a symptom fix.
- **Sweep.** Search for the same pattern elsewhere; the fix covers the pattern, not the one instance.
- **State first.** For "fails after restart", suspect stale persistent state (config, caches, lock files, serialized state) before code.

With no repro, stop. Say what was tried, and ask the user for access to an environment that reproduces it or a captured artifact (logs, a recording, a dump). Do not design a fix on a guess.

## Step 4: Design

- **Usage first.** Write the caller's view before anything else: what the caller imports, calls or runs, and what comes back, in two or three realistic call sites. The shape is derived from the usage; when they disagree, fix the shape.
- **Shape.** Data first, then how it flows. Name the invariants, where validation lives, and what the design deliberately does not do.
- **Options.** Offer at least two genuinely different shapes (not flavours of one), with the minimal change among them when it is plausible. Recommend one, and record each loser under Alternatives considered, with one line on why it lost.
- **Trade-offs.** One line each, as "we accept X for Y". Name anything a reader might take for an oversight.
- **Self-check.** Before handing off, read `${CLAUDE_PLUGIN_ROOT}/skills/review-spec-plan/references/lens-architect.md` and `${CLAUDE_PLUGIN_ROOT}/skills/review-spec-plan/references/lens-root-cause.md`, and fix what they would flag.

## Step 5: Test seams

- Propose the highest and fewest seams at which the change is tested, ideally one. Prefer existing seams to new ones.
- For a fix, the seam must exercise the real bug pattern as it happens at the call site. If no correct seam exists, that is a finding: record it, do not test at a shallower seam.
- Confirm the seams with the user in one question (AskUserQuestion, recommended option first).
- Write each acceptance check as a command or an observation that can fail.

## Step 6: Units

- Vertical slices: each one cuts a narrow but complete path through every layer it touches and can be verified on its own.
- Each unit has its owned paths (disjoint between units that run in parallel), its blocked-by edges, and a deterministic gate (a command that exits non-zero on failure).
- Size each unit for one fresh context. Put any prefactoring first.
- A wide refactor (one mechanical change whose blast radius fans across the codebase) follows expand → migrate batches → contract:
  - expand: add the new form beside the old, so nothing breaks;
  - migrate: move call sites in batches sized by blast radius, each batch blocked by the expand and green on its own;
  - contract: delete the old form, blocked by every migrate batch.

## Step 7: Write

- Write the spec from `references/spec-template.md` at its single canonical path (Step 1). Fill every section that applies; delete the ones marked "if" that do not.
- Move the frame in as section 1. With a PRD, section 1 links the PRD instead. If the frame came from a separate file or a brief's context file, delete the original once it is moved (one copy).
- Every decision lives only in the Decisions table; other sections cite it as `#N`.
- Open user decisions go to the Open questions section, options listed, recommended first. Ask them one at a time.

## Step 8: Hygiene pass

- Apply every rule in `references/hygiene.md` to the spec and fix each violation in place.
- Print a one-line result, for example `Hygiene: 7/7 rules pass (2 fixes: dead ref §4, duplicate decision #3)`.
- Return the spec path, the open decisions, and one "Next:" line naming the next command (the spec review).
