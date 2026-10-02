#!/usr/bin/env bash
# senioro pr-guard: a plugin-wide PreToolUse hook (hooks/hooks.json) on pull/merge request create and merge.
# Purpose: no PR is created or merged without the user's approval, and none on content the pre-PR loop
# (the check-before-pr skill) has not passed.
# Hook mode (stdin = PreToolUse input):
#   - not a PR command                                   -> no output, exit 0
#   - cannot verify (no jq or git, cwd not a git repo)   -> ask, "could not be verified (<cause>)"
#   - no marker for HEAD^{tree} in the input's cwd       -> deny: run the pre-PR loop first
#   - a pass marker                                      -> ask
#   - an override marker                                 -> ask, "user override"
# A PR command: a Bash subcommand running gh pr create|merge, glab mr create|merge, az repos pr create or
# tea pull(s) create, or an MCP tool named mcp__*__(create|merge)_(pull|merge)_request.
# Without jq it falls back to a loose raw-text match, failing toward treating the input as a PR command.
# Markers: ~/.cache/senioro-tl/prepr/<tree id>, holding the round report path (pass) or "override".
#   pr-guard.sh --record <report>  the loop's clean stop: fingerprints the working content (uncommitted
#                                  changes included) through a temporary index; the real index is untouched.
#   pr-guard.sh --override         after the user explicitly says to skip the loop: marks HEAD^{tree}.
# Both exit non-zero and record nothing when the fingerprint cannot be computed. Markers older than
# 30 days are pruned on each write. A guardrail, not a security boundary: gh api, curl and the web UI pass.
set -u

# Probe P2: set to deny if a hook "ask" does not stop the call under bypassPermissions.
ASK=ask

MARKERS="${HOME}/.cache/senioro-tl/prepr"

# esc <text>: JSON string escaping for emit when jq is absent.
esc() { local s=${1//\\/\\\\}; s=${s//\"/\\\"}; printf '%s' "$s"; }

# emit <ask|deny> <reason>: the PreToolUse decision on stdout, exit 0.
emit() {
  local d=$1 r=$2
  if [ "$d" = ask ] && [ "$ASK" = deny ]; then d=deny; r="$r. Ask the user; on yes the user runs the command"; fi
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' "$d" "$(esc "$r")"
  exit 0
}

unverified() { emit ask "Pre-PR loop could not be verified ($1). Creating or merging a pull request needs the user's approval"; }

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

# worktree_tree: the tree id of the working content (HEAD plus every change git add -A would stage),
# built in a temporary index so the real index is never touched.
worktree_tree() {
  local d t rc
  d=$(mktemp -d) || return 1
  t=$(GIT_INDEX_FILE="$d/index" git read-tree HEAD 2>/dev/null \
      && GIT_INDEX_FILE="$d/index" git add -A 2>/dev/null \
      && GIT_INDEX_FILE="$d/index" git write-tree 2>/dev/null)
  rc=$?
  rm -rf "$d"
  [ "$rc" -eq 0 ] && [ -n "$t" ] && printf '%s\n' "$t"
}

case "${1:-}" in
  --record)
    report=${2:-}
    [ -n "$report" ] || die "usage: pr-guard.sh --record <round report>"
    [ -f "$report" ] || die "round report '$report' not found"
    case "$report" in /*) ;; *) report="$PWD/$report" ;; esac
    command -v git >/dev/null 2>&1 || die "git not found"
    top=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git work tree"
    tree=$(cd "$top" && worktree_tree) || die "could not fingerprint the working content (no commit yet?)"
    mark "$tree" "$report" || die "could not write $MARKERS/$tree"
    printf 'pr-guard: pre-PR pass recorded for tree %s\n' "$tree"
    exit 0 ;;
  --override)
    command -v git >/dev/null 2>&1 || die "git not found"
    tree=$(git rev-parse --verify -q 'HEAD^{tree}' 2>/dev/null) || die "no HEAD tree here (not a git repo, or no commit yet)"
    mark "$tree" override || die "could not write $MARKERS/$tree"
    printf 'pr-guard: user override recorded for tree %s\n' "$tree"
    exit 0 ;;
  "") ;;
  *) printf 'usage: pr-guard.sh [--record <round report> | --override]  (no argument: PreToolUse hook on stdin)\n' >&2; exit 2 ;;
esac

# Hook mode. Builtins only until jq is known to exist (no cat, so it works with an empty PATH).
input=""
IFS= read -r -d '' input || true
# Cheap pre-filter: every PR command and tool name contains one of these words.
case "$input" in *create*|*merge*) ;; *) exit 0 ;; esac

S='[[:space:]]'
CORE="(gh$S+pr$S+(create|merge)|glab$S+mr$S+(create|merge)|az$S+repos$S+pr$S+create|tea$S+pulls?$S+create)([^[:alnum:]_]|\$)"
TOOL_RE='^mcp__.*__(create|merge)_(pull|merge)_request'
RAW_TOOL_RE='mcp__[^"]*__(create|merge)_(pull|merge)_request'

if ! command -v jq >/dev/null 2>&1; then
  # Raw-text fallback: any PR verb or PR tool name anywhere in the input counts.
  if [[ $input =~ $CORE ]] || [[ $input =~ $RAW_TOOL_RE ]]; then
    unverified "jq not found"
  fi
  exit 0
fi

tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
if [ "$tool" = Bash ]; then
  cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
  # A subcommand start (line start, or after ; & | ( or a newline), optional VAR=value prefixes and a path.
  NL=$'\n'
  CMD_RE="(^|[;&|(${NL}])$S*([[:alnum:]_]+=[^[:space:]]*$S+)*([^[:space:]]*/)?$CORE"
  [[ $cmd =~ $CMD_RE ]] || exit 0
elif ! [[ $tool =~ $TOOL_RE ]]; then
  exit 0
fi

command -v git >/dev/null 2>&1 || unverified "git not found"
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || unverified "no cwd in the hook input"
[ -d "$cwd" ] || unverified "cwd $cwd not found"
tree=$(git -C "$cwd" rev-parse --verify -q 'HEAD^{tree}' 2>/dev/null) || unverified "$cwd is not a git repository with a commit"
[ -n "$tree" ] || unverified "no HEAD tree in $cwd"

if [ ! -f "$MARKERS/$tree" ]; then
  emit deny "The pre-PR loop has not passed on this content (tree $tree). Run /senioro:check-before-pr first, or tell Claude explicitly to skip it."
fi
first=""
IFS= read -r first < "$MARKERS/$tree" 2>/dev/null || true
if [ "$first" = override ]; then
  emit ask "The pre-PR loop did NOT pass on this content (user override). Creating or merging a pull request needs the user's approval"
fi
emit ask "Creating or merging a pull request needs the user's approval"
