# Third-party notices

## pstack (Lauren Tan)

Four skills in `plugins/senioro/skills/` are ported from the `pstack` plugin in the cursor/plugins repository, and parts of the workflow-stage skills are adapted from it (the files after them in the list below).

- Source: https://github.com/cursor/plugins/tree/c47b12849e43f18d5c374c7069c744cc55b0ea00/pstack
- Pinned commit: `c47b12849e43f18d5c374c7069c744cc55b0ea00`
- License: MIT (`pstack/LICENSE`, reproduced below)

Ported files (source path under `pstack/skills/` → path under `plugins/senioro/skills/`):

- `bro/SKILL.md` → `bro/SKILL.md`, unmodified.
- `unslop/SKILL.md` → `unslop/SKILL.md`, modified:
  - removed `disable-model-invocation: true`, so the skill is model-invocable;
  - rewrote the description as "Cuts AI tells from any writing ... Use when ...", without "Must always apply."
- `technical-writing/SKILL.md` → `technical-writing/SKILL.md`, modified:
  - removed `disable-model-invocation: true`, so the skill is model-invocable;
  - rewrote the description as "Applies a layered technical-writing standard ... Use when ...", without the `/technical-writing` command;
  - changed the two references to the `unslop` skill to `/senioro:unslop`;
  - removed "swarm logs" (output of pstack's `/swarm` skill, which is not ported) from the list of things not to paste into a PR body;
  - removed the Cursor-specific sentence "Indent code snippets with tabs."
- `typescript-best-practices/SKILL.md` → `typescript-best-practices/SKILL.md`, modified:
  - removed `disable-model-invocation: true`, so the skill is model-invocable (`paths` kept);
  - rewrote the description as "Applies TypeScript best practices: ... Use when ...";
  - pointed the references to the type-system-discipline and boundary-discipline principle skills at the folded-in files below.
- `typescript-best-practices/references/patterns.md` → `typescript-best-practices/references/patterns.md`, modified: pointed the two references to the principle skills at the folded-in files below.
- `principle-type-system-discipline/SKILL.md` → `typescript-best-practices/references/type-system-discipline.md`, modified:
  - folded in as a reference file, without its frontmatter;
  - pointed the boundary-discipline reference at `references/boundary-discipline.md`;
  - removed the reference to the encode-lessons-in-structure principle skill, which is not ported.
- `principle-boundary-discipline/SKILL.md` → `typescript-best-practices/references/boundary-discipline.md`, modified: folded in as a reference file, without its frontmatter.
- `interrogate/references/rubric.md` → `review-spec-plan/references/lens-root-cause.md`, modified: the symptom-versus-root and bolted-on-versus-integrated checks, condensed and rewritten as a spec-review lens.
- `interrogate/references/reviewer-prompt.md` → `review-spec-plan/references/lens-architect.md`, `review-spec-plan/references/lens-spec-quality.md`, `review-spec-plan/references/lens-root-cause.md`, `review-spec-plan/references/lens-blast-radius.md`, modified: "what makes a good finding" rewritten as each lens's footer; in the root-cause lens, the rule that a reviewer does not question the intent is inverted, so a spec review may question the intent and the premise.
- `interrogate/SKILL.md` → `review-spec-plan/references/lead-judgment.md`, `review-spec-plan/review.workflow.js`, modified: the synthesis step and its four buckets became the filter's merge and buckets, run by a separate verifier seat inside a Workflow script.
- `interrogate/references/lead-judgment.md` → `review-spec-plan/references/lead-judgment.md`, modified: the filtering principles moved near-verbatim; "conversation context" became the spec's Decisions table, its non-goals and the decisions context the brief names; added the round-2+ rule for findings an earlier round already ruled on, and the report format.
- `principle-fix-root-causes/SKILL.md` → `write-spec/SKILL.md`, `check-before-pr/SKILL.md`, `review-spec-plan/references/lens-root-cause.md`, modified: rewritten as steps (reproduce, ask why down to the source, no silencing guards, sweep for the pattern, suspect state after a restart) in the spec's root-cause step, the pre-PR fix rule and the root-cause lens.
- `principle-attack-the-premise/SKILL.md`, `principle-redesign-from-first-principles/SKILL.md` → `review-spec-plan/references/lens-root-cause.md`, modified: condensed into the lens's premise and bolted-on checks.
- `principle-subtract-before-you-add/SKILL.md` → `write-spec/references/hygiene.md`, `review-spec-plan/references/lens-architect.md`, modified: condensed into the "compress" hygiene rule and the architect lens's subtract-before-you-add check.
- `principle-minimize-reader-load/SKILL.md`, `architect/references/design-red-flags.md` → `review-spec-plan/references/lens-architect.md`, modified: condensed into the architect lens's reader-load test and design red-flag checks.
- `architect/references/rationale-template.md` → `write-spec/references/spec-template.md`, `review-spec-plan/references/lens-architect.md`, modified: problem, usage, shape, trade-offs, alternatives and open questions became spec-template sections and the architect lens's alternatives check; the synthesis decision is dropped.
- `blast-radius/SKILL.md` → `review-spec-plan/references/lens-blast-radius.md`, modified: rewritten as a spec-review lens; the arena step, the companion skills and the unslop pass are dropped.
- `figure-it-out/SKILL.md` → `frame-goal/SKILL.md`, `preflight/SKILL.md`, modified: the falsifiable done predicate, quantified scope and rigor became frame-goal steps, and "capture a baseline before the change" became preflight's baseline gate run; the line about never blocking on the human is dropped.
- `create-verification-skill/SKILL.md` → `preflight/SKILL.md`, modified: the read-only "doctor" check became preflight's auth and tool checks.
- `recall/SKILL.md` → `status/SKILL.md`, modified: the capsule-first digest with a single concrete next move became the status fields; transcript mining is dropped.
- `poteto-mode/playbooks/babysit.md` → `check-before-pr/SKILL.md`, modified: comment text as untrusted data, classify before retrying, failures in code the diff never touches are not the branch's, no churn to quiet a bot, merge only on an explicit request; the forge watcher, the loop command and the stack topology are dropped.

```
MIT License

Copyright (c) 2026 Lauren Tan

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## mattpocock/skills (Matt Pocock)

Parts of the workflow-stage skills in `plugins/senioro/skills/` are adapted from the mattpocock/skills repository.

- Source: https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60
- Pinned commit: `d81f3a183412e71a5b1e84ca21bc1a35eea03a60`
- License: MIT (`LICENSE`, reproduced below)

Adapted files (source path in the repository → path under `plugins/senioro/skills/`):

- `skills/productivity/grilling/SKILL.md` → `frame-goal/SKILL.md`, modified: the design tree, the decision frontier, a recommended answer per question, facts gathered through a subagent, and "done when the frontier is empty"; asks one question at a time instead of the whole frontier per round.
- `docs/engineering/to-spec.md` → `frame-goal/SKILL.md`, `write-prd/SKILL.md`, modified: the triage became frame-goal's route table; "anything the spec asserts that you never said is a defect" became write-prd's closing check.
- `skills/engineering/to-spec/SKILL.md` → `write-prd/SKILL.md`, `write-prd/references/prd-template.md`, `write-spec/SKILL.md`, `write-spec/references/spec-template.md`, modified: problem, solution, user stories and out of scope became the PRD; seams before prose and the implementation and testing decisions became spec steps and sections; no tracker or label; the number of user stories scales with the scope; paths are allowed as evidence in a spec.
- `skills/engineering/to-tickets/SKILL.md` → `write-spec/SKILL.md`, modified: vertical slices, blocking edges and expand–contract became the spec's units step.
- `skills/engineering/diagnosing-bugs/SKILL.md` → `write-spec/SKILL.md`, `review-spec-plan/references/lens-root-cause.md`, modified: the red-capable repro loop as the completion criterion and the correct seam became write-spec's root-cause step and the root-cause lens's bug-spec check.
- `skills/engineering/codebase-design/SKILL.md` → `review-spec-plan/references/lens-architect.md`, modified: the deletion test and "one adapter means a hypothetical seam" became the architect lens's seam checks.
- `skills/productivity/handoff/SKILL.md` → `write-spec/references/hygiene.md`, modified: "reference artifacts, never duplicate them" became the one-copy rule; the part that names skills inside the artifact is dropped.

Not ported: the `pr` skill, which embeds HumanLayer text.

```
MIT License

Copyright (c) 2026 Matt Pocock

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
