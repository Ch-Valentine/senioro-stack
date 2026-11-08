#!/usr/bin/env bash
# G6 smoke (SPEC section 7): model runs. Prints PASS/FAIL per run; exits non-zero on any failure.
# Usage: tests/smoke.sh [hook|wallet|effort|audit] [--installed]
#   default      loads the plugin in place with --plugin-dir "$REPO/plugins/senioro"
#   --installed  uses the installed senioro plugin (no --plugin-dir)
#   hook         runs only the PR-hook probes P1 to P3 (by hand, spec 002 U1, U7) instead of S1 and S2
#   wallet       runs only W1 and W2 (by hand, spec 002 U3, Done-when 2)
#   effort       runs only E1 (by hand, spec 002 U3, needs Claude Code 2.1.292 or later)
#   audit        runs only A1 (by hand, spec 002 U7; run it from a runner seat, so the audit child is nested)
# S1 hook:  /senioro:orchestrate in strict mode must deny a Bash read with the guard's text.
# S2 agent: the senioro:runner agent must be spawned and return smoke-42, which only it computes.
# P1 hook loaded: under bypassPermissions, `gh pr create` (a stub gh) on a tree with no pre-PR marker must be
#    denied by pr-guard.sh, which proves hooks/hooks.json loads by convention (F21).
# P2 ask: with an override marker the hook answers "ask"; the stub gh must not run, else set ASK=deny in
#    scripts/pr-guard.sh (F21).
# P3 docs-only: with no marker, a diff with no code against the remote default branch must get "ask" instead of the
#    deny of P1: the stub gh must not run and the result must not carry the deny text (spec 002 U7, #6 table).
# W1 wallet: a haiku /senioro:orchestrate session with wallet=ramen is told to spawn a runner, a verifier and an
#    implementer (no model named); the result's model usage must list haiku and sonnet only. The implementer's
#    definition is opus, so an omitted or wrong `model` shows as opus.
# W2 control: the same with wallet=omakase-bro must list haiku (the session), opus and sonnet, with the runner spawned
#    on sonnet and the verifier and implementer on opus; ramen and an unset wallet give the same models on this task,
#    so only W2 shows the option is read.
# E1 effort: six one-spawn runs of one fixed verifier task, three with a per-spawn effort of low, three with max.
#    Pass = every max run's output plus thinking tokens (U2's request counting) exceed every low run's, and every
#    run's spawn carried the effort asked for. The effort itself is invisible in the stream (F10), so the tokens
#    are the only evidence.
# A1 audit: scripts/prompt-audit.sh on a throwaway plugin repo whose branch plants one dated pattern (a retired
#    model name under all-caps pressure language) in one skill file. Pass = exit 0, the report cites that line, git status and
#    the diff are unchanged afterwards, and the call ends within 600 s. The model is $AUDIT_MODEL (default sonnet).
#    On a fail: retry in another session with `/doctor prompt-audit <path>`, then use the spec's fallback (#30): the
#    pre-PR step asks the user to run the audit elsewhere or skip it.
# Needs bash, claude, jq, git and uuidgen. S1, S2 and the hook probes run haiku, at most 4 turns; A1 runs $AUDIT_MODEL. The probes never
# call a real gh: a stub gh comes first on PATH. W1 and E1 also spawn sonnet seats and cost a few cents each.
set -uo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)

PD=(--plugin-dir "$REPO/plugins/senioro")
HOOK=0
WALLET=0
EFFORT=0
AUDIT=0
for a in "$@"; do
  case "$a" in
    hook) HOOK=1 ;;
    wallet) WALLET=1 ;;
    effort) EFFORT=1 ;;
    audit) AUDIT=1 ;;
    --installed) PD=() ;;
    *) echo "usage: tests/smoke.sh [hook|wallet|effort|audit] [--installed]"; exit 2 ;;
  esac
done
[ $((HOOK + WALLET + EFFORT + AUDIT)) -le 1 ] || { echo "usage: tests/smoke.sh [hook|wallet|effort|audit] [--installed]"; exit 2; }

