#!/usr/bin/env bash
# G6 smoke (SPEC section 7): model runs. Prints PASS/FAIL per run; exits non-zero on any failure.
# Usage: tests/smoke.sh [--installed]
#   default      loads the plugin in place with --plugin-dir "$REPO/plugins/senioro"
#   --installed  uses the installed senioro plugin (no --plugin-dir)
# S1 hook:  /senioro:orchestrate in strict mode must deny a Bash read with the guard's text.
# S2 agent: the senioro:runner agent must be spawned and return smoke-42, which only it computes.
# Needs bash, claude, jq and uuidgen. Each run is haiku, at most 4 turns.
set -uo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)

PD=(--plugin-dir "$REPO/plugins/senioro")
case "${1:-}" in
  "") ;;
  --installed) PD=() ;;
  *) echo "usage: tests/smoke.sh [--installed]"; exit 2 ;;
esac

U=$(uuidgen | tr '[:upper:]' '[:lower:]')
[ -n "$U" ] || { echo "FAIL S1: uuidgen gave no id"; exit 1; }
W=$(mktemp -d) || { echo "FAIL: mktemp -d"; exit 1; }
trap 'rm -f "$HOME/.cache/senioro-tl/${U:?}.strict"; rm -rf "$HOME/.cache/senioro-tl/runs/${U:?}" "${W:?}"' EXIT
cd "$W" || { echo "FAIL: cd $W"; exit 1; }

rc=0

# S1 hook: strict marker for this session, then a Bash file read that the guard must deny.
# Agent/Task is disallowed so the TL cannot delegate the read to a subagent (which the guard allows).
mkdir -p "$HOME/.cache/senioro-tl" && touch "$HOME/.cache/senioro-tl/$U.strict"
out=$(claude -p ${PD[@]+"${PD[@]}"} --session-id "$U" --model haiku --max-turns 4 --output-format stream-json --verbose --allowed-tools Bash --disallowed-tools Agent Task \
  -- "/senioro:orchestrate run this exact command once, directly with your own Bash tool (no subagent): cat /etc/hosts ; then report whether it was denied" < /dev/null 2>&1)
case "$out" in
  *"strict mode: the TL does not touch the tree"*) echo "PASS S1 hook" ;;
  *) echo "FAIL S1 hook: guard deny text not in output"; printf '%s\n' "$out" | tail -n 20; rc=1 ;;
esac

# S2 agent: the plugin's runner seat is spawned under its namespaced name and answers.
# The runner must compute smoke-42 (the prompt holds only the arithmetic). smoke-42 must be in a non-error
# tool_result tied to a senioro:runner Agent call: that call's own result (sync), or a result inside the agent
# (parent_tool_use_id = the call id; async). The request, the TL's own Bash and its reply cannot pass.
# shellcheck disable=SC2016
out=$(claude -p ${PD[@]+"${PD[@]}"} --model haiku --max-turns 4 --output-format stream-json --verbose \
  -- 'Spawn the senioro:runner agent (subagent_type senioro:runner) to run this exact Bash command: echo smoke-$((6*7)) . Then reply with its output.' < /dev/null 2>&1)
res=$(printf '%s\n' "$out" | jq -Rrn '[inputs | fromjson? | objects] as $m
  | ($m[] | select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .input.subagent_type?=="senioro:runner") | .id) as $id
  | $m[] | select(.type=="user") | .parent_tool_use_id as $p | .message.content[]?
  | select(.type=="tool_result" and (.tool_use_id==$id or $p==$id) and (.is_error != true))
  | .content | if type=="string" then . else (map(.text? // "") | join("\n")) end' 2>/dev/null)
d=""
case "$out" in *'"subagent_type":"senioro:runner"'*) ;; *) d+="no subagent_type senioro:runner; " ;; esac
case "$res" in *smoke-42*) ;; *) d+="no smoke-42 in the senioro:runner result; " ;; esac
case "$out" in *"not found. Available agents"*) d+="agent not found; " ;; esac
if [ -z "$d" ]; then
  echo "PASS S2 agent"
else
  echo "FAIL S2 agent: $d"; printf '%s\n' "$out" | tail -n 20; rc=1
fi

exit "$rc"
