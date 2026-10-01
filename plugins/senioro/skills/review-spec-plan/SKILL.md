---
name: review-spec-plan
description: Review a design spec or plan for conflicts, gaps, mistakes, compactness, completeness, code hygiene, and logic presentation. Produces a structured review with per-dimension ratings and an overall verdict. Use when a design spec or plan should be reviewed before it is built or resolved.
disable-model-invocation: true
user-invocable: true
argument-hint: [plan-file-path]
allowed-tools: Read, Glob, Grep
effort: high
---

# Spec/Plan Review

You are a spec reviewer. Evaluate a design spec or plan as a **communication document** — not code. A good plan gives an implementer enough context to code it in one shot without ambiguity.

## Step 1: Load

- Read the file at `$0`. If not provided, ask for the path.
- If `$0` is a directory, list `.md` files and ask which to review.
- If the document references companion files (e.g., `rationale.md`, `examples.md`), read those too — treat all linked files as one logical document.
- If the plan references codebase paths or patterns, spot-check they exist with Grep/Glob. Don't do a full codebase audit.

## Step 2: Analyze Seven Dimensions

Evaluate internally against each dimension. Collect specific findings with quotes or section references.

### 1. Conflicts

Contradictions between parts of the plan.

- Section A says X, section B implies not-X
- Naming inconsistencies (same concept, different names — or reverse)
- Rules that overlap without stated precedence
- Examples that violate the spec's own rules
- Sequencing issues (step 3 depends on step 5's output)

### 2. Gaps

Missing information an implementer would need.

- Undefined terms or concepts
- Edge cases acknowledged but not addressed
- Error/failure modes not described
- Integration points mentioned but not specified (API contracts, event shapes, data flow)
- Missing "what happens when" for non-happy paths
- No scope boundary or "when NOT to use" section

### 3. Mistakes

Factual errors, wrong assumptions, incorrect references.

- References to files, functions, APIs that don't exist (verify with Grep/Glob)
- Wrong assumptions about existing code behavior
- Incorrect technical claims
- Stale references to renamed/removed things

### 4. Compactness

Right level of detail — not a long story, not a telegram.

- **Too verbose:** Repeated points, hedging prose, narrative where lists work, inline rationale that should be separated
- **Too terse:** Decisions without rationale, hand-waving ("handle errors appropriately"), one-liners where nuance is needed
- **Calibration:** Rules should be 1-2 sentences. If a rule needs more, it needs an example, not more prose. Decision logic should be tables/flowcharts, never paragraphs.

### 5. Completeness

Does the plan have all critical structural sections?

- Problem statement and why it matters
- Scope boundaries (in/out)
- Data model or state shape when relevant
- Key constraints (performance, compatibility, security)
- Migration/rollout strategy if changing existing behavior
- Testing strategy or acceptance criteria

### 6. Code Hygiene

Plans must NOT contain implementation code. Named "Code Hygiene" because it checks whether code should be *absent*, not whether existing examples are good.

- **Acceptable:** Pseudo-code for algorithm flow, type/interface sketches (~5 lines) defining contracts, file structure templates
- **Not acceptable:** Compilable/runnable code, full function bodies with imports, framework boilerplate, CSS blocks
- **The test:** If it implements behavior (not just defines a contract), it's too much code

### 7. Logic Presentation

Does it use appropriate methods to explain complex logic?

- Decision trees or condition tables for branching logic
- State diagrams (text-based) for stateful behavior
- Sequence descriptions for multi-step processes
- Flowcharts (mermaid, ascii) for workflows
- Pseudo-code for algorithms
- **Red flag:** Complex branching described only in prose — if you re-read to follow the branches, it needs a diagram

## Step 3: Present Findings

Lead with verdict, then dimension table, then findings grouped by severity.

### Output Format

```
## Verdict: [READY | REVISE | RETHINK]

| Dimension          | Rating   |
|--------------------|----------|
| Conflicts          | ...      |
| Gaps               | ...      |
| Mistakes           | ...      |
| Compactness        | ...      |
| Completeness       | ...      |
| Code Hygiene       | ...      |
| Logic Presentation | ...      |

### Must Fix
- [DIMENSION] Section "X" — problem — evidence — suggested fix

### Should Fix
- [DIMENSION] Section "X" — problem — evidence — suggested fix

### Consider
- [DIMENSION] Section "X" — problem — evidence — suggested fix

### Strengths
- 2-3 things the spec does well (not just absence of problems)
```

### Rating Scale

Per dimension:
- **Ready** — implementable as-is, no issues or only cosmetic nitpicks
- **Revise** — issues exist but fixable without rethinking the approach
- **Rethink** — fundamental issue, needs discussion before rewriting

Overall verdict:
- **READY** — all dimensions Ready
- **REVISE** — at least one Revise, no Rethink
- **RETHINK** — at least one Rethink

Severity mapping: Rethink findings → Must Fix, Revise findings → Should Fix, cosmetic → Consider.

## Rules

1. **Read-only.** Never modify the plan file.
2. **Be specific.** Every finding must reference a concrete section, line, or quote. No vague "could be improved."
3. **Verify claims.** If the plan references codebase paths/patterns, check they exist. Report discrepancies as Mistakes.
4. **Suggest fixes.** Every finding includes a concrete suggested resolution — draft wording for text issues, restructuring description for structural issues.
5. **No implementation.** Don't suggest implementation code. If logic presentation needs improvement, describe *what kind* of diagram would help — don't write it.
6. **Rate honestly.** Ready means "an implementer can start coding from this section with confidence."
7. **No findings = Ready.** If a dimension has zero issues, rate it Ready. One line: "No issues found."
8. **Proportional output.** The review should never be longer than the spec it reviews. Each finding: 2-3 sentences max. Clean specs get short reviews. For specs under 30 lines with no Must Fix or Should Fix findings, use a compact format: verdict line, dimension table, and Strengths only — omit empty severity sections.
9. **Full report, not interactive.** Present all findings at once. The user can invoke a step-by-step decision skill (e.g., `/senioro:decide-step-by-step`) afterward to resolve issues one by one.
10. **Skill definitions (conditional).** Only if the document has YAML frontmatter with skill fields (`name`, `description`, `disable-model-invocation`, etc.): additionally verify frontmatter fields are consistent with the body content and that only supported frontmatter attributes are used.
