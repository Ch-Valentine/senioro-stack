---
name: babysit-triage
description: One babysit round on a saved PR digest with four planted signals (design U6).
tags: [babysit, triage]
runs: 3
max_turns: 60
timeout_seconds: 1500
allowed_tools: [Read, Glob, Grep, Skill, Agent]
append_system_prompt: |
  Sandbox note for this session: the shell accepts only git commands, and git itself may fail here, so nothing can be run (no sed, node, npm or gh). Read files with the Read tool, including the skill sections you are told to print with sed. Every subagent has the same limits, so say so in its brief. Evidence from the code, the tests and the CI log as written counts, and there is no user to ask.
---

/senioro:babysit-pr --digest pr-signals.md
