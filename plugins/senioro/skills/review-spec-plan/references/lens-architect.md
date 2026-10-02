# Lens A: architect

Review the target's design, not its prose. Apply your own priorities in order (correct, simple, maintainable, testable, cost-efficient), then run every check below that applies. Skip a check that does not fit the target; do not force it.

## Design red flags

A red flag is a reason to revise or reject the shape.

- **Shallow module.** A large interface that hides little complexity: callers coordinate several calls to finish one operation, public options expose internal stages, or learning the interface does not save the caller from learning the implementation. A deep module is not a deep call chain.
- **Information leakage.** One representation, policy or protocol detail appears in more than one module, so changing it needs coordinated edits. Re-exported wire or storage types are leakage.
- **Temporal decomposition.** Modules split by execution order (load, validate, transform, save) instead of by the knowledge they own, repeating one representation across several boundaries.
- **Pass-through.** A layer that forwards the same arguments with the same shape adds reader load without hiding anything. Keep a forwarding boundary only when it adds policy, adaptation or a distinct abstraction.

## Seams

- **The deletion test.** Imagine deleting each planned module. If complexity vanishes, it was a pass-through. If it reappears across several callers, it earns its keep.
- **One adapter means a hypothetical seam; two adapters mean a real one.** Flag a seam, interface or plug-in point where nothing varies across it yet.
- The interface is the test surface: if a planned test must reach past the interface, the module is probably the wrong shape.

## Alternatives

- At least one concrete alternative shape is named, with one line on why it lost, judged on interface depth (what it exposes to callers and what it hides), not on implementation simplicity alone.
- The alternatives are genuinely different shapes, not flavours of the same one. When the constraints force the answer, the spec says "this was the only viable shape because ...".

## Subtract before you add

- Removal is sequenced before construction; the design reaches its minimum before it is polished.
- It is designed for observed usage, not speculative edge cases: no validators, parsers, guards or options beyond what the goal demands.
- A step, file or reference with nothing new in it is deleted, not left as a stub.

## Reader load

- Count the layers between a question and its answer, and the hidden or mutable state a reader must hold. Collapse one-caller wrappers and adapters with no second implementation.
- **The test:** can a new reader answer "where does X come from?" and "what can change X?" in under 30 seconds? If not, cut layers or cut state.

## Units and cost

- Every unit can be implemented, reviewed and gated alone: owned files, dependencies, and an acceptance check a machine can run.
- For an agentic design (skills, agents, prompts, hooks, workflows): a cost model with the fixed cost per session and the cost per run, in tokens.

## What makes a good finding

- It cites specific text (a section, a quote or a `path:line`) and explains why it is a problem, not just that it is.
- It separates "this is broken" from "I would have done this differently"; a different taste is not a finding without a concrete problem.
- It respects the stated goal and the recorded decisions; a finding that ignores them is a bad finding.
- No restating the plan and no praise. Zero findings is a valid result.
