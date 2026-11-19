#!/usr/bin/env bash
# G2: pr-guard fixtures (SPEC-workflow section 11; cases 29-39 are the change class, spec 002 U7; cases 42-50 are the
# once-per-HEAD create reminder, --tree, the two-marker --record and merges, which are always silent). Prints PASS n/n; exits non-zero on any failure.
# The hook never asks: a create with a marker, a docs diff or no way to verify it is silent; with an unchecked code
# diff it is denied once per HEAD tree, then silent. A merge (gh, glab, an MCP tool, or with a create in one command)
# is always silent.
# Runs plugins/senioro/scripts/pr-guard.sh with HOME set to a temp dir and cwd set to a temp git repo with one commit.
# A decision is read from the hook's stdout JSON. "deny" may exit 0 or 2 (both block).
set -uo pipefail

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

# rec <home> <cwd> <flag> [arg]: runs pr-guard.sh with that flag (--record); returns its exit code.
rec() { (cd "$2" && HOME="$1" bash "$GUARD" "$3" ${4:+"$4"} >/dev/null 2>&1); }

# pass <case> [failure detail]: counts the case; an empty detail is a pass.
pass() {
  total=$((total + 1))
  if [ -z "${2:-}" ]; then passed=$((passed + 1)); else echo "FAIL case $1: $2"; fi
}

# silent <case> [extra failure detail]: no output, exit 0.
silent() {
  local d="${2:-}"
  [ "$RC" -eq 0 ] || d+="exit $RC, expected 0 "
  [ -z "$OUT" ] || d+="unexpected output: $OUT "
  pass "$1" "$d"
}

# want <case> <deny> [reason substring, case-insensitive] [extra failure detail]
want() {
  local d="${4:-}" got r
  got=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  r=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)
  [ "$got" = "$2" ] || d+="decision '$got', expected '$2' (stdout: $OUT) "
  case "$2:$RC" in deny:0|deny:2) ;; *) d+="exit $RC with decision $2 " ;; esac
  [ -z "${3:-}" ] || printf '%s' "$r" | grep -qiF -- "$3" || d+="reason lacks '$3': $r "
  pass "$1" "$d"
}

# denyonce <case> <home> <cwd> <stdin> [extra failure detail]: deny naming the pre-PR loop, then the same input
# again is silent.
denyonce() {
  guard "$2" "$3" "$4"; want "$1" deny "pre-PR loop has not passed" "${5:-}"
  guard "$2" "$3" "$4"; silent "$1 retry"
}

W=$(newrepo repo) || { echo "FAIL: fixture repo"; exit 1; }
TREE=$(git -C "$W" rev-parse 'HEAD^{tree}')

# Cases 1-11: a pass marker recorded for the repo's tree. A create and a merge (2, 5, 10) are silent.
H1=$(newhome h1)
mkdir -p "$H1/.cache/senioro-tl/prepr" && echo "$RPT" > "$H1/.cache/senioro-tl/prepr/$TREE"
n=1
for c in 'gh pr create --fill' 'gh pr merge 12 --squash' 'cd app && gh pr create -t x' 'glab mr create' \
         'glab mr merge 3' 'GH_PROMPT_DISABLED=1 gh pr create' '/usr/local/bin/gh pr create' 'az repos pr create'; do
  guard "$H1" "$W" "$(bin "$W" "$c")"; silent "$n ($c)"
  n=$((n + 1))
done
for t in mcp__github__create_pull_request mcp__github__merge_pull_request mcp__gitlab__create_merge_request; do
  guard "$H1" "$W" "$(tin "$W" "$t")"; silent "$n ($t)"
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

# nojq <home> <cwd> <stdin>: runs the guard with no jq and no git on PATH; sets OUT and RC.
nojq() { OUT=$(cd "$2" && printf '%s' "$3" | HOME="$1" PATH=/nonexistent /bin/bash "$GUARD" 2>/dev/null); RC=$?; }

# 19 case 1 with no jq and no git on PATH -> silent (a create never asks)
nojq "$H1" "$W" "$(bin "$W" 'gh pr create --fill')"; silent 19

