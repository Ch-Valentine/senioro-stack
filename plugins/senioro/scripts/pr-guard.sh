#!/usr/bin/env bash
# senioro pr-guard: a plugin-wide PreToolUse hook (hooks/hooks.json) on pull/merge request create.
# Purpose: a reminder, not a gate. A PR create on content the pre-PR loop (the check-before-pr skill) has not passed
# is denied once per HEAD tree. It never asks, and it never acts on a merge: merges are guarded only by the skills'
# instruction to merge only when the user asked.
# Hook mode (stdin = PreToolUse input):
#   - not a PR create, or a command that also merges     -> no output, exit 0
#   - create: a pass marker for HEAD^{tree}              -> no output (Claude Code's permission mode decides)
#   - create: no marker, the diff has code, no reminder yet for this tree
#                                                        -> write <tree>.reminded, deny once with a reason for Claude
#   - create: <tree>.reminded exists, it cannot be written, the diff has no code (none or docs) or nothing can be
#     verified (no jq or git, cwd not a git repo)        -> no output
# The diff is taken against the remote default branch (origin/HEAD, else origin/main, else origin/master). With no such
# base, no change-class.sh or any doubt, the class is code (spec 002 #6 table, #19).
# A PR create: a Bash subcommand running gh pr create, glab mr create, az repos pr create or tea pull(s) create, or an
# MCP tool named mcp__*__create_(pull|merge)_request. A Bash command that also runs gh pr merge, glab mr merge or
# tea pull(s) merge outside quotes passes silently.
# Markers: ~/.cache/senioro-tl/prepr/<tree id>, holding the round report path;
# <tree id>.reminded records that the create reminder fired for that tree.
#   pr-guard.sh --tree             prints the fingerprint of the working content (HEAD plus every change git add -A
#                                  would stage, untracked files included), built in a temporary index; the one
#                                  routine for the tree ids that name round and review reports.
#   pr-guard.sh --record <report>  the loop's clean stop: writes two markers, both holding the report path: one for
#                                  the --tree fingerprint, one for the tracked-only content (git add -u, so stray
#                                  untracked files are left out). The real index is untouched.
#                                  A leading ~/ in <report> is $HOME/.
# Both exit non-zero (and record nothing) when the fingerprint cannot be computed. Markers older than
# 30 days are pruned on each write. A guardrail, not a security boundary: gh api, curl and the web UI pass.
set -u

MARKERS="${HOME}/.cache/senioro-tl/prepr"

