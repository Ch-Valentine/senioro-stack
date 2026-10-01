# Third-party notices

## pstack (Lauren Tan)

Four skills in `plugins/senioro/skills/` are ported from the `pstack` plugin in the cursor/plugins repository.

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