# 20-22 no marker: a create is denied once (20 names the pre-PR loop), and the same input again is silent;
# a merge (21) is silent every time. 22 uses its own HOME, as 20 already reminded on this tree.
H2=$(newhome h2)
guard "$H2" "$W" "$(bin "$W" 'gh pr create')"; want 20 deny "pre-PR loop has not passed"
d=""; [ -f "$H2/.cache/senioro-tl/prepr/$TREE.reminded" ] || d="no $TREE.reminded written "
guard "$H2" "$W" "$(bin "$W" 'gh pr create')"; silent "20 retry" "$d"
guard "$H2" "$W" "$(bin "$W" 'gh pr merge 12')"; silent 21
guard "$H2" "$W" "$(bin "$W" 'gh pr merge 12')"; silent "21 again"
H22=$(newhome h22)
guard "$H22" "$W" "$(tin "$W" mcp__github__create_pull_request)"; want 22 deny "pre-PR loop has not passed"
guard "$H22" "$W" "$(tin "$W" mcp__github__create_pull_request)"; silent "22 retry"

# 23 --record with an uncommitted edit, then commit exactly that edit -> silent (OQ7)
H=$(newhome h23); R=$(newrepo r23)
echo fix >> "$R/a.txt"
d=""; rec "$H" "$R" --record "$RPT" || d="--record exited non-zero "
g "$R" add -A && g "$R" commit -q -m fix
guard "$H" "$R" "$(bin "$R" 'gh pr create')"; silent 23 "$d"

# 24 --record, then commit one more change -> deny once
H=$(newhome h24); R=$(newrepo r24)
echo fix >> "$R/a.txt"
d=""; rec "$H" "$R" --record "$RPT" || d="--record exited non-zero "
g "$R" add -A && g "$R" commit -q -m fix
echo more >> "$R/b.txt" && g "$R" add -A && g "$R" commit -q -m more
denyonce 24 "$H" "$R" "$(bin "$R" 'gh pr create')" "$d"

# 25 --record with two uncommitted edits, commit only one -> deny once
H=$(newhome h25); R=$(newrepo r25)
echo fix >> "$R/a.txt"; echo fix >> "$R/b.txt"
d=""; rec "$H" "$R" --record "$RPT" || d="--record exited non-zero "
g "$R" add a.txt && g "$R" commit -q -m half
denyonce 25 "$H" "$R" "$(bin "$R" 'gh pr create')" "$d"

# 26 --override is gone: a usage error (exit 2) that records nothing.
H=$(newhome h26); R=$(newrepo r26)
rec "$H" "$R" --override; rc26=$?
d=""; [ "$rc26" -eq 2 ] || d+="--override exited $rc26, expected 2 "
[ ! -e "$H/.cache/senioro-tl/prepr" ] || d+="--override wrote markers "
pass 26 "$d"

# 27 cwd outside any git repo -> silent for a create and a merge
mkdir -p "$T/norepo"
guard "$H1" "$T/norepo" "$(bin "$T/norepo" 'gh pr create')"; silent 27
guard "$H1" "$T/norepo" "$(bin "$T/norepo" 'gh pr merge 3')"; silent "27 merge"

# 28 --record leaves git status --porcelain and git diff --cached unchanged (the real index is untouched)
H=$(newhome h28); R=$(newrepo r28)
echo staged >> "$R/a.txt" && g "$R" add a.txt
echo unstaged >> "$R/b.txt"; echo new > "$R/c.txt"
s1=$(git -C "$R" status --porcelain); c1=$(git -C "$R" diff --cached)
d=""; rec "$H" "$R" --record "$RPT" || d+="--record exited non-zero "
[ "$s1" = "$(git -C "$R" status --porcelain)" ] || d+="git status --porcelain changed "
[ "$c1" = "$(git -C "$R" diff --cached)" ] || d+="git diff --cached changed "
pass 28 "$d"

# Change class (spec 002 U7, #6 table, #19): with no marker, a diff with no code against the remote default branch
# is silent on a create, instead of "deny"; a merge is silent too. A fixture repo gets its base from a remote-tracking ref (no network).
# withbase <repo> [<ref>]: points origin/HEAD (or the named ref alone) at the repo's current commit.
withbase() {
  local w=$1 ref=${2:-main}
  g "$w" update-ref "refs/remotes/origin/$ref" HEAD || return 1
  [ -n "${2:-}" ] || g "$w" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
}
# commit <repo> <file>: adds the file and commits it.
commit() { mkdir -p "$1/$(dirname "$2")" && echo "$2" > "$1/$2" && g "$1" add -A && g "$1" commit -q -m "$2"; }