U=$(uuidgen | tr '[:upper:]' '[:lower:]')
[ -n "$U" ] || { echo "FAIL S1: uuidgen gave no id"; exit 1; }
W=$(mktemp -d) || { echo "FAIL: mktemp -d"; exit 1; }
TREE=""
SESS=()
# cleanup: the strict marker and run dir of S1, the hook probes' marker, the temp dir, and the transcripts W1 and E1 made.
# shellcheck disable=SC2329
cleanup() {
  local s
  rm -f "$HOME/.cache/senioro-tl/${U:?}.strict"
  [ -z "$TREE" ] || rm -f "$HOME/.cache/senioro-tl/prepr/$TREE"
  rm -rf "$HOME/.cache/senioro-tl/runs/${U:?}" "${W:?}"
  for s in ${SESS[@]+"${SESS[@]}"}; do
    rm -rf "${s:?}" "${s%.jsonl}"
    rmdir "$(dirname "$s")" 2>/dev/null
  done
}
trap cleanup EXIT
cd "$W" || { echo "FAIL: cd $W"; exit 1; }

rc=0

# hook_probe: one haiku run, in the probe repo, asking for `gh pr create` through Bash under
# bypassPermissions. Sets HP_OUT (stream) and HP_RES ("<is_error> <text>" of that Bash call's result, if any).
hook_probe() {
  HP_OUT=$(cd "$W/repo" && PATH="$W/bin:$PATH" claude -p ${PD[@]+"${PD[@]}"} --model haiku --max-turns 4 --permission-mode bypassPermissions --allowed-tools Bash --disallowed-tools Agent Task --output-format stream-json --verbose \
    -- "Run this exact command once with your Bash tool, then report its output or the reason it did not run: gh pr create --title smoke --body smoke" < /dev/null 2>&1)
  HP_RES=$(printf '%s\n' "$HP_OUT" | jq -Rrn '[inputs | fromjson? | objects] as $m
    | ($m[] | select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="Bash" and ((.input.command // "") | test("gh pr create"))) | .id) as $id
    | $m[] | select(.type=="user") | .message.content[]? | select(.type=="tool_result" and .tool_use_id==$id)
    | ((.is_error // false | tostring) + " " + (.content | if type=="string" then . else (map(.text? // "") | join("\n")) end))' 2>/dev/null)
}

if [ "$HOOK" -eq 1 ]; then
  # A throwaway repo whose tree is unique (a uuid file), a stub gh, and the marker cleanup in the trap.
  mkdir -p "$W/repo" "$W/bin" || { echo "FAIL P1: mkdir"; exit 1; }
  printf '#!/bin/sh\necho smoke-gh-ran\n' > "$W/bin/gh" && chmod +x "$W/bin/gh"
  { cd "$W/repo" && git init -q && printf '%s\n' "$U" > id.txt && git add id.txt \
    && git -c user.name=smoke -c user.email=smoke@example.com commit -q -m smoke; } || { echo "FAIL P1: could not make the probe repo"; exit 1; }
  TREE=$(git -C "$W/repo" rev-parse 'HEAD^{tree}') || { echo "FAIL P1: no HEAD tree"; exit 1; }
  rm -f "$HOME/.cache/senioro-tl/prepr/$TREE"

  # P1: no marker for this tree, so the hook must deny; a stub gh that ran means the hook did not load.
  hook_probe
  case "$HP_RES" in
    *smoke-gh-ran*) echo "FAIL P1 hook loaded: the stub gh ran, the hook did not stop it (hooks/hooks.json not loaded?)"; printf '%s\n' "$HP_OUT" | tail -n 20; rc=1 ;;
    *"pre-PR loop has not passed"*) echo "PASS P1 hook loaded: pr-guard denied gh pr create under bypassPermissions" ;;
    *) echo "FAIL P1 hook loaded: no pr-guard deny text in the gh pr create result"; printf '%s\n' "$HP_OUT" | tail -n 20; rc=1 ;;
  esac

  # P2: an override marker makes the hook answer "ask"; the call must still not run under bypassPermissions.
  if (cd "$W/repo" && bash "$REPO/plugins/senioro/scripts/pr-guard.sh" --override >/dev/null); then
    hook_probe
    case "$HP_RES" in
      *smoke-gh-ran*) echo "FAIL P2 ask: ask does NOT stop gh pr create under bypassPermissions; set ASK=deny in plugins/senioro/scripts/pr-guard.sh (F21)"; rc=1 ;;
      "") echo "FAIL P2 ask: no gh pr create result in the output"; printf '%s\n' "$HP_OUT" | tail -n 20; rc=1 ;;
      *) echo "PASS P2 ask: ask stopped gh pr create under bypassPermissions ($(printf '%s' "$HP_RES" | head -c 120))" ;;
    esac
  else
    echo "FAIL P2 ask: pr-guard.sh --override failed"; rc=1
  fi

  # P3: a docs-only diff against the remote default branch needs no loop, so the hook asks (no marker for this tree).
  if { cd "$W/repo" && git update-ref refs/remotes/origin/main HEAD && git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main \
      && printf '%s\n' "$U" > notes.md && git add notes.md && git -c user.name=smoke -c user.email=smoke@example.com commit -q -m docs; }; then
    hook_probe
    case "$HP_RES" in
      *smoke-gh-ran*) echo "FAIL P3 docs-only: gh pr create ran on a docs-only diff (ask did not stop it, see P2)"; rc=1 ;;
      *"pre-PR loop has not passed"*) echo "FAIL P3 docs-only: the hook denied a docs-only diff"; printf '%s\n' "$HP_OUT" | tail -n 20; rc=1 ;;
      "") echo "FAIL P3 docs-only: no gh pr create result in the output"; printf '%s\n' "$HP_OUT" | tail -n 20; rc=1 ;;
      *) echo "PASS P3 docs-only: the hook asked instead of denying ($(printf '%s' "$HP_RES" | head -c 120))" ;;
    esac
  else
    echo "FAIL P3 docs-only: could not make the docs-only commit"; rc=1
  fi
  exit "$rc"
