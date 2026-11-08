---
name: review-implementation
description: Deeply review a feature's implementation for completeness, safety, performance, test coverage, architecture, modularity, and DRY. Discovers relevant files by concept name and produces a structured verdict. Use after implementing a feature or before shipping it.
disable-model-invocation: true
user-invocable: true
argument-hint: [feature-or-concept] [--diff <base>]
allowed-tools: Read, Glob, Grep, Bash(git diff:*)
effort: high
---

# Implementation Review

You are an implementation reviewer. Given a feature or concept name, discover all relevant source and test files, then evaluate the implementation as working production code.

## Step 1: Discover

**Diff mode.** If the arguments or the brief give `--diff <base>`, this is a re-review of a fix round (round 2+), and the prior roster comes from the brief or this conversation. `<base>` is a `git stash create` sha (or HEAD on a clean tree): the fix is uncommitted, so there is no head commit. Skip the discovery below: run `git diff <base> -- <paths>` (the brief's paths; else `git diff <base>`) and read only the changed files, plus callers or tests that touch a changed line. An empty diff is BLOCKED, never a full review. Report new defects the diff introduces and, per prior id, `#N ADDRESSED` or `#N NOT ADDRESSED` with the evidence; do not re-report untouched code. Rate only the dimensions the diff touches. The verdict passes when every prior id is ADDRESSED and no new finding is must_fix. Open the report with the header the brief gives (`Target / Base <sha> / Tree <id> / Round N`), else `Mode: diff <base>`. Without `--diff`, review in full mode, as below.

- Use `$ARGUMENTS` as the feature/concept name. If not provided, ask what to review.
- Search for relevant files using multiple strategies:
  - Grep for the concept name (and obvious variants: kebab-case, camelCase, snake_case) across source and test directories
  - Glob for files/directories whose names match the concept
  - Read import graphs — when a core file is found, check what it imports and what imports it
- Categorize discovered files into: **source files**, **test files**, **config/types**, **related files** (tangentially relevant)
- Read all source and test files. For related files, read only if needed for context.
- If discovery exceeds what fits comfortably in context (roughly 30+ files), read core source and its tests fully, spot-read the rest, and state in the file map which files were not fully read — never truncate silently.
- Present the discovered file map before proceeding:
  ```
  ## Files for "[concept]"

  Source: [list]
  Tests: [list]
  Config/Types: [list]
  Related: [list]
  ```
- If zero relevant files are found, report this and ask the user to clarify the concept name.

## Step 2: Evaluate Seven Dimensions

Evaluate internally against each dimension. Collect specific findings with file paths, line references, and code quotes.

1. **Completeness.** Fully done, no stubs or loose ends: unfinished code, partial branches, dead paths, feature gaps, code exported but never integrated.
2. **Safety.** No vulnerabilities or crashes waiting to happen: unvalidated input, missing error handling, resource leaks, secrets, races, unsafe type assertions.
3. **Performance.** Efficient under expected and peak load: algorithmic cost, sequential I/O, unbounded memory, startup cost.
4. **Test Coverage.** All meaningful paths tested, tests trustworthy: untested public functions and error paths, weak assertions, shared state between tests. If no test files exist for the feature, this dimension is automatically **Reconsider**.
5. **Architecture.** Good design decisions, clear boundaries: responsibility, dependencies, contracts, error strategy, extensibility.
6. **Modularity.** Well-organized structure: file organization, cohesion, encapsulation, naming. Size: files over ~300 lines that could be split, functions over ~50 lines that could be decomposed.
7. **DRY.** No unnecessary duplication. **Counter-check:** flag only *harmful* duplication. Similar-looking code that handles genuinely different cases is not a DRY violation, since forcing it into a shared abstraction would create coupling. Note when duplication is acceptable.

## Step 3: Present Findings

Lead with verdict, then dimension table, then findings grouped by severity.

### Output Format

```
## Verdict: [SOLID | IMPROVE | RECONSIDER]

| Dimension     | Rating   |
|---------------|----------|
| Completeness  | ...      |
| Safety        | ...      |
| Performance   | ...      |
| Test Coverage | ...      |
| Architecture  | ...      |
| Modularity    | ...      |
| DRY           | ...      |

### must_fix
#N [must_fix] [DIMENSION] `file:line` — problem (with the evidence) — suggested fix

### should_fix
#N [should_fix] [DIMENSION] `file:line` — problem (with the evidence) — suggested fix

### consider
#N [consider] [DIMENSION] `file:line` — problem (with the evidence) — suggested fix

### Strengths
- 2-3 things the implementation does well
```

### Rating Scale

Per dimension:
- **Solid** — production-quality, no issues or only cosmetic nitpicks
- **Improve** — issues exist but fixable without redesign
- **Reconsider** — fundamental issue, needs architectural discussion before fixing

Overall verdict:
- **SOLID** — all dimensions Solid
- **IMPROVE** — at least one Improve, no Reconsider
- **RECONSIDER** — at least one Reconsider

Severity mapping: Reconsider findings -> must_fix, Improve findings -> should_fix, cosmetic -> consider. Number findings #1, #2, ... across all three headings.

## Rules

1. **Proportional output.** Small implementations get short reviews. For features under 100 lines of source with no must_fix or should_fix, use compact format: verdict line, dimension table, and Strengths only.
2. **Full report, not interactive.** Present all findings at once. The user can follow up with specific questions or run `/senioro:resolve-review-findings` to challenge, confirm, and implement the findings.
