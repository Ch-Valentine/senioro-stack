#!/usr/bin/env bash
# change-class fixtures (spec 002 U7, #6 table, #19). Prints PASS n/n; exits non-zero on any failure.
# Runs plugins/senioro/scripts/change-class.sh in temp git repos: each case lists files, then checks the class and the
# --prompts list. No network, no model.
set -uo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
CC="$REPO/plugins/senioro/scripts/change-class.sh"
[ -f "$CC" ] || { echo "FAIL: $CC missing"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "FAIL: git missing"; exit 1; }

T=$(mktemp -d) || { echo "FAIL: mktemp -d"; exit 1; }
T=$(cd "$T" && pwd -P)
trap 'rm -rf "${T:?}"' EXIT
# Fixture repos see no user or system git config, and git discovery stops at $T.
export HOME="$T" GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$T"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

total=0; passed=0

# g <repo> <git args>: quiet git in a fixture repo.
g() { local w=$1; shift; git -C "$w" -c commit.gpgsign=false "$@" >/dev/null 2>&1; }

# newrepo <name>: a repo whose one commit holds .gitkeep; prints its path.
newrepo() {
  local w="$T/$1"
  mkdir -p "$w" && g "$w" init -q && : > "$w/.gitkeep" && g "$w" add -A && g "$w" commit -q -m base && echo "$w"
}

# put <repo> <path>...: creates the files (with parents) untracked.
put() {
  local w=$1 f; shift
  for f in "$@"; do mkdir -p "$w/$(dirname "$f")" && echo "$f" > "$w/$f"; done
}

# pass <case> [failure detail]: counts the case; an empty detail is a pass.
pass() {
  total=$((total + 1))
  if [ -z "${2:-}" ]; then passed=$((passed + 1)); else echo "FAIL case $1: $2"; fi
}

# check <case> <repo> <class> <prompts, newline separated> [base]: runs the script in the repo.
check() {
  local n=$1 w=$2 want=$3 wantp=$4 b=${5:-} d="" got gotp
  got=$(cd "$w" && bash "$CC" ${b:+"$b"} 2>/dev/null) || d+="exit $? "
  gotp=$(cd "$w" && bash "$CC" --prompts ${b:+"$b"} 2>/dev/null) || d+="--prompts exit $? "
  [ "$got" = "$want" ] || d+="class '$got', expected '$want' "
  [ "$gotp" = "$wantp" ] || d+="prompts '$(printf '%s' "$gotp" | tr '\n' ' ')', expected '$(printf '%s' "$wantp" | tr '\n' ' ')' "
  pass "$n" "$d"
}

# One case per fixture: an untracked file set against the base commit.
R=$(newrepo c1); put "$R" README.md LICENSE a.png
check "1 README, LICENSE, png are docs" "$R" docs ""

R=$(newrepo c2); put "$R" .claude/skills/x/SKILL.md
check "2 .claude/skills is a prompt path" "$R" code ".claude/skills/x/SKILL.md"

R=$(newrepo c3); put "$R" .claude/rules/r.md
check "3 .claude/rules is a prompt path" "$R" code ".claude/rules/r.md"

R=$(newrepo c4); put "$R" docs/CLAUDE.md
check "4 CLAUDE.md at depth is a prompt path" "$R" code "docs/CLAUDE.md"

R=$(newrepo c5); put "$R" skills/x/SKILL.md .claude-plugin/plugin.json
check "5 skills/ beside a manifest" "$R" code "skills/x/SKILL.md"

R=$(newrepo c6); put "$R" agents/a.md skills/y/SKILL.md
check "6 agents/ beside a skills/*/SKILL.md, no manifest" "$R" code "agents/a.md
skills/y/SKILL.md"

R=$(newrepo c7); put "$R" agents/a.md
check "7 agents/ alone is not a plugin root" "$R" docs ""

R=$(newrepo c8); put "$R" src/hooks/useX.ts
check "8 src/hooks/useX.ts is code, not a prompt path" "$R" code ""

R=$(newrepo c9); put "$R" README.md src/a.ts
check "9 README.md + src/a.ts" "$R" code ""

for f in requirements.txt CMakeLists.txt a.unknown Makefile LICENSE-MIT; do
  R=$(newrepo "c10-$f"); put "$R" "$f"
  check "10 $f is code" "$R" code ""
done

R=$(newrepo c11)
check "11 empty diff" "$R" none ""

R=$(newrepo c12); put "$R" a.mdx b.rst c.jpg d.jpeg e.gif f.svg g.webp LICENSE.txt docs/guide.MD
check "12 every docs type, LICENSE.*, upper-case extension" "$R" docs ""

R=$(newrepo c13); put "$R" AGENTS.md CLAUDE.local.md
check "13 AGENTS.md and CLAUDE.local.md" "$R" code "AGENTS.md
CLAUDE.local.md"

