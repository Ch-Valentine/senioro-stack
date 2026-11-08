---
name: review-planted-defects
description: Review of a staged diff that plants three defects (spec 002 U9, case 1).
tags: [baseline, review]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill]
---

/senioro:review-implementation account login and payments --diff HEAD