H=$(newhome h29)
R=$(newrepo r29); withbase "$R"; commit "$R" notes.md
guard "$H" "$R" "$(bin "$R" 'gh pr create')"; silent 29

R=$(newrepo r30); withbase "$R"; commit "$R" src/a.ts
denyonce 30 "$H" "$R" "$(bin "$R" 'gh pr create')"

R=$(newrepo r31); withbase "$R"; commit "$R" notes.md; commit "$R" src/a.ts
denyonce 31 "$H" "$R" "$(bin "$R" 'gh pr create')"

R=$(newrepo r32); withbase "$R"
guard "$H" "$R" "$(bin "$R" 'gh pr create')"; silent 32

R=$(newrepo r33); withbase "$R" master; commit "$R" notes.md
guard "$H" "$R" "$(bin "$R" 'gh pr create')"; silent 33

R=$(newrepo r34); withbase "$R"; commit "$R" notes.md
guard "$H" "$R" "$(tin "$R" mcp__github__create_pull_request)"; silent 34

R=$(newrepo r35); withbase "$R"; commit "$R" notes.md
guard "$H" "$R" "$(bin "$R" 'gh pr merge 12 --squash')"; silent 35

# A markdown file under a prompt path is code, not docs.
R=$(newrepo r36); withbase "$R"; commit "$R" .claude/skills/x/SKILL.md
denyonce 36 "$H" "$R" "$(bin "$R" 'gh pr create')"

# An untracked code file on top of a docs commit still makes the diff code.
R=$(newrepo r37); withbase "$R"; commit "$R" notes.md; echo x > "$R/b.py"
denyonce 37 "$H" "$R" "$(bin "$R" 'gh pr create')"

# A base that does not exist (no remote-tracking ref at all) keeps the deny, as cases 20-22. Its own HOME: case 37
# already reminded on this HEAD tree (a.txt, b.txt, notes.md).
H=$(newhome h39); R=$(newrepo r39); commit "$R" notes.md
denyonce 39 "$H" "$R" "$(bin "$R" 'gh pr create')"

# 40 --record with a ~/ report path (a quoted ~ is not expanded by the shell) reads it under HOME; commit exactly the edit -> silent
H=$(newhome h40); R=$(newrepo r40)
echo "round report" > "$H/prepr-tilde.md"
echo fix >> "$R/a.txt"
d=""; rec "$H" "$R" --record \~/prepr-tilde.md || d="--record exited non-zero "
grep -qxF "$H/prepr-tilde.md" "$H/.cache/senioro-tl/prepr"/* 2>/dev/null || d+="marker lacks the report path under HOME "
g "$R" add -A && g "$R" commit -q -m fix
guard "$H" "$R" "$(bin "$R" 'gh pr create')"; silent 40 "$d"

# 42-44 no jq and no git on PATH: a merge verb, a merge tool and a create tool are all silent.
nojq "$H1" "$W" "$(bin "$W" 'gh pr merge 12 --squash')"; silent 42
nojq "$H1" "$W" "$(tin "$W" mcp__github__merge_pull_request)"; silent 43
nojq "$H1" "$W" "$(tin "$W" mcp__gitlab__create_merge_request)"; silent 44

# 45 a read-only prepr dir: the reminder cannot be written, so the create fails open (silent), twice.
H=$(newhome h45); R=$(newrepo r45); commit "$R" src/a.ts
mkdir -p "$H/.cache/senioro-tl/prepr" && chmod 555 "$H/.cache/senioro-tl/prepr"
guard "$H" "$R" "$(bin "$R" 'gh pr create')"; silent 45
guard "$H" "$R" "$(bin "$R" 'gh pr create')"; silent "45 retry"
chmod 755 "$H/.cache/senioro-tl/prepr"

# 46 --record with a stray untracked file writes two markers; --tree names the one with the stray file;
# committing only the tracked fix (the stray file left out) -> silent.
H=$(newhome h46); R=$(newrepo r46)
echo fix >> "$R/a.txt"; echo stray > "$R/SPEC-stray.md"
d=""; rec "$H" "$R" --record "$RPT" || d+="--record exited non-zero "
full=$(cd "$R" && HOME="$H" bash "$GUARD" --tree 2>/dev/null) || d+="--tree exited non-zero "
k=0
for m in "$H/.cache/senioro-tl/prepr"/*; do
  [ -e "$m" ] || continue
  k=$((k + 1)); grep -qxF "$RPT" "$m" || d+="marker '${m##*/}' lacks the report path "