fi

if [ "$AUDIT" -eq 1 ]; then
  # A1: a throwaway plugin repo; main holds a clean skill, branch plant adds one dated pattern on a known line.
  AM=${AUDIT_MODEL:-sonnet}
  PLANT='CRITICAL: You MUST ALWAYS use the claude-3-5-sonnet-20241022 model for this step, and NEVER skip it.'
  A="$W/arepo"
  mkdir -p "$A/.claude-plugin" "$A/skills/demo" || { echo "FAIL A1: mkdir"; exit 1; }
  printf '{"name":"demo","description":"audit smoke"}\n' > "$A/.claude-plugin/plugin.json"
  {
    printf '%s\n' '---' 'name: demo' 'description: "Summarizes a changelog entry in one sentence. Use when a changelog entry needs a one-line summary."' \
      'disable-model-invocation: true' '---' '' '# Demo' '' 'Read the changelog entry the user names.' 'Summarize it in one sentence that states what changed for the user.'
  } > "$A/skills/demo/SKILL.md"
  { cd "$A" && git init -q -b main && git add -A && git -c user.name=smoke -c user.email=smoke@example.com commit -q -m base \
      && git checkout -q -b plant && printf '%s\n' "$PLANT" >> skills/demo/SKILL.md; } || { echo "FAIL A1: could not make the audit repo"; exit 1; }
  LN=$(grep -nF -- "$PLANT" "$A/skills/demo/SKILL.md" | cut -d: -f1)
  [ -n "$LN" ] || { echo "FAIL A1: no planted line"; exit 1; }
  before=$(cd "$A" && { git status --short; git diff; git rev-parse HEAD; } | shasum)
  t0=$(date +%s)
  (cd "$A" && bash "$REPO/plugins/senioro/scripts/prompt-audit.sh" main "$W/audit-report.md" "$AM") ; arc=$?
  secs=$(( $(date +%s) - t0 ))
  after=$(cd "$A" && { git status --short; git diff; git rev-parse HEAD; } | shasum)
  d=""
  [ "$arc" -eq 0 ] || d+="prompt-audit.sh exited $arc; "
  [ "$before" = "$after" ] || d+="the repo changed (git status or diff differs); "
  [ "$secs" -le 600 ] || d+="took $secs s, over 600; "
  [ -s "$W/audit-report.md" ] || d+="the report is empty; "
  cited=$(perl -ne 'while (m#SKILL\.md:(\d+)(?:[-\x{2013}](\d+))?#g) { print "$1-", ($2 // $1), "\n" }' "$W/audit-report.md" 2>/dev/null)
  hit=$(printf '%s\n' "$cited" | awk -F- -v n="$LN" '$1 <= n && n <= $2 { print "yes"; exit }')
  [ "$hit" = yes ] || d+="the report does not cite skills/demo/SKILL.md line $LN (cited: $(printf '%s' "$cited" | tr '\n' ' ')); "
  if [ -z "$d" ]; then
    echo "PASS A1 audit: exit 0 in $secs s, the report cites SKILL.md:$LN, the repo is unchanged ($(grep -m1 -F "SKILL.md" "$W/audit-report.md" | head -c 160))"
  else
    echo "FAIL A1 audit: ${d}retry with /doctor prompt-audit skills/demo/SKILL.md in another session, then use the fallback in #30"
    head -n 30 "$W/audit-report.md" 2>/dev/null | cut -c1-300; rc=1
  fi
  exit "$rc"
