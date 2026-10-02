---
name: review-spec-plan
description: "Reviews a spec or plan through four fixed lenses, each run by its own reviewer seat (architect, spec quality, root cause versus dirty fix, blast radius), then filters the merged findings for noise and returns one verdict with Must Fix, Should Fix and Consider findings. Use when a spec or plan should be reviewed before it is built or its issues are resolved."
disable-model-invocation: true
user-invocable: true
argument-hint: "[spec-or-plan-path] [previous-review-report]"
allowed-tools: Workflow, Agent, Read, Bash
effort: high
---

# Spec/Plan Review

Review a spec or plan through four fixed lenses, each run by its own reviewer seat, then filter the merged findings with lead judgment and return one verdict. The workflow `${CLAUDE_SKILL_DIR}/review.workflow.js` is the only copy of the lenses, seats, models and schemas; this file only launches it.

| Lens | What it checks |
|---|---|
| A architect | Design red flags, the deletion test, real seams, genuine alternatives, subtraction, reader load, gateable units, cost |
| Q spec quality | The seven dimensions (conflicts, gaps, mistakes, compactness, completeness, code hygiene, logic presentation) and the spec hygiene rules |
| R root cause | Symptom versus root, bolted on versus integrated, the premise behind failed fixes, repro and seam for bug specs |
| B blast radius | What breaks beyond the named files, and the one fact the change is safe because of, proven as far as is cheap |

A lead-judgment filter then dedupes the findings and puts each one in a bucket: act on, consider, noted or dismissed. A dismissed must_fix gets a blind second opinion.

## Step 1: Target

- The target is the file at `$0`, as an absolute path. Without one, ask for the path.
- If `$0` is a directory, list its `.md` files and ask which one to review.

## Step 2: Run dir

- `R` = `$HOME/.cache/senioro-tl/runs/${CLAUDE_SESSION_ID}` (absolute). Run `mkdir -p "$R/reports"`.
- Reports live only there: never in the repo, never inside the target.

## Step 3: Round

Each report starts with three header lines: `Target: <absolute path>`, `SHA256: <hash>`, `Round: <n>`.

- `sha` = the first field of `shasum -a 256 "<target>"`.
- The previous report is `$1` if given. Otherwise it is the newest `$R/reports/review-<n>.md` whose header has the line `Target: <target>` exactly (`grep -lxF`, then the newest by `ls -t`).
- With a previous report:
  - if its `SHA256:` equals `sha`, stop and say the target is unchanged since that round: there is nothing new to review;
  - otherwise `round` = its `Round:` + 1, and `prior` = its absolute path.
- Without one: `round` = 1 and no `prior`.
- If `round` would be 4 or more, stop and say so: at most 3 review rounds. Resolve the open findings by decision instead.

## Step 4: Launch

Launch the Workflow tool with `scriptPath` = `${CLAUDE_SKILL_DIR}/review.workflow.js` and `args` as a JSON object:

```
{ "target": "<absolute target>", "R": "<R>", "dir": "${CLAUDE_SKILL_DIR}", "round": <n>,
  "prior": "<previous report, round 2+ only>", "sha": "<sha>", "context": "<decisions context file, only if the user named one>" }
```

Omit `prior` and `context` when there are none. The workflow runs the four lenses in parallel, then the filter, then the second opinion when needed. It returns `{verdict, report, lenses, items, noted, dismissed, contested}`.

## Step 5: Present

- Print the report file at the returned `report` path: it is the deliverable. It keeps the `### Must Fix`, `### Should Fix` and `### Consider` headings, so the decision commands find the findings.
- Then one line: the returned verdict, and the `contested` ids if any (a dismissed must_fix the second opinion confirmed; treat it as open).
- A verdict tagged `(incomplete: …)` means a lens or the filter died: say which, and that a re-run is needed before the review can be trusted. It is never READY.
- If `report` is null, print the returned `items` instead.

## Step 6: Next

End with a "Next:" line naming the decision step with both paths:

- `/senioro:decide-step-by-step <target> <report>` to settle the findings one at a time, or `/senioro:resolve-plan-issues <target> <report>` to resolve them in one pass;
- after the target is revised, `/senioro:review-spec-plan <target>` runs the next round (at most 3).

## Without the Workflow tool

If the Workflow tool is unavailable, run the review in this session instead:

1. Apply each lens file in `${CLAUDE_SKILL_DIR}/references/` (`lens-architect.md`, `lens-spec-quality.md` with `${CLAUDE_SKILL_DIR}/../write-spec/references/hygiene.md`, `lens-root-cause.md`, `lens-blast-radius.md`) to the target, one pass each.
2. Apply `${CLAUDE_SKILL_DIR}/references/lead-judgment.md` to the merged findings, and write the report to `$R/reports/review-<round>.md` with the same header.
3. Label the report "single-session review (lenses not independent)", then continue with Step 5.

## Rules

1. **Read-only on the target.** Never modify the reviewed file, and never write review text into it or anywhere in the repo.
2. **Proportional output.** The report is never longer than the target; each finding is one line.
3. **At most 3 rounds,** and never re-review an unchanged target (Step 3).
4. **Full report, not interactive.** Present the whole report at once; decisions come after, one at a time, through the decision commands.
