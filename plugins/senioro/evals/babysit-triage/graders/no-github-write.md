---
type: tool_used
tool: Bash
input_match: 'gh (?:pr|issue) (?:comment|review|merge)|gh api'
min: 0
max: 0
---

No Bash call writes to GitHub or calls `gh api`: the `--digest` run is read-only and posts no reply unasked.
