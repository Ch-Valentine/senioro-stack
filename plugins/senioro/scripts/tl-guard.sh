#!/usr/bin/env bash
# senioro:orchestrate strict-mode guard — a PreToolUse hook registered by the senioro:orchestrate skill.
# Purpose: the Tech Lead (main session) never touches the tree; seats do.
# No repo path is TL-owned: specs, plans, and roadmaps are edited in place by seats, never copied.
# Behaviour: FAIL-OPEN on any doubt (missing jq, malformed input, no session id).
#   - tool calls made inside a subagent carry `agent_id`  -> always allowed
#   - no marker file for this session                      -> TL mode not armed, allowed
#   - Read/Edit/Write/MultiEdit/NotebookEdit/Grep/Glob on TL paths -> allowed
#     (~/.cache/senioro-tl/ — run dirs and markers —, memory dirs, the session scratchpad, MEMORY.md)
#   - Bash whose leading command reads or copies files (cat/sed/head/tail/less/more/bat/grep/rg/awk/ugrep/cp/mv/tee)
#     and does not target a TL path                        -> denied
#   - everything else                                      -> denied with a reason that names the seat to delegate to
set -u
command -v jq >/dev/null 2>&1 || exit 0
input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || exit 0
agent_id="$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null || true)"
[ -n "$agent_id" ] && exit 0
session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
[ -n "$session_id" ] || exit 0
marker="${HOME}/.cache/senioro-tl/${session_id}.strict"
[ -f "$marker" ] || exit 0
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)"
target=""
case "$tool" in
  Read|Edit|Write|MultiEdit|NotebookEdit|Grep|Glob)
    target="$(printf '%s' "$input" | jq -r '.tool_input | (.file_path // .path // .notebook_path // "")' 2>/dev/null || true)"
    ;;
  Bash)
    cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
    # strip a leading `cd X &&` / `cd X;` so the real first command is judged
    stripped="$(printf '%s' "$cmd" | sed -E 's/^[[:space:]]*cd[[:space:]]+[^;&|]*([;&|]+[[:space:]]*)?//')"
    first="$(printf '%s' "$stripped" | awk '{print $1}')"
    case "$first" in
      cat|sed|head|tail|less|more|bat|grep|rg|awk|ugrep|cp|mv|tee) target="$cmd" ;;
      *) exit 0 ;;
    esac
    ;;
  *) exit 0 ;;
esac
# TL paths are exempt; no repo path is
allow_re='/\.cache/senioro-tl/|/\.claude/projects/[^/]+/memory/|/scratchpad(/|$)|MEMORY\.md'
if [[ "$target" =~ $allow_re ]]; then exit 0; fi
reason="senioro:orchestrate strict mode: the TL does not touch the tree. Delegate this ${tool} to a seat (senioro:runner: lookups and commands; senioro:verifier: evidence checks; senioro:investigator: research and diagnosis; senioro:architect: design; senioro:implementer: changes) and work from its report. No repo path is TL-owned: artifacts are edited in place by seats, never copied. TL paths: ~/.cache/senioro-tl/runs/<session>/, memory dirs, the scratchpad. Leave TL mode only on the user's explicit request: rm ${marker}. If you are a SUBAGENT reading this, stop and report 'tl-guard misfire: no agent_id in hook input' to the TL verbatim."
jq -cn --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
printf '%s\n' "$reason" >&2
exit 2
