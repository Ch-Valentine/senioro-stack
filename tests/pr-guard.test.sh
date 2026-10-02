#!/usr/bin/env bash
# G2: pr-guard fixtures (SPEC-workflow section 11). Prints PASS n/n; exits non-zero on any failure.
# Runs plugins/senioro/scripts/pr-guard.sh with HOME set to a temp dir and cwd set to a temp git repo with one commit.
# A decision is read from the hook's stdout JSON. "ask" needs exit 0; "deny" may exit 0 or 2 (both block).
set -uo pipefail

# If probe P2 shows that "ask" does not stop a call under bypassPermissions, every ask becomes deny (SPEC-workflow section 8).
ASK=ask

REPO=$(cd "$(dirname "$0")/.." && pwd)
GUARD="$REPO/plugins/senioro/scripts/pr-guard.sh"
[ -f "$GUARD" ] || { echo "FAIL: $GUARD missing"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq missing"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "FAIL: git missing"; exit 1; }

T=$(mktemp -d) || { echo "FAIL: mktemp -d"; exit 1; }
T=$(cd "$T" && pwd -P)
trap 'rm -rf "${T:?}"' EXIT
# Fixture repos see no user or system git config, and git discovery stops at $T.
export GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$T"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
RPT="$T/prepr-1.md"
echo "round report" > "$RPT"

total=0; passed=0; OUT=""; RC=0

# g <repo> <git args>: quiet git in a fixture repo.
g() { local w=$1; shift; HOME="$T" git -C "$w" -c commit.gpgsign=false "$@" >/dev/null 2>&1; }

# newrepo <name>: a repo with one commit holding a.txt and b.txt; prints its path.
newrepo() {
  local w="$T/$1"
  mkdir -p "$w" && g "$w" init -q && echo a > "$w/a.txt" && echo b > "$w/b.txt" \
    && g "$w" add -A && g "$w" commit -q -m init && echo "$w"
}

# newhome <name>: an empty HOME; prints its path.
newhome() { mkdir -p "$T/$1" && echo "$T/$1"; }

# bin <cwd> <command>, tin <cwd> <tool>: hook input for a Bash command or another tool.
bin() { jq -cn --arg c "$1" --arg x "$2" '{session_id:"s1",cwd:$c,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$x}}'; }
tin() { jq -cn --arg c "$1" --arg t "$2" '{session_id:"s1",cwd:$c,hook_event_name:"PreToolUse",tool_name:$t,tool_input:{owner:"o",repo:"r"}}'; }

# guard <home> <cwd> <stdin>: runs the guard; sets OUT (stdout) and RC (exit code).
guard() { OUT=$(cd "$2" && printf '%s' "$3" | HOME="$1" bash "$GUARD" 2>/dev/null); RC=$?; }

# rec <home> <cwd> <flag> [arg]: runs pr-guard.sh --record or --override; returns its exit code.
rec() { (cd "$2" && HOME="$1" bash "$GUARD" "$3" ${4:+"$4"} >/dev/null 2>&1); }

# pass <case> [failure detail]: counts the case; an empty detail is a pass.
pass() {
  total=$((total + 1))
  if [ -z "${2:-}" ]; then passed=$((passed + 1)); else echo "FAIL case $1: $2"; fi
}

# silent <case>: no output, exit 0.
silent() {
  local d=""
  [ "$RC" -eq 0 ] || d+="exit $RC, expected 0 "
  [ -z "$OUT" ] || d+="unexpected output: $OUT "
  pass "$1" "$d"
}

# want <case> <ask|deny> [reason substring, case-insensitive] [extra failure detail]
want() {
  local d="${4:-}" got r
  got=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  r=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)
  [ "$got" = "$2" ] || d+="decision '$got', expected '$2' (stdout: $OUT) "
  case "$2:$RC" in ask:0|deny:0|deny:2) ;; *) d+="exit $RC with decision $2 " ;; esac
  [ -z "${3:-}" ] || printf '%s' "$r" | grep -qiF -- "$3" || d+="reason lacks '$3': $r "
  pass "$1" "$d"
}

W=$(newrepo repo) || { echo "FAIL: fixture repo"; exit 1; }
TREE=$(git -C "$W" rev-parse 'HEAD^{tree}')

# Ask cases 1-11: a pass marker recorded for the repo's tree.
H1=$(newhome h1)
mkdir -p "$H1/.cache/senioro-tl/prepr" && echo "$RPT" > "$H1/.cache/senioro-tl/prepr/$TREE"
n=1
for c in 'gh pr create --fill' 'gh pr merge 12 --squash' 'cd app && gh pr create -t x' 'glab mr create' \
         'glab mr merge 3' 'GH_PROMPT_DISABLED=1 gh pr create' '/usr/local/bin/gh pr create' 'az repos pr create'; do
  guard "$H1" "$W" "$(bin "$W" "$c")"; want "$n ($c)" "$ASK"
  n=$((n + 1))
