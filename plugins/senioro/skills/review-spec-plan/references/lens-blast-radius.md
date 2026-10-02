# Lens B: blast radius

Find what the planned change breaks beyond the files it names, before it is built. Listing the callers is not the job; anyone can grep those. The job is the breakage grep will not show.

A blast-radius writeup that sounds right is worthless: it reads as convincing whether or not it is true. Find the one or two facts the plan's safety depends on and prove them.

## Steps

1. **Read the change.** What the spec adds, changes and deletes, and what will behave differently, including the part it does not spell out.
2. **Find the one fact it is safe because of.** Most risky-looking changes are safe because of a single fact, such as "this only drops cache entries that are already dead". If it holds, most risky cases clear at once. Spend your time here, not on a long list of maybes.
3. **Look where grep stops.** Read the source of the libraries the plan calls, at their pinned versions and local patches. Work out when things run (async order, teardown, hooks). Follow what a symbol search misses: wire formats, the JSON an API returns, DB columns, another language reading the same bytes, feature flags, timing, code three hops downstream.
4. **Be honest about each risk.** Give it a real likelihood and a real cost. Keep the confirmed risks; list the ones you checked and cleared separately. A search that finds nothing is still an answer; never invent a caller or an API.
5. **Prove the one fact.** Take it as far down the ladder below as is cheap, and say where it stopped.

## How sure are you

1. You said so. Worthless on its own.
2. You pointed at the line: a real `file:line`, or the library's own source.
3. You showed the bad case cannot happen: you walked the failure step by step and it does not reach.
4. You ran it: a script or test that calls the real code and fails loud if you are wrong.
5. You reproduced it in the running app.

Step 4 is usually one small script that imports what the project ships and calls the exact function in question. At rigor `high` (when your brief asks for it), the one fact must reach step 4; otherwise mark it unproven.

## What goes in your notes

- **What it does,** including the part that is not obvious.
- **The one fact it is safe because of,** the ladder step it reached, and the proof (or "unproven").
- **Risks:** how each one breaks, `file:line`, likelihood and cost, and how to check it. Each confirmed risk is also a finding.
- **Cleared:** what you checked and why it is fine.
- **Before merge:** the cheapest test or repro that would catch the real breakage.

## What makes a good finding

- It cites specific text or code (a section, a quote or a `path:line`) and explains how the break happens, not just that it might.
- It separates "this is broken" from "I would have done this differently", and a real execution path from a hypothetical.
- It respects the stated goal and the recorded decisions.
- No restating the plan and no praise. Zero findings is a valid result.
