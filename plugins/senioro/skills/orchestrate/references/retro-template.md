## <YYYY-MM-DD> <session id, first 8 chars>: <goal, ≤ 10 words>
Wallet <value>; review <Status line, or none>
<spec line from token-spend.sh>
<build line from token-spend.sh>
<seats line from token-spend.sh>
Struggles: <≤ 3 phrases from the brief, or none>
---
Append only the six lines above. Run `bash ../../../scripts/token-spend.sh ~/.claude/projects/*/<session id>.jsonl <flag>` from this file's directory; <flag> is the brief's `--split <ts>` (UTC, like 2026-11-08T13:47:18Z) or `--phase spec|build`.
