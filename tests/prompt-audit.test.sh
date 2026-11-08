#!/usr/bin/env bash
# prompt-audit fixtures (spec 002 U7, #30). Prints PASS n/n; exits non-zero on any failure.
# Runs plugins/senioro/scripts/prompt-audit.sh in a temp git repo with a stub `claude` first on PATH. The stub records its
# arguments and working directory and prints a canned report; no model runs and nothing leaves the machine.
set -uo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
PA="$REPO/plugins/senioro/scripts/prompt-audit.sh"
[ -f "$PA" ] || { echo "FAIL: $PA missing"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "FAIL: git missing"; exit 1; }

T=$(mktemp -d) || { echo "FAIL: mktemp -d"; exit 1; }
T=$(cd "$T" && pwd -P)
trap 'rm -rf "${T:?}"' EXIT
export HOME="$T" GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$T"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

total=0; passed=0
pass() {
  total=$((total + 1))
  if [ -z "${2:-}" ]; then passed=$((passed + 1)); else echo "FAIL case $1: $2"; fi
}

g() { local w=$1; shift; git -C "$w" -c commit.gpgsign=false "$@" >/dev/null 2>&1; }

# The stub: arguments NUL-separated to $STUB_LOG, the cwd to $STUB_LOG.cwd, a canned report on stdout.
mkdir -p "$T/bin"
cat > "$T/bin/claude" <<'EOF'
#!/bin/sh
printf '%s\0' "$@" > "$STUB_LOG"
pwd -P > "$STUB_LOG.cwd"
printf '#1 [should_fix] [G2] skills/x/SKILL.md:3 — stub finding — stub fix\n'
exit "${STUB_RC:-0}"
EOF
chmod +x "$T/bin/claude"

# newrepo <name>: a repo with a base commit holding .gitkeep; prints its path.
newrepo() {
  local w="$T/$1"
  mkdir -p "$w" && g "$w" init -q && : > "$w/.gitkeep" && g "$w" add -A && g "$w" commit -q -m base && echo "$w"
}
put() {
  local w=$1 f; shift
  for f in "$@"; do mkdir -p "$w/$(dirname "$f")" && echo "$f" > "$w/$f"; done
}

# run <repo-dir> <args...>: runs the script from that dir with the stub first on PATH; sets RC and ERR.
run() {
  local w=$1; shift
  rm -f "$STUB_LOG" "$STUB_LOG.cwd"
  ERR=$(cd "$w" && PATH="$T/bin:$PATH" bash "$PA" "$@" 2>&1 >/dev/null); RC=$?
}
export STUB_LOG="$T/stub.args"

# args: loads the stub's argument list into ARGS.
ARGS=()
args() {
  ARGS=()
  [ -f "$STUB_LOG" ] || return 1
  while IFS= read -r -d '' a; do ARGS+=("$a"); done < "$STUB_LOG"
}
# has <flag> <value>: the flag is followed by that value.
has() {
  local i
  for ((i = 0; i < ${#ARGS[@]} - 1; i++)); do [ "${ARGS[$i]}" = "$1" ] && [ "${ARGS[$i + 1]}" = "$2" ] && return 0; done
  return 1
}
# hasarg <value>: some argument is exactly that.
hasarg() { local a; for a in "${ARGS[@]}"; do [ "$a" = "$1" ] && return 0; done; return 1; }

# Case 1: the call. Prompt paths and others changed; only the prompt paths reach the child.
R=$(newrepo r1); put "$R" skills/x/SKILL.md .claude/rules/r.md .claude-plugin/plugin.json src/a.ts README.md
mkdir -p "$T/out"
run "$R/src" HEAD "$T/out/audit.md" sonnet
d=""
[ "$RC" -eq 0 ] || d+="exit $RC: $ERR "
args || d+="the stub was not called "
hasarg -p || d+="no -p "
hasarg "/claude-api prompt-audit .claude/rules/r.md skills/x/SKILL.md" || d+="no '/claude-api prompt-audit <prompt paths>' argument: ${ARGS[*]} "
has --model sonnet || d+="no --model sonnet "
has --permission-mode dontAsk || d+="no --permission-mode dontAsk "
has --tools "Read,Grep,Glob,Bash" || d+="no --tools Read,Grep,Glob,Bash "
for t in Read Grep Glob "Bash(git diff *)" "Bash(git log *)" "Bash(git show *)"; do hasarg "$t" || d+="--allowed-tools lacks '$t' "; done
for a in "${ARGS[@]}"; do
  case "$a" in *src/a.ts*|*README.md*|*plugin.json*) d+="a non-prompt path reached the child: $a " ;; esac
done
pass 1 "$d"

# Case 2: no Edit or Write tool anywhere in the arguments; Bash is limited to git commands.
d=""
for a in "${ARGS[@]}"; do
  case "$a" in *Edit*|*Write*) d+="write-capable tool in: $a " ;; esac
done
for a in "${ARGS[@]}"; do
  case "$a" in "Bash("*) case "$a" in "Bash(git "*) ;; *) d+="non-git Bash rule: $a " ;; esac ;; esac
