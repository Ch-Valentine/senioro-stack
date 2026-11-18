#!/usr/bin/env bash
# senioro pr-guard: a plugin-wide PreToolUse hook (hooks/hooks.json) on pull/merge request create and merge.
# Purpose: a reminder, not a gate. A PR create on content the pre-PR loop (the check-before-pr skill) has not passed
# is denied once per HEAD tree; a merge still needs the user's approval and a passed loop.
# Hook mode (stdin = PreToolUse input):
#   - not a PR command                                   -> no output, exit 0
#   - create: a marker (pass or override) for HEAD^{tree} -> no output (Claude Code's permission mode decides)
#   - create: no marker, the diff has code, no reminder yet for this tree
#                                                        -> write <tree>.reminded, deny once with a reason for Claude
#   - create: <tree>.reminded exists, it cannot be written, the diff has no code (none or docs) or nothing can be
#     verified (no jq or git, cwd not a git repo)        -> no output
#   - merge: cannot verify                               -> ask, "could not be verified (<cause>)"
#   - merge: no marker for HEAD^{tree} in the input's cwd -> deny: run the pre-PR loop first, unless the diff has
#                                                           no code (change-class.sh says none or docs) -> ask
#   - merge: a pass marker                               -> ask
#   - merge: an override marker                          -> ask, "user override"
# A command holding both a create and a merge counts as a merge.
# The diff is taken against the remote default branch (origin/HEAD, else origin/main, else origin/master). With no such
# base, no change-class.sh or any doubt, the class is code (spec 002 #6 table, #19).
# A PR command: a Bash subcommand running gh pr create|merge, glab mr create|merge, az repos pr create or
# tea pull(s) create, or an MCP tool named mcp__*__(create|merge)_(pull|merge)_request.
# Without jq it falls back to a loose raw-text match: a merge verb or merge tool anywhere asks; anything else passes.
# Markers: ~/.cache/senioro-tl/prepr/<tree id>, holding the round report path (pass) or "override";
# <tree id>.reminded records that the create reminder fired for that tree.
#   pr-guard.sh --tree             prints the fingerprint of the working content (HEAD plus every change git add -A
#                                  would stage, untracked files included), built in a temporary index; the one
#                                  routine for report and skip ids.
#   pr-guard.sh --record <report>  the loop's clean stop: writes two markers, both holding the report path: one for
#                                  the --tree fingerprint, one for the tracked-only content (git add -u, so stray
#                                  untracked files are left out). The real index is untouched.
#                                  A leading ~/ in <report> is $HOME/.
#   pr-guard.sh --override         after the user explicitly says to skip the loop: fingerprints the working
#                                  content as --tree does, so committing exactly it keeps the override valid.
# All three exit non-zero (and record nothing) when the fingerprint cannot be computed. Markers older than
# 30 days are pruned on each write. A guardrail, not a security boundary: gh api, curl and the web UI pass.
set -u

# Probe P2: set to deny if a hook "ask" does not stop the call under bypassPermissions.
ASK=ask

MARKERS="${HOME}/.cache/senioro-tl/prepr"