done
[ "$k" -eq 2 ] || d+="expected 2 markers, found $k "
[ -n "$full" ] && [ -f "$H/.cache/senioro-tl/prepr/$full" ] || d+="no marker named after --tree '$full' "
g "$R" add a.txt && g "$R" commit -q -m fix
[ "$(git -C "$R" rev-parse 'HEAD^{tree}')" != "$full" ] || d+="the tracked-only commit equals the full tree "
guard "$H" "$R" "$(bin "$R" 'gh pr create')"; silent 46 "$d"

# 47 --tree output equals the marker name --record writes (no untracked files: one marker), and --tree records nothing.
H=$(newhome h47); R=$(newrepo r47)
echo fix >> "$R/a.txt"
d=""; t47=$(cd "$R" && HOME="$H" bash "$GUARD" --tree 2>/dev/null) || d+="--tree exited non-zero "
[ ! -e "$H/.cache/senioro-tl/prepr" ] || d+="--tree wrote markers "
rec "$H" "$R" --record "$RPT" || d+="--record exited non-zero "
m=""; for f in "$H/.cache/senioro-tl/prepr"/*; do [ -e "$f" ] && m+="${m:+ }${f##*/}"; done
[ -n "$t47" ] && [ "$m" = "$t47" ] || d+="--tree '$t47' differs from the marker '$m' "
pass 47 "$d"

# 48 the create reason names an existing check-before-pr SKILL.md by absolute path.
H=$(newhome h48); R=$(newrepo r48); commit "$R" src/b.ts
guard "$H" "$R" "$(bin "$R" 'gh pr create')"
r=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)
f=$(printf '%s' "$r" | grep -oE '/[^ ]*/skills/check-before-pr/SKILL\.md' | head -n 1)
d=""; [ -n "$f" ] && [ -f "$f" ] || d="no existing check-before-pr/SKILL.md path in the reason: $r "
want 48 deny "never asks the user" "$d"

# 49 a merge on an unchecked code diff -> silent twice, and it writes no reminder, so a later create still gets it.
H=$(newhome h49); R=$(newrepo r49); commit "$R" src/c.ts
guard "$H" "$R" "$(bin "$R" 'gh pr merge 3')"; silent 49
guard "$H" "$R" "$(tin "$R" mcp__github__merge_pull_request)"; silent "49 tool"
d=""; [ ! -e "$H/.cache/senioro-tl/prepr" ] || d="a merge wrote markers "
denyonce "49 create" "$H" "$R" "$(bin "$R" 'gh pr create')" "$d"

# 50 one command holding a create and a merge counts as a merge: silent with a pass marker, and with no marker
# (every time, no reminder written).
guard "$H1" "$W" "$(bin "$W" 'gh pr create --fill && gh pr merge --auto')"; silent 50
H=$(newhome h50)
guard "$H" "$W" "$(bin "$W" 'gh pr create --fill && gh pr merge --auto')"; silent "50 no marker"
guard "$H" "$W" "$(bin "$W" 'gh pr create --fill; glab mr merge 3')"; silent "50 glab"
guard "$H" "$W" "$(bin "$W" 'tea pulls create && tea pulls merge 3')"; silent "50 tea"
d=""; [ ! -e "$H/.cache/senioro-tl/prepr" ] || d="a create+merge wrote markers "
pass "50 no reminder" "$d"

# 51 a create whose quoted body mentions a merge is still a create: denied once (double and single quotes).
H=$(newhome h51); R=$(newrepo r51); commit "$R" src/d.ts
denyonce 51 "$H" "$R" "$(bin "$R" 'gh pr create --body "fix; gh pr merge later"')"
H=$(newhome h51s)
denyonce "51 single" "$H" "$R" "$(bin "$R" "gh pr create --body 'a; gh pr merge 3'")"

if [ "$passed" -eq "$total" ] && [ "$total" -eq 71 ]; then
  echo "PASS $passed/$total"
else
  echo "FAIL $passed/$total"; exit 1
fi