done
pass 2 "$d"

# Case 3: the child runs from the repo root, even when the script was started in a subdirectory.
d=""
[ "$(cat "$STUB_LOG.cwd" 2>/dev/null)" = "$R" ] || d+="cwd '$(cat "$STUB_LOG.cwd" 2>/dev/null)', expected '$R' "
pass 3 "$d"

# Case 4: the child's stdout is the report.
d=""
[ "$(cat "$T/out/audit.md" 2>/dev/null)" = "#1 [should_fix] [G2] skills/x/SKILL.md:3 — stub finding — stub fix" ] || d+="report holds '$(cat "$T/out/audit.md" 2>/dev/null)' "
pass 4 "$d"

# Case 5: the note names the non-interactive run, the output format, and applies nothing.
d=""
note=""
for ((i = 0; i < ${#ARGS[@]} - 1; i++)); do [ "${ARGS[$i]}" = --append-system-prompt ] && note=${ARGS[$i + 1]}; done
for w in "Non-interactive" "frontmatter" "Route the seat" "#N [must_fix|should_fix|consider] [DIM] file:line" "High is must_fix" "unified diff" "Apply nothing"; do
  case "$note" in *"$w"*) ;; *) d+="note lacks '$w' " ;; esac
done
pass 5 "$d"

# Case 6: a docs-only diff has no prompt paths: no call, a one-line report, exit 0.
R=$(newrepo r6); put "$R" README.md notes.md
run "$R" HEAD "$T/out/none.md" sonnet
d=""
[ "$RC" -eq 0 ] || d+="exit $RC: $ERR "
[ ! -f "$STUB_LOG" ] || d+="claude was called "
grep -q 'No prompt paths' "$T/out/none.md" 2>/dev/null || d+="report lacks 'No prompt paths': $(cat "$T/out/none.md" 2>/dev/null) "
pass 6 "$d"

# Case 7: the child's failure is the script's failure; the report keeps what was printed.
R=$(newrepo r7); put "$R" skills/x/SKILL.md
STUB_RC=3 run "$R" HEAD "$T/out/fail.md" sonnet
d=""
[ "$RC" -eq 3 ] || d+="exit $RC, expected 3 "
case "$ERR" in *"claude exited 3"*) ;; *) d+="stderr lacks 'claude exited 3': $ERR " ;; esac
[ -s "$T/out/fail.md" ] || d+="report is empty "
pass 7 "$d"

# Case 8: a path with white space is quoted in the request.
R=$(newrepo r8); put "$R" ".claude/rules/my rule.md"
run "$R" HEAD "$T/out/space.md" sonnet
d=""
args || d+="the stub was not called "
hasarg '/claude-api prompt-audit ".claude/rules/my rule.md"' || d+="path not quoted: ${ARGS[*]} "
pass 8 "$d"

# Case 9: a relative report path is relative to the caller's directory, and its directory is created.
R=$(newrepo r9); put "$R" AGENTS.md
run "$R" HEAD reports/sub/audit.md sonnet
d=""
[ "$RC" -eq 0 ] || d+="exit $RC: $ERR "
[ -s "$R/reports/sub/audit.md" ] || d+="no report at the relative path "
pass 9 "$d"

# Case 10: usage errors exit 2 and call nothing; outside a repo exits 1.
R=$(newrepo r10)
d=""
for set in "" "HEAD" "HEAD $T/out/x.md" "HEAD $T/out/x.md sonnet extra"; do
  # shellcheck disable=SC2086
  run "$R" $set
  [ "$RC" -eq 2 ] || d+="args '$set' exit $RC, expected 2 "
done
[ ! -f "$STUB_LOG" ] || d+="claude was called on a usage error "
mkdir -p "$T/norepo"
run "$T/norepo" HEAD "$T/out/n.md" sonnet
[ "$RC" -eq 1 ] || d+="outside a repo exit $RC, expected 1 "
pass 10 "$d"

# Case 11: a report path that starts with ~/ is under $HOME (the caller quoted it, so the shell did not expand it); no ~ directory in the repo.
R=$(newrepo r11); put "$R" AGENTS.md
run "$R" HEAD \~/out/tilde/audit.md sonnet
d=""
[ "$RC" -eq 0 ] || d+="exit $RC: $ERR "
[ -s "$HOME/out/tilde/audit.md" ] || d+="no report at \$HOME/out/tilde/audit.md "
[ ! -e "$R/~" ] || d+="a ~ directory was created in the repo "
pass 11 "$d"

if [ "$passed" -eq "$total" ] && [ "$total" -eq 11 ]; then
  echo "PASS $passed/$total"
else
  echo "FAIL $passed/$total"; exit 1
fi
