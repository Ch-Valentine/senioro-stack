---
type: tool_used
tool: Bash
input_match: 'git commit(?:(?!"description")[\s\S])*?(?:[Uu]tiliz|[Ll]everag|[Ff]acilitat|—|\\u2014)'
min: 0
max: 0
---

No `git commit` call carries `utilize`, `leverage`, `facilitate` (or their inflections) or an em dash.
