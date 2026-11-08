---
name: resolve-roster
description: Resolve a roster of two real findings and one false finding (spec 002 U9, case 2).
tags: [baseline, resolve]
runs: 3
max_turns: 60
timeout_seconds: 1500
allowed_tools: [Read, Glob, Grep, Skill, Agent]
append_system_prompt: |
  Sandbox note for this session: the shell accepts only git commands, and git itself may fail here, so nothing can be run (no sed, node or npm). Read files with the Read tool, including the skill sections you are told to print with sed. Every subagent has the same limits, so say so in its brief. Evidence from the code and tests as written counts, and there is no user to ask.
---

/senioro:resolve-review-findings review-report.md
