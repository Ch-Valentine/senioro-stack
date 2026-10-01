#!/usr/bin/env bash
# Gate functions are called indirectly as "gate_$g".
# shellcheck disable=SC2317,SC2329
# Deterministic gates G1-G5 (SPEC section 7).
# Usage: tests/check.sh [validate|guard|grep|lint|layout ...] [-- <path> ...]
# No gate named = all gates. Paths after -- replace the grep gate's default scan set.
# Needs bash, jq, perl and claude; shellcheck is optional.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 2

GATES=()
PATHS=()
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--" ]; then shift; PATHS=("$@"); break; fi
  GATES+=("$1"); shift
done
[ "${#GATES[@]}" -gt 0 ] || GATES=(validate guard grep lint layout)
[ "${#PATHS[@]}" -gt 0 ] || PATHS=(.claude-plugin plugins README.md LICENSE .gitignore tests)

PLUGIN=plugins/senioro
SKILLS="decide-step-by-step orchestrate resolve-plan-issues resolve-review-findings review-implementation review-spec-plan"
AGENTS="architect implementer investigator runner verifier"
# Agent model:effort as promised by the README components table (SPEC section 1: unchanged per seat).
AGENT_ME="architect:opus:xhigh implementer:opus:high investigator:opus:high runner:haiku:low verifier:sonnet:high"
# shellcheck disable=SC2016
LINE14='          command: "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/tl-guard.sh\""'

# G1: non-strict validate; no errors, only the version warning allowed (F5).
gate_validate() {
  local t out bad=""
  for t in . "$PLUGIN"; do
    # stdout only: stderr stays out of the JSON that jq parses (it still reaches the gate's output).
    if ! out=$(claude plugin validate --json "$t"); then
      bad+="$t: claude plugin validate exited non-zero: $out; "; continue
    fi
    printf '%s' "$out" | jq -e '([.manifest.errors[]?, .contents[]?.errors[]?]|length==0) and ([.manifest.warnings[]?, .contents[]?.warnings[]?]|map(select(.path|endswith("version")|not))|length==0)' >/dev/null \
      || bad+="$t: $out; "
  done
  [ -z "$bad" ] || { echo "$bad"; return 1; }
}

# G2: tl-guard fixtures.
gate_guard() {
  local out
  [ -f tests/tl-guard.test.sh ] || { echo "tests/tl-guard.test.sh missing"; return 1; }
  out=$(bash tests/tl-guard.test.sh 2>&1) || { echo "$out"; return 1; }
}

# G3: ban regexes. Pattern files get only P_PATH; every other file gets P_ALL.
gate_grep() {
  # shellcheck disable=SC2016
  local P_ALL='(?<!cache/)senioro-(?!stack\b)[a-z*\{][^\s\x60"]*|\$HOME/\.claude|~/\.claude/(?:skills|agents)|/Users/|senioro:tl\b|relesio|additionalDirectories|modelSettings|Fable'
  # shellcheck disable=SC2016
  local P_PATH='/Users/[A-Za-z0-9]|\$HOME/\.claude|~/\.claude/(?:skills|agents)'
  local PF='^(\./)?tests/(check|tl-guard\.test)\.sh$'
  local FILES hits
  scan() { local p=$1; shift; [ "$#" -eq 0 ] || P="$p" perl -ne 'while (m#$ENV{P}#g) { print "$ARGV:$.: $&\n" } close ARGV if eof' "$@"; }
  FILES=$(find "${PATHS[@]}" -type f | sort) || { echo "find failed on: ${PATHS[*]}"; return 1; }
  # shellcheck disable=SC2046
  hits=$(scan "$P_ALL" $(printf '%s\n' "$FILES" | grep -Ev "$PF"); \
         scan "$P_PATH" $(printf '%s\n' "$FILES" | grep -E "$PF"))
  [ -z "$hits" ] || { echo "$hits"; return 1; }
}

