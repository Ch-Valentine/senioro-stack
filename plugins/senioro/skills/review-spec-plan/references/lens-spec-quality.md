# Lens Q: spec quality

Review the target as a **communication document**, not code: a good plan gives an implementer enough context to build it in one pass without ambiguity. Read linked companion files as part of the target, and spot-check the paths and patterns it names with Grep or Glob (no full codebase audit). Rate each of the seven dimensions below and return the ratings with your findings. Also apply the hygiene rules file your brief names; each violation is a finding under the dimension it fits. Set each finding's severity with the Severity mapping at the end.

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
- Dead references: `#N` ids, anchors and paths that resolve to nothing (check each one)

### 4. Compactness

Right level of detail — not a long story, not a telegram.

- **Too verbose:** Repeated points, hedging prose, narrative where lists work, inline rationale that should be separated
- **Too terse:** Decisions without rationale, hand-waving ("handle errors appropriately"), one-liners where nuance is needed
- **Calibration:** Rules should be 1-2 sentences. If a rule needs more, it needs an example, not more prose. Decision logic should be tables/flowcharts, never paragraphs.
- **One copy:** one canonical document, and one place per fact; other sections cite it instead of restating it

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
- **No tool names:** no skill, agent tool or slash-command names; the plan says what happens, not which tool does it

### 7. Logic Presentation

Does it use appropriate methods to explain complex logic?

- Decision trees or condition tables for branching logic
- State diagrams (text-based) for stateful behavior
- Sequence descriptions for multi-step processes
- Flowcharts (mermaid, ascii) for workflows
- Pseudo-code for algorithms
- **Red flag:** Complex branching described only in prose — if you re-read to follow the branches, it needs a diagram

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

## What makes a good finding

- It cites specific text (a section, a quote or a `path:line`), explains why it is a problem, not just that it is, and gives a concrete fix: draft wording, or the restructuring. Never implementation code; name the kind of diagram, don't draw it.
- It separates "this is broken" from "I would have done this differently", and respects the stated goal and the recorded decisions.
- A dimension with no issues is Ready: an implementer can start from that section with confidence. Zero findings is a valid result; no restating the plan, no praise.
- Only if the target has skill frontmatter (`name`, `description`, `disable-model-invocation`, ...): check the fields match the body and are supported.