# Committed work: the base is the first commit.
R=$(newrepo c14); B=$(git -C "$R" rev-parse HEAD)
put "$R" notes.md; g "$R" add -A; g "$R" commit -q -m docs
check "14 a docs commit since the base" "$R" docs "" "$B"
check "14b the same without a base is empty (HEAD)" "$R" none ""
put "$R" src/b.go
check "14c a code file added on top" "$R" code "" "$B"

# A modified tracked file and a deleted prompt file (the plugin root is known from the base tree).
R=$(newrepo c15); put "$R" .claude-plugin/plugin.json skills/x/SKILL.md README.md
g "$R" add -A; g "$R" commit -q -m plugin; B=$(git -C "$R" rev-parse HEAD)
echo more >> "$R/README.md"
check "15 a modified README is docs" "$R" docs "" "$B"
rm "$R/skills/x/SKILL.md"
check "15b a deleted skill is a prompt path" "$R" code "skills/x/SKILL.md" "$B"
git -C "$R" checkout -q -- skills/x/SKILL.md; put "$R" hooks/hooks.json
check "15c a plugin root's hooks/ dir" "$R" code "hooks/hooks.json" "$B"

# Plugin root in a subdirectory: hooks/ there is a prompt path, in a sibling dir it is not.
R=$(newrepo c16); put "$R" plugins/p/.claude-plugin/plugin.json; g "$R" add -A; g "$R" commit -q -m p
put "$R" plugins/p/hooks/hooks.json plugins/q/hooks/hooks.json
check "16 hooks/ under a nested plugin root only" "$R" code "plugins/p/hooks/hooks.json"

# A rename out of code into docs keeps both paths, so it is code.
R=$(newrepo c17); put "$R" src/a.ts; g "$R" add -A; g "$R" commit -q -m ts
mkdir -p "$R/docs" && mv "$R/src/a.ts" "$R/docs/a.md"
check "17 a rename from .ts to .md is code" "$R" code ""

# The merge base: main moves on with code, the branch adds docs; the branch diff is docs.
R=$(newrepo c18); g "$R" branch -M main; g "$R" checkout -q -b feat
put "$R" notes.md; g "$R" add -A; g "$R" commit -q -m docs
g "$R" checkout -q main; put "$R" src/main.ts; g "$R" add -A; g "$R" commit -q -m code
g "$R" checkout -q feat
check "18 the diff starts at the merge base" "$R" docs "" main

# A `git stash create` snapshot as the base (#16): only what changed since the snapshot counts.
R=$(newrepo c19); put "$R" src/a.ts README.md; g "$R" add -A; g "$R" commit -q -m files
echo edit >> "$R/src/a.ts"
S=$(git -C "$R" stash create)
echo edit >> "$R/README.md"
check "19 since a snapshot: README only" "$R" docs "" "$S"
check "19b since HEAD: code" "$R" code ""

# Mixed prompt list: sorted, only prompt paths.
R=$(newrepo c20); put "$R" src/a.ts z/CLAUDE.md .claude/agents/b.md README.md
check "20 sorted prompt list without other paths" "$R" code ".claude/agents/b.md
z/CLAUDE.md"

# Failures are code; --prompts lists nothing and exits 1.
mkdir -p "$T/norepo"
d=""
got=$(cd "$T/norepo" && bash "$CC" 2>/dev/null); rc=$?
[ "$got" = code ] && [ "$rc" -eq 0 ] || d+="outside a repo: '$got' exit $rc "
got=$(cd "$T/norepo" && bash "$CC" --prompts 2>/dev/null); rc=$?
[ -z "$got" ] && [ "$rc" -eq 1 ] || d+="--prompts outside a repo: '$got' exit $rc "
R=$(newrepo c21)
got=$(cd "$R" && bash "$CC" no-such-ref 2>/dev/null); rc=$?
[ "$got" = code ] && [ "$rc" -eq 0 ] || d+="bad base: '$got' exit $rc "
mkdir -p "$T/nocommit" && g "$T/nocommit" init -q && put "$T/nocommit" README.md
got=$(cd "$T/nocommit" && bash "$CC" 2>/dev/null); rc=$?
[ "$got" = code ] && [ "$rc" -eq 0 ] || d+="no commit yet: '$got' exit $rc "
pass 21 "$d"

d=""
(cd "$R" && bash "$CC" --bogus >/dev/null 2>&1); rc=$?
[ "$rc" -eq 2 ] || d+="--bogus exit $rc, expected 2 "
(cd "$R" && bash "$CC" a b >/dev/null 2>&1); rc=$?
[ "$rc" -eq 2 ] || d+="two bases exit $rc, expected 2 "
pass 22 "$d"

# A subdirectory is the same repo: paths are repo-relative whatever the cwd.
R=$(newrepo c23); put "$R" src/a.ts skills/x/SKILL.md
d=""
got=$(cd "$R/src" && bash "$CC" --prompts 2>/dev/null)
[ "$got" = "skills/x/SKILL.md" ] || d+="from a subdir: '$got' "
pass 23 "$d"

if [ "$passed" -eq "$total" ] && [ "$total" -eq 32 ]; then
  echo "PASS $passed/$total"
else
  echo "FAIL $passed/$total"; exit 1
fi