# HERE: this script's directory as an absolute path; the plugin root is its parent.
case "$0" in */*) HERE=${0%/*} ;; *) HERE=. ;; esac
case "$HERE" in /*) ;; *) HERE="$PWD/$HERE" ;; esac

# esc <text>: JSON string escaping for emit when jq is absent.
esc() { local s=${1//\\/\\\\}; s=${s//\"/\\\"}; printf '%s' "$s"; }

# emit <ask|deny> <reason>: the PreToolUse decision on stdout, exit 0.
emit() {
  local d=$1 r=$2
  if [ "$d" = ask ] && [ "$ASK" = deny ]; then d=deny; r="$r. Ask the user; on yes the user runs the command"; fi
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' "$d" "$(esc "$r")"
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
# the deny below stays the default.
class_of() {
  local d=$1 cls
  if [ -n "$2" ] && [ -f "$HERE/change-class.sh" ]; then cls=$(cd "$d" && bash "$HERE/change-class.sh" "$2" 2>/dev/null); fi
  case "${cls:-}" in none|docs) echo "$cls" ;; *) echo code ;; esac
}

# unverified <cause>: a merge asks; a create passes silently (the reminder never asks).
unverified() {
  [ "$MERGE" = 1 ] || exit 0
  emit ask "Pre-PR loop could not be verified ($1). Creating or merging a pull request needs the user's approval"
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
  --override)
    command -v git >/dev/null 2>&1 || die "git not found"
    top=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git work tree"
    tree=$(cd "$top" && worktree_tree) || die "could not fingerprint the working content (no commit yet?)"
    mark "$tree" override || die "could not write $MARKERS/$tree"
    printf 'pr-guard: user override recorded for tree %s\n' "$tree"
    exit 0 ;;
  "") ;;
  *) printf 'usage: pr-guard.sh [--tree | --record <round report> | --override]  (no argument: PreToolUse hook on stdin)\n' >&2; exit 2 ;;
esac

# Hook mode. Builtins only until jq is known to exist (no cat, so it works with an empty PATH).
input=""
IFS= read -r -d '' input || true
# Cheap pre-filter: every PR command and tool name contains one of these words.
case "$input" in *create*|*merge*) ;; *) exit 0 ;; esac

S='[[:space:]]'
CORE="(gh$S+pr$S+(create|merge)|glab$S+mr$S+(create|merge)|az$S+repos$S+pr$S+create|tea$S+pulls?$S+create)([^[:alnum:]_]|\$)"
MERGE_CORE="(gh$S+pr$S+merge|glab$S+mr$S+merge)([^[:alnum:]_]|\$)"
TOOL_RE='^mcp__.*__(create|merge)_(pull|merge)_request'
MERGE_TOOL_RE='^mcp__.*__merge_(pull|merge)_request'
RAW_MERGE_TOOL_RE='mcp__[^"]*__merge_(pull|merge)_request'
# MERGE: 1 when the input merges a PR; 0 means a create (or not a PR command at all).
MERGE=0

if ! command -v jq >/dev/null 2>&1; then
  # Raw-text fallback: a merge verb or merge tool name anywhere in the input asks; a create passes.
  if [[ $input =~ $MERGE_CORE ]] || [[ $input =~ $RAW_MERGE_TOOL_RE ]]; then
    MERGE=1; unverified "jq not found"
  fi
  exit 0
fi

tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
if [ "$tool" = Bash ]; then
  cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
  # A subcommand start (line start, or after ; & | ( or a newline), optional VAR=value prefixes and a path.
  NL=$'\n'
  START="(^|[;&|(${NL}])$S*([[:alnum:]_]+=[^[:space:]]*$S+)*([^[:space:]]*/)?"
  CMD_RE="$START$CORE"
  MERGE_RE="$START$MERGE_CORE"
  [[ $cmd =~ $CMD_RE ]] || exit 0
  [[ $cmd =~ $MERGE_RE ]] && MERGE=1
elif [[ $tool =~ $TOOL_RE ]]; then
  [[ $tool =~ $MERGE_TOOL_RE ]] && MERGE=1
else
  exit 0
fi

command -v git >/dev/null 2>&1 || unverified "git not found"
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || unverified "no cwd in the hook input"
[ -d "$cwd" ] || unverified "cwd $cwd not found"
tree=$(git -C "$cwd" rev-parse --verify -q 'HEAD^{tree}' 2>/dev/null) || unverified "$cwd is not a git repository with a commit"
[ -n "$tree" ] || unverified "no HEAD tree in $cwd"

if [ "$MERGE" = 0 ]; then
  # Create: a reminder, never an ask. Any marker, a reminder already given, or a diff with no code -> silent.
  [ -f "$MARKERS/$tree" ] && exit 0
  [ -e "$MARKERS/$tree.reminded" ] && exit 0
  base_of "$cwd"
  case "$(class_of "$cwd" "$BASE")" in none|docs) exit 0 ;; esac
  # Fail open: if the reminder cannot be recorded, the hook must not deny again on the retry, so it stays silent.
  mark "$tree.reminded" reminded 2>/dev/null || exit 0
  root=$(cd "$HERE/.." 2>/dev/null && pwd) || root="$HERE/.."
  emit deny "The pre-PR loop has not passed on this content (tree $tree). If the checks already passed in this conversation, or the user said to skip them, retry the same command now. Otherwise apply $root/skills/check-before-pr/SKILL.md to this branch, then retry. This reminder fires once per HEAD and never asks the user."
fi

# Merge: unchanged.
if [ ! -f "$MARKERS/$tree" ]; then
  base_of "$cwd"
  cls=$(class_of "$cwd" "$BASE")
  case "$cls" in
    none|docs) emit ask "The diff against $BASE has no code (class $cls), so the pre-PR loop does not apply. Creating or merging a pull request needs the user's approval" ;;
  esac
  emit deny "The pre-PR loop has not passed on this content (tree $tree). Run /senioro:check-before-pr first, or tell Claude explicitly to skip it."
fi
first=""
IFS= read -r first < "$MARKERS/$tree" 2>/dev/null || true
if [ "$first" = override ]; then
  emit ask "The pre-PR loop did NOT pass on this content (user override). Creating or merging a pull request needs the user's approval"
fi
emit ask "Creating or merging a pull request needs the user's approval"
