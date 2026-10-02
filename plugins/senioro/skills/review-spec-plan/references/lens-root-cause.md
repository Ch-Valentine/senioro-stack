# Lens R: root cause versus dirty fix

**Spec mode: you may question the intent and the premise.** A code reviewer assumes the goal is right and challenges the execution. Here the goal, the premise and the chosen layer are all in scope: ask whether the planned change fixes the source of the problem or papers over a symptom.

Answering this often needs reads beyond the files the spec names: callers, callees, types, sibling modules. Follow the call chain and understand why the code exists before you judge whether the change sits at the right layer.

## Symptom or root

- Guard clauses that mask a deeper invariant violation; retries that hide a broken contract; type casts that silence a modelling error.
- A planned workaround: why is it needed, and what would the proper fix look like?
- A fix in module A that belongs in module B's contract.
- Instructions where structure would be better: a "don't do X" note or a convention someone must remember, where a type constraint, a lint rule, a hook or a runtime check could make the wrong thing impossible.

## Bolted on or integrated

- If the new requirement had been known from the start, would the design look like this? Redesign as if it had been a foundational assumption, then deliver incrementally.
- The change propagates through every reference: types, docs, examples, rationale.
- Legacy dual paths: a new path added while the old one stays alive. With no external consumers, callers migrate and the old path is deleted in the same wave.

## Attack the premise

- Two or more failed fixes that share one premise are evidence about the premise, not the fixes. Name the premise: the one sentence every failed fix assumed.
- Demand a census before the next fix: which actors hold the imbalance, as a rerunnable script. If the same few actors hold it on every run, find what assigns them that role and remove the asymmetry instead of compensating for it.
- If the census is even, the premise is not the cause; say so.

## Fix root causes

- Reproduce first; ask "why" until the root is reached.
- A workaround that needs a paragraph of justification means the design is wrong.
- Fix the pattern, not the instance: the spec searches for the same pattern elsewhere and covers all of it.
- When stuck, instrument; don't guess.
- "Fails after restart": suspect stale persistent state (config, caches, lock files, serialized state) before code.

## Bug specs

- The spec carries a red-capable repro: one command, already run, that drives the real bug path and asserts the user's exact symptom. "Runs without erroring" is not red-capable.
- The regression test sits at a correct seam, one that exercises the real bug pattern as it occurs at the call site. If no correct seam exists, that is itself a finding.

## What makes a good finding

- It cites specific text (a section, a quote or a `path:line`) and explains why it is a problem, not just that it is.
- It separates "this is broken" from "I would have done this differently".
- It names the root, the layer the fix belongs in, and the evidence that it is the root.
- No restating the plan and no praise. Zero findings is a valid result.