fi

# find_session <session id>: prints the transcript path of a session this script started (any project dir).
find_session() { find "$HOME"/.claude/projects -maxdepth 2 -name "$1.jsonl" 2>/dev/null | head -n1; }

# model_family <model id>: haiku, sonnet, opus or the id itself.
model_family() { case "$1" in *haiku*) echo haiku ;; *sonnet*) echo sonnet ;; *opus*) echo opus ;; *) echo "$1" ;; esac; }

if [ "$WALLET" -eq 1 ]; then
  # wallet_run <value>: one haiku orchestrate session with that wallet, in a throwaway plugin config (user-level
  # settings are not read: --setting-sources is empty and --settings carries the option; the in-place plugin's id is
  # senioro@inline). Sets WR_OUT (stream), WR_SPAWNS ("type=model" per Agent call, "none" when no model was passed)
  # and WR_FAMS (the model families in the result's model usage).
  wallet_run() {
    local ws m f
    ws=$(uuidgen | tr '[:upper:]' '[:lower:]')
    mkdir -p "$W/work" || return 1
    WR_OUT=$(cd "$W/work" && claude -p ${PD[@]+"${PD[@]}"} --session-id "$ws" --model haiku --max-turns 16 --permission-mode acceptEdits \
      --setting-sources "" --settings "{\"pluginConfigs\":{\"senioro@inline\":{\"options\":{\"wallet\":\"$1\"}}}}" \
      --output-format stream-json --verbose \
      -- "/senioro:orchestrate --soft Spawn exactly three seats, one each, and report what they return. The runner runs: echo smoke-42 . The implementer creates the file $W/work/w.txt containing the word ok. The verifier checks that $W/work/w.txt exists and holds the word ok. Spawn no other seat." < /dev/null 2>&1)
    f=$(find_session "$ws"); [ -z "$f" ] || SESS+=("$f")
    rm -rf "$HOME/.cache/senioro-tl/runs/${ws:?}" "$W/work"
    WR_SPAWNS=$(printf '%s\n' "$WR_OUT" | jq -Rrn '[inputs | fromjson? | objects] | .[] | select(.type=="assistant") | .message.content[]?
      | select(.type=="tool_use" and (.name=="Agent" or .name=="Task")) | "\(.input.subagent_type // "?")=\(.input.model // "none")"' 2>/dev/null | sort | tr '\n' ' ')
    WR_FAMS=$(for m in $(printf '%s\n' "$WR_OUT" | jq -Rrn '[inputs | fromjson? | objects | select(.type=="result") | .modelUsage // {} | keys[]] | unique | .[]' 2>/dev/null); do model_family "$m"; done | sort -u | tr '\n' ' ')
  }
  # W1: wallet=ramen must give haiku and sonnet only, with all three seats spawned. W2 (control): wallet=omakase-bro
  # must bring in opus (verifier, implementer) and keep the runner on sonnet, which proves the option is read; ramen
  # and an unset wallet give the same models on this task.
  for w in ramen omakase-bro; do
    wallet_run "$w" || { echo "FAIL W1 wallet: mkdir"; exit 1; }
    d=""
    for t in senioro:runner senioro:verifier senioro:implementer; do
      case " $WR_SPAWNS" in *" $t="*) ;; *) d+="no $t spawn; " ;; esac
    done
    if [ "$w" = ramen ]; then n=W1; want="haiku sonnet "; else n=W2; want="haiku opus sonnet "; fi
    [ "$WR_FAMS" = "$want" ] || d+="model usage is '${WR_FAMS% }', expected '${want% }'; "
    if [ "$w" = omakase-bro ]; then
      for t in senioro:runner=sonnet senioro:verifier=opus senioro:implementer=opus; do
        case " $WR_SPAWNS" in *" $t "*) ;; *) d+="no $t spawn; " ;; esac
      done
    fi
    if [ -z "$d" ]; then
      echo "PASS $n wallet=$w: model usage ${WR_FAMS% }; spawns ${WR_SPAWNS% }"
    else
      echo "FAIL $n wallet=$w: $d(spawns ${WR_SPAWNS% })"; printf '%s\n' "$WR_OUT" | tail -n 12 | cut -c1-400; rc=1
    fi
  done
  exit "$rc"