# G4: shellcheck, SKIP when absent.
gate_lint() {
  local out
  command -v shellcheck >/dev/null 2>&1 || { echo "SKIP lint: shellcheck not installed"; return 0; }
  out=$(shellcheck "$PLUGIN/scripts/tl-guard.sh" tests/*.sh 2>&1) || { echo "$out"; return 1; }
}

# G5: tree shape, names, frontmatter flags, modes, manifests, LICENSE.
gate_layout() {
  local bad="" got n f e
  fm() { sed -n "s/^$1: *//p" "$2" 2>/dev/null | head -n1; }
  got=$(find "$PLUGIN/skills" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort | tr '\n' ' ')
  [ "$got" = "$SKILLS " ] || bad+="skill dirs are '$got'; "
  got=$(find "$PLUGIN/agents" -mindepth 1 -maxdepth 1 -type f -name '*.md' -exec basename {} .md \; 2>/dev/null | sort | tr '\n' ' ')
  [ "$got" = "$AGENTS " ] || bad+="agent files are '$got'; "
  for n in $SKILLS; do
    f="$PLUGIN/skills/$n/SKILL.md"
    [ "$(sed -n 's/^name: *//p' "$f" 2>/dev/null | head -n1)" = "$n" ] || bad+="$f name != $n; "
    [ "$(fm disable-model-invocation "$f")" = true ] || bad+="$f disable-model-invocation != true; "
  done
  for e in $AGENT_ME; do
    f="$PLUGIN/agents/${e%%:*}.md"
    [ "$(fm model "$f"):$(fm effort "$f")" = "${e#*:}" ] || bad+="$f model:effort != ${e#*:}; "
  done
  for n in $AGENTS; do
    f="$PLUGIN/agents/$n.md"
    [ "$(sed -n 's/^name: *//p' "$f" 2>/dev/null | head -n1)" = "$n" ] || bad+="$f name != $n; "
  done
  [ -x "$PLUGIN/scripts/tl-guard.sh" ] || bad+="scripts/tl-guard.sh not executable; "
  [ "$(sed -n 14p "$PLUGIN/skills/orchestrate/SKILL.md" 2>/dev/null)" = "$LINE14" ] || bad+="orchestrate SKILL.md line 14 differs; "
  jq -e 'has("version")|not' "$PLUGIN/.claude-plugin/plugin.json" >/dev/null || bad+="plugin.json has version; "
  jq -e '.plugins[0]|has("version")|not' .claude-plugin/marketplace.json >/dev/null || bad+="marketplace plugins[0] has version; "
  jq -e '.plugins[0].name=="senioro" and .plugins[0].source=="./plugins/senioro"' .claude-plugin/marketplace.json >/dev/null || bad+="marketplace plugins[0] name/source; "
  jq -e '.name=="senioro"' "$PLUGIN/.claude-plugin/plugin.json" >/dev/null || bad+="plugin.json name; "
  [ "$(head -n1 LICENSE)" = "MIT License" ] || bad+="LICENSE line 1; "
  { [ -L "$PLUGIN/LICENSE" ] && [ "$(readlink "$PLUGIN/LICENSE")" = ../../LICENSE ] && [ "$(head -n1 "$PLUGIN/LICENSE")" = "MIT License" ]; } || bad+="$PLUGIN/LICENSE is not a resolving symlink to ../../LICENSE; "
  [ -z "$bad" ] || { echo "$bad"; return 1; }
}

rc=0
for g in "${GATES[@]}"; do
  case "$g" in
    validate|guard|grep|lint|layout) ;;
    *) echo "FAIL $g: unknown gate"; rc=1; continue ;;
  esac
  if out=$("gate_$g" 2>&1); then
    case "$out" in SKIP*) echo "$out" ;; *) echo "PASS $g" ;; esac
  else
    echo "FAIL $g: $out"; rc=1
  fi
done
exit "$rc"