done
for t in mcp__github__create_pull_request mcp__github__merge_pull_request mcp__gitlab__create_merge_request; do
  guard "$H1" "$W" "$(tin "$W" "$t")"; want "$n ($t)" "$ASK"
  n=$((n + 1))
done

# Silent cases 12-18: exit 0, no output.
for c in 'gh pr view 12' 'gh pr checks' 'git push origin feat' 'echo "gh pr create"'; do
  guard "$H1" "$W" "$(bin "$W" "$c")"; silent "$n ($c)"
  n=$((n + 1))
done
guard "$H1" "$W" "$(tin "$W" mcp__github__get_pull_request)"; silent 16
guard "$H1" "$W" 'not json'; silent 17
guard "$H1" "$W" ''; silent 18

# 19 case 1 with no jq and no git on PATH -> ask, could not be verified
OUT=$(cd "$W" && printf '%s' "$(bin "$W" 'gh pr create --fill')" | HOME="$H1" PATH=/nonexistent /bin/bash "$GUARD" 2>/dev/null); RC=$?
want 19 "$ASK" "could not be verified"

# 20-22 no marker -> deny; 20 names the pre-PR loop
H2=$(newhome h2)
guard "$H2" "$W" "$(bin "$W" 'gh pr create')"; want 20 deny "pre-PR loop"
guard "$H2" "$W" "$(bin "$W" 'gh pr merge 12')"; want 21 deny
guard "$H2" "$W" "$(tin "$W" mcp__github__create_pull_request)"; want 22 deny

# 23 --record with an uncommitted edit, then commit exactly that edit -> ask (OQ7)
H=$(newhome h23); R=$(newrepo r23)
echo fix >> "$R/a.txt"
d=""; rec "$H" "$R" --record "$RPT" || d="--record exited non-zero "
g "$R" add -A && g "$R" commit -q -m fix
guard "$H" "$R" "$(bin "$R" 'gh pr create')"; want 23 "$ASK" "" "$d"

# 24 --record, then commit one more change -> deny
H=$(newhome h24); R=$(newrepo r24)
echo fix >> "$R/a.txt"
d=""; rec "$H" "$R" --record "$RPT" || d="--record exited non-zero "
g "$R" add -A && g "$R" commit -q -m fix
echo more >> "$R/b.txt" && g "$R" add -A && g "$R" commit -q -m more
guard "$H" "$R" "$(bin "$R" 'gh pr create')"; want 24 deny "" "$d"

# 25 --record with two uncommitted edits, commit only one -> deny
H=$(newhome h25); R=$(newrepo r25)
echo fix >> "$R/a.txt"; echo fix >> "$R/b.txt"
d=""; rec "$H" "$R" --record "$RPT" || d="--record exited non-zero "
g "$R" add a.txt && g "$R" commit -q -m half
guard "$H" "$R" "$(bin "$R" 'gh pr create')"; want 25 deny "" "$d"

# 26 --override on an unrecorded tree -> ask, user override
H=$(newhome h26); R=$(newrepo r26)
d=""; rec "$H" "$R" --override || d="--override exited non-zero "
guard "$H" "$R" "$(bin "$R" 'gh pr create')"; want 26 "$ASK" "user override" "$d"

# 27 cwd outside any git repo -> ask, could not be verified
mkdir -p "$T/norepo"
guard "$H1" "$T/norepo" "$(bin "$T/norepo" 'gh pr create')"; want 27 "$ASK" "could not be verified"

# 28 --record leaves git status --porcelain and git diff --cached unchanged (the real index is untouched)
H=$(newhome h28); R=$(newrepo r28)
echo staged >> "$R/a.txt" && g "$R" add a.txt
echo unstaged >> "$R/b.txt"; echo new > "$R/c.txt"
s1=$(git -C "$R" status --porcelain); c1=$(git -C "$R" diff --cached)
d=""; rec "$H" "$R" --record "$RPT" || d+="--record exited non-zero "
[ "$s1" = "$(git -C "$R" status --porcelain)" ] || d+="git status --porcelain changed "
[ "$c1" = "$(git -C "$R" diff --cached)" ] || d+="git diff --cached changed "
pass 28 "$d"

if [ "$passed" -eq "$total" ] && [ "$total" -eq 28 ]; then
  echo "PASS $passed/$total"
else
  echo "FAIL $passed/$total"; exit 1
fi
