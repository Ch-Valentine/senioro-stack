#!/usr/bin/env bash
# G2: tl-guard fixtures (SPEC section 7). Prints PASS n/n; exits non-zero on any failure.
# Runs plugins/senioro/scripts/tl-guard.sh with HOME set to a temp dir that holds the s1 strict marker.
set -uo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
GUARD="$REPO/plugins/senioro/scripts/tl-guard.sh"
[ -f "$GUARD" ] || { echo "FAIL: $GUARD missing"; exit 1; }

H=$(mktemp -d) || { echo "FAIL: mktemp -d"; exit 1; }
trap 'rm -rf "${H:?}"' EXIT
mkdir -p "$H/.cache/senioro-tl" && touch "$H/.cache/senioro-tl/s1.strict"

total=0; passed=0; OUT=""; RC=0

# guard <stdin>: runs the guard; sets OUT (stdout) and RC (exit code).
guard() { OUT=$(printf '%s' "$1" | HOME="$H" bash "$GUARD" 2>/dev/null); RC=$?; }

# check <case> <expected exit> [extra failure detail]
check() {
  total=$((total + 1))
  if [ "$RC" -eq "$2" ] && [ -z "${3:-}" ]; then
    passed=$((passed + 1))
  else
    echo "FAIL case $1: exit $RC, expected $2${3:+; $3}"
  fi
}

# hin <tool> <tool_input json> [session]: builds the hook input.
hin() { printf '{"session_id":"%s","tool_name":"%s","tool_input":%s}' "${3:-s1}" "$1" "$2"; }

READ_R=$(hin Read '{"file_path":"/r/a.ts"}')

# 1 Read /r/a.ts, agent_id set
guard '{"session_id":"s1","agent_id":"a1","tool_name":"Read","tool_input":{"file_path":"/r/a.ts"}}'; check 1 0
# 2 Read /r/a.ts, session s2 (no marker)
guard "$(hin Read '{"file_path":"/r/a.ts"}' s2)"; check 2 0
# 3 Read /r/a.ts -> deny JSON naming senioro:runner, never senioro-runner
guard "$READ_R"
d=""
printf '%s' "$OUT" | jq -e '.hookSpecificOutput.permissionDecision=="deny"' >/dev/null 2>&1 || d+="no deny decision on stdout "
r=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null)
case "$r" in *senioro:runner*) ;; *) d+="reason lacks senioro:runner " ;; esac
case "$r" in *senioro-runner*) d+="reason contains senioro-runner " ;; esac
check 3 2 "$d"
# 4 Read a run-dir file
guard "$(hin Read '{"file_path":"/h/.cache/senioro-tl/runs/x/r.md"}')"; check 4 0
# 5 Edit a memory file
guard "$(hin Edit '{"file_path":"/h/.claude/projects/p/memory/MEMORY.md"}')"; check 5 0
# 6 Write into a scratchpad
guard "$(hin Write '{"file_path":"/private/tmp/x/scratchpad/f"}')"; check 6 0
# 7 Glob path /r
guard "$(hin Glob '{"path":"/r"}')"; check 7 2
# 8 Bash cat /r/a
guard "$(hin Bash '{"command":"cat /r/a"}')"; check 8 2
# 9 Bash cd /r && grep foo a
guard "$(hin Bash '{"command":"cd /r && grep foo a"}')"; check 9 2
# 10 Bash git status
guard "$(hin Bash '{"command":"git status"}')"; check 10 0
# 11 Bash cat of a run-dir path
guard "$(hin Bash '{"command":"cat ~/.cache/senioro-tl/x"}')"; check 11 0
# 12 not json
guard 'not json'; check 12 0
# 13 empty stdin
guard ''; check 13 0
# 14 tool Agent
guard "$(hin Agent '{"prompt":"x"}')"; check 14 0
# 15 case 3 without jq on PATH -> fail open
OUT=$(printf '%s' "$READ_R" | HOME="$H" PATH=/nonexistent /bin/bash "$GUARD" 2>/dev/null); RC=$?
check 15 0
# 16 Grep path in a run dir -> allowed only if the guard reads .path (else empty target, denied)
guard "$(hin Grep '{"pattern":"x","path":"/h/.cache/senioro-tl/runs/x"}')"; check 16 0
# 17 NotebookEdit notebook_path in a scratchpad -> allowed only if the guard reads .notebook_path
guard "$(hin NotebookEdit '{"notebook_path":"/private/tmp/x/scratchpad/n.ipynb"}')"; check 17 0
# 18-20 Edit, Write, MultiEdit /r/a.ts
guard "$(hin Edit '{"file_path":"/r/a.ts"}')"; check 18 2
guard "$(hin Write '{"file_path":"/r/a.ts"}')"; check 19 2
guard "$(hin MultiEdit '{"file_path":"/r/a.ts"}')"; check 20 2
# 21 Bash cd /r; cat a (semicolon form of the cd strip)
guard "$(hin Bash '{"command":"cd /r; cat a"}')"; check 21 2
# 22 no session_id -> fail open, even with a marker at the empty-session path (.strict)
touch "$H/.cache/senioro-tl/.strict"
guard '{"tool_name":"Read","tool_input":{"file_path":"/r/a.ts"}}'; check 22 0
rm -f "$H/.cache/senioro-tl/.strict"
# 23 Read with no path in tool_input -> empty target, denied
guard "$(hin Read '{}')"; check 23 2
# 24-35 Bash <word> /r/x for every other reader or writer word in the guard's list
n=24
for w in sed head tail less more bat rg awk ugrep cp mv tee; do
  guard "$(hin Bash "{\"command\":\"$w /r/x\"}")"; check "$n ($w)" 2
  n=$((n + 1))
done
# 36 Grep path /r (split from 16: Grep is in the guarded tool list)
guard "$(hin Grep '{"pattern":"x","path":"/r"}')"; check 36 2
# 37 NotebookEdit notebook_path /r/n.ipynb (split from 17: NotebookEdit is in the guarded tool list)
guard "$(hin NotebookEdit '{"notebook_path":"/r/n.ipynb"}')"; check 37 2

if [ "$passed" -eq "$total" ] && [ "$total" -eq 37 ]; then
  echo "PASS $passed/$total"
else
  echo "FAIL $passed/$total"; exit 1
fi