# HERE: this script's directory as an absolute path; the plugin root is its parent.
case "$0" in */*) HERE=${0%/*} ;; *) HERE=. ;; esac
case "$HERE" in /*) ;; *) HERE="$PWD/$HERE" ;; esac

# esc <text>: JSON string escaping for deny.
esc() { local s=${1//\\/\\\\}; s=${s//\"/\\\"}; printf '%s' "$s"; }

# deny <reason>: the PreToolUse deny on stdout, exit 0.
deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$(esc "$1")"
  exit 0
}

# base_of <dir>: sets BASE to the remote default branch of the repo in <dir> (empty when none is found).
BASE=""
base_of() {
  local d=$1 b
  BASE=$(git -C "$d" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null) || BASE=""
  [ -z "$BASE" ] || return 0
  for b in origin/main origin/master; do
    if git -C "$d" rev-parse --verify -q "$b^{commit}" >/dev/null 2>&1; then BASE=$b; return 0; fi
  done
}

# class_of <dir> <base>: none, docs or code for the diff in <dir> against <base>. Anything it cannot tell is code, so
# the deny stays the default.
class_of() {
  local d=$1 cls
  if [ -n "$2" ] && [ -f "$HERE/change-class.sh" ]; then cls=$(cd "$d" && bash "$HERE/change-class.sh" "$2" 2>/dev/null); fi
  case "${cls:-}" in none|docs) echo "$cls" ;; *) echo code ;; esac
}

# prune: drop markers older than 30 days; never fails the write that called it.
prune() { find "$MARKERS" -type f -mtime +30 -exec rm -f {} + 2>/dev/null || true; }

# mark <tree id> <content>: writes one marker atomically.
mark() {
  mkdir -p "$MARKERS" || return 1
  if ! { printf '%s\n' "$2" > "$MARKERS/.$1.$$" && mv -f "$MARKERS/.$1.$$" "$MARKERS/$1"; }; then
    rm -f "$MARKERS/.$1.$$"; return 1
  fi
  prune
}

die() { printf 'pr-guard: %s; nothing recorded\n' "$1" >&2; exit 1; }

# worktree_tree [-A|-u]: the tree id of the working content, HEAD plus every change git add -A (default: untracked
# files included) or git add -u (tracked files only) would stage, built in a temporary index so the real index is
# never touched.
worktree_tree() {
  local d t rc
  d=$(mktemp -d) || return 1
  t=$(GIT_INDEX_FILE="$d/index" git read-tree HEAD 2>/dev/null \
      && GIT_INDEX_FILE="$d/index" git add "${1:--A}" 2>/dev/null \
      && GIT_INDEX_FILE="$d/index" git write-tree 2>/dev/null)
  rc=$?
  rm -rf "$d"
  [ "$rc" -eq 0 ] && [ -n "$t" ] && printf '%s\n' "$t"
}

case "${1:-}" in
  --tree)
    command -v git >/dev/null 2>&1 || die "git not found"
    top=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git work tree"
    (cd "$top" && worktree_tree) || die "could not fingerprint the working content (no commit yet?)"
    exit 0 ;;
  --record)
    report=${2:-}
    [ -n "$report" ] || die "usage: pr-guard.sh --record <round report>"
    case "$report" in \~/*) report="$HOME/${report:2}" ;; esac
    [ -f "$report" ] || die "round report '$report' not found"
    case "$report" in /*) ;; *) report="$PWD/$report" ;; esac
    command -v git >/dev/null 2>&1 || die "git not found"
    top=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git work tree"
    tree=$(cd "$top" && worktree_tree) || die "could not fingerprint the working content (no commit yet?)"
    tracked=$(cd "$top" && worktree_tree -u) || die "could not fingerprint the tracked content"
    mark "$tree" "$report" || die "could not write $MARKERS/$tree"
    if [ "$tracked" != "$tree" ] && ! mark "$tracked" "$report"; then
      rm -f "$MARKERS/$tree"; die "could not write $MARKERS/$tracked"
    fi
    printf 'pr-guard: pre-PR pass recorded for tree %s\n' "$tree"
    [ "$tracked" = "$tree" ] || printf 'pr-guard: pre-PR pass recorded for tracked-only tree %s\n' "$tracked"
    exit 0 ;;
  "") ;;
  *) printf 'usage: pr-guard.sh [--tree | --record <round report>]  (no argument: PreToolUse hook on stdin)\n' >&2; exit 2 ;;
esac

# Hook mode. Builtins only until jq is known to exist (no cat, so it works with an empty PATH).
input=""
IFS= read -r -d '' input || true
# Cheap pre-filter: every PR create command and tool name contains this word.
case "$input" in *create*) ;; *) exit 0 ;; esac
# Nothing can be verified without jq: a create passes.
command -v jq >/dev/null 2>&1 || exit 0

S='[[:space:]]'
CORE="(gh$S+pr$S+create|glab$S+mr$S+create|az$S+repos$S+pr$S+create|tea$S+pulls?$S+create)([^[:alnum:]_]|\$)"
MERGE_CORE="(gh$S+pr$S+merge|glab$S+mr$S+merge|tea$S+pulls?$S+merge)([^[:alnum:]_]|\$)"
TOOL_RE='^mcp__.*__create_(pull|merge)_request'

tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
if [ "$tool" = Bash ]; then
  cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
  # A subcommand start (line start, or after ; & | ( or a newline), optional VAR=value prefixes and a path.
  NL=$'\n'
  START="(^|[;&|(${NL}])$S*([[:alnum:]_]+=[^[:space:]]*$S+)*([^[:space:]]*/)?"
  CMD_RE="$START$CORE"
  MERGE_RE="$START$MERGE_CORE"
  [[ $cmd =~ $CMD_RE ]] || exit 0
  # A command that also merges is a merge: the hook never acts on one. Quoted text (a PR body) is dropped first, so a
  # create whose body mentions a merge still gets the reminder.
  unq=$(printf '%s' "$cmd" | jq -Rrs --arg q "'" 'gsub("\"(\\\\.|[^\"\\\\])*\""; "") | gsub($q + "[^" + $q + "]*" + $q; "")' 2>/dev/null) || unq=$cmd
  [[ $unq =~ $MERGE_RE ]] && exit 0
elif ! [[ $tool =~ $TOOL_RE ]]; then
  exit 0
fi

# A reminder, never an ask. Anything that cannot be verified, any marker, a reminder already given, or a diff with no
# code -> silent.
command -v git >/dev/null 2>&1 || exit 0
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] && [ -d "$cwd" ] || exit 0
tree=$(git -C "$cwd" rev-parse --verify -q 'HEAD^{tree}' 2>/dev/null) || exit 0
[ -n "$tree" ] || exit 0
[ -f "$MARKERS/$tree" ] && exit 0
[ -e "$MARKERS/$tree.reminded" ] && exit 0
base_of "$cwd"
case "$(class_of "$cwd" "$BASE")" in none|docs) exit 0 ;; esac
# Fail open: if the reminder cannot be recorded, the hook must not deny again on the retry, so it stays silent.
mark "$tree.reminded" reminded 2>/dev/null || exit 0
root=$(cd "$HERE/.." 2>/dev/null && pwd) || root="$HERE/.."
deny "The pre-PR loop has not passed on this content (tree $tree). If the checks already passed in this conversation, or the user said to skip them, retry the same command now. Otherwise apply $root/skills/check-before-pr/SKILL.md to this branch, then retry. This reminder fires once per HEAD and never asks the user."