fi

if [ "$EFFORT" -eq 1 ]; then
  # E1: one fixed verifier task, six runs. seat_tokens sums output and thinking tokens over the seat's requests.
  ver=$(claude --version 2>/dev/null | awk '{print $1}')
  [ -n "$ver" ] && [ "$(printf '%s\n%s\n' 2.1.292 "$ver" | sort -V | head -n1)" = 2.1.292 ] \
    || { echo "FAIL E1 effort: needs Claude Code 2.1.292 or later (found '${ver:-none}')"; exit 1; }
  TASK='Rule on three claims without running any command, reasoning them out: #1 the 12th Fibonacci number (F1=F2=1) is 144; #2 2^40 mod 7 equals 2; #3 the number of primes below 60 is 17. Answer one line per claim, CONFIRMED or REFUTED with the value.'
  seat_tokens() {
    cat "${1%.jsonl}"/subagents/agent-*.jsonl 2>/dev/null | jq -rs '[.[] | select(.type=="assistant" and (.message.usage | type)=="object" and .message.model != "<synthetic>")]
      | group_by(.requestId // .message.id) | map(.[-1].message.usage)
      | "\(map(.output_tokens // 0) | add // 0) \(map(.output_tokens_details.thinking_tokens // 0) | add // 0)"'
  }
  declare -a LOW=() HIGH=()
  d=""
  for i in 1 2 3; do
    for e in low max; do
      ES=$(uuidgen | tr '[:upper:]' '[:lower:]')
      out=$(cd "$W" && claude -p ${PD[@]+"${PD[@]}"} --session-id "$ES" --model haiku --max-turns 6 --output-format stream-json --verbose \
        -- "Spawn the senioro:verifier agent once (subagent_type senioro:verifier) with model sonnet and effort $e, and give it this task verbatim: $TASK Wait for it, then reply with its answer. Spawn nothing else." < /dev/null 2>&1)
      f=$(find_session "$ES"); [ -z "$f" ] || SESS+=("$f")
      got=$(printf '%s\n' "$out" | jq -Rrn '[inputs | fromjson? | objects] | [.[] | select(.type=="assistant") | .message.content[]?
        | select(.type=="tool_use" and (.name=="Agent" or .name=="Task") and .input.subagent_type=="senioro:verifier") | (.input.effort // "none")] | join(",")' 2>/dev/null)
      [ "$got" = "$e" ] || d+="run $i $e: the spawn carried effort '${got:-no spawn}'; "
      if [ -z "$f" ]; then d+="run $i $e: no transcript; "; continue; fi
      read -r o t <<< "$(seat_tokens "$f")"
      tot=$(( ${o:-0} + ${t:-0} ))
      echo "run $i $e: output $o thinking $t total $tot ($(bash "$REPO/plugins/senioro/scripts/token-spend.sh" "$f" 2>/dev/null | grep '^seats ' | cut -c1-120))"
      if [ "$e" = low ]; then LOW+=("$tot"); else HIGH+=("$tot"); fi
    done
  done
  if [ "${#LOW[@]}" -eq 3 ] && [ "${#HIGH[@]}" -eq 3 ]; then
    maxlow=$(printf '%s\n' "${LOW[@]}" | sort -n | tail -n1); minhigh=$(printf '%s\n' "${HIGH[@]}" | sort -n | head -n1)
    [ "$minhigh" -gt "$maxlow" ] || d+="smallest max run $minhigh does not exceed largest low run $maxlow; "
  else
    d+="fewer than three measured runs per level; "
  fi
  if [ -z "$d" ]; then
    echo "PASS E1 effort: every max run (low ${LOW[*]}, max ${HIGH[*]}) exceeds every low run"
  else
    echo "FAIL E1 effort: ${d}(low ${LOW[*]:-none}, max ${HIGH[*]:-none})"; rc=1
  fi
  exit "$rc"
fi

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
