#!/usr/bin/env bash
# senioro change-class: classifies a diff so the pre-PR loop and the PR hook run only the checks it needs
# (spec 002 #6 table, #19).
# Usage: change-class.sh [--prompts] [<base>]
#   The diff is the files changed since <base> (working tree included) plus untracked files that are not ignored.
#   <base> is a ref or sha; the diff starts at its merge base with HEAD, or at <base> itself when HEAD is an ancestor
#   of it (a `git stash create` snapshot, #16). Without <base>, HEAD: the uncommitted changes and untracked files.
#   (no flag)  prints none (empty diff), docs or code.
#   --prompts  prints the changed prompt paths instead, one per line, sorted.
# docs = every changed path is *.md|mdx|rst|png|jpg|jpeg|gif|svg|webp or LICENSE or LICENSE.*, and none is a prompt
# path. Anything else is code, including *.txt and a type it does not know. Prompt paths:
#   .claude/{skills,agents,commands,rules}/**; the skills/, agents/, commands/ and hooks/ dirs of a plugin root (a dir
#   that holds .claude-plugin/plugin.json or a skills/*/SKILL.md, in the work tree, at HEAD or at the base);
#   CLAUDE.md, CLAUDE.local.md and AGENTS.md at any depth.
# When git, the work tree, HEAD or the base cannot be resolved the class is code (unknown is code) and the cause goes
# to stderr; with --prompts nothing is listed and the exit code is 1. Exit 0 otherwise; 2 on a usage error.
set -u

usage() { echo "usage: change-class.sh [--prompts] [<base>]" >&2; exit 2; }

prompts=0
base=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --prompts) prompts=1 ;;
    -*) usage ;;
    *) [ -z "$base" ] || usage; base=$1 ;;
  esac
  shift
done

# unknown <cause>: the class is code; no prompt list.
unknown() {
  printf 'change-class: %s\n' "$1" >&2
  [ "$prompts" -eq 0 ] || exit 1
  echo code
  exit 0
}

command -v git >/dev/null 2>&1 || unknown "git not found"
top=$(git rev-parse --show-toplevel 2>/dev/null) || unknown "not inside a git work tree"
cd "$top" || unknown "cannot enter $top"
head=$(git rev-parse --verify -q 'HEAD^{commit}') || unknown "no commit yet"
base=${base:-HEAD}
bc=$(git rev-parse --verify -q "$base^{commit}") || unknown "base '$base' is not a commit"
if git merge-base --is-ancestor "$head" "$bc" 2>/dev/null; then
  from=$bc
else
  from=$(git merge-base "$bc" "$head" 2>/dev/null) || unknown "no merge base between '$base' and HEAD"
fi

G=(git -c core.quotepath=off)
changed=$("${G[@]}" diff --name-only --no-renames "$from" -- 2>/dev/null) || unknown "git diff failed"
untracked=$("${G[@]}" ls-files --others --exclude-standard 2>/dev/null) || unknown "git ls-files failed"
changed=$(printf '%s\n%s\n' "$changed" "$untracked" | sed '/^$/d' | sort -u)
if [ -z "$changed" ]; then
  [ "$prompts" -eq 1 ] || echo none
  exit 0
fi
known=$("${G[@]}" ls-tree -r --name-only "$from" 2>/dev/null) || unknown "git ls-tree failed"

# One stream: "K <path>" lines (every path that exists in the work tree, at HEAD or at the base), then "C <path>"
# lines (the changed paths). The first awk line of output is the class, the rest are the prompt paths.
out=$({
  printf '%s\n' "$known" | sed '/^$/d; s/^/K /'
  "${G[@]}" ls-files 2>/dev/null | sed '/^$/d; s/^/K /'
  printf '%s\n' "$untracked" | sed '/^$/d; s/^/K /'
  printf '%s\n' "$changed" | sed 's/^/C /'
} | awk '
  function addroot(r) { proot[r] = 1 }
  function isprompt(p,   n, c, i, j, root) {
    if (p ~ /(^|\/)\.claude\/(skills|agents|commands|rules)\//) return 1
    if (p ~ /(^|\/)(CLAUDE|CLAUDE\.local|AGENTS)\.md$/) return 1
    n = split(p, c, "/")
    for (i = 1; i < n; i++) {
      if (c[i] == "skills" || c[i] == "agents" || c[i] == "commands" || c[i] == "hooks") {
        root = ""
        for (j = 1; j < i; j++) root = root (j > 1 ? "/" : "") c[j]
        if (root in proot) return 1
      }
    }
    return 0
  }
  function isdocs(p,   b, e) {
    b = p; sub(/^.*\//, "", b)
    if (b ~ /^LICENSE(\..*)?$/) return 1
    if (b !~ /\./) return 0
    e = tolower(b); sub(/^.*\./, "", e)
    return (e == "md" || e == "mdx" || e == "rst" || e == "png" || e == "jpg" || e == "jpeg" || e == "gif" || e == "svg" || e == "webp")
  }
  /^K / {
    p = substr($0, 3)
    if (match(p, /(^|\/)\.claude-plugin\/plugin\.json$/)) addroot(substr(p, 1, RSTART - 1))
    if (match(p, /(^|\/)skills\/[^\/]+\/SKILL\.md$/)) addroot(substr(p, 1, RSTART - 1))
    next
  }
  /^C / {
    p = substr($0, 3); total++
    if (isprompt(p)) { code = 1; np++; plist[np] = p }
    else if (!isdocs(p)) code = 1
  }
  END {
    print (total == 0 ? "none" : (code ? "code" : "docs"))
    for (i = 1; i <= np; i++) print plist[i]
  }') || unknown "classifier failed"

if [ "$prompts" -eq 1 ]; then
  printf '%s\n' "$out" | sed '1d'
else
  printf '%s\n' "$out" | sed -n '1p'
fi
