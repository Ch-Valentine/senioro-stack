#!/usr/bin/env bash
# Gate functions are called indirectly as "gate_$g".
# shellcheck disable=SC2317,SC2329
# Deterministic gates G1-G5 (SPEC section 7), stage (spec 002 U1) and the wallet, review-loop and retro checks of layout (spec 002 U3, U5, U8).
# Usage: tests/check.sh [validate|guard|grep|lint|layout|stage ...] [-- <path> ...]
# No gate named = validate guard grep lint layout (layout runs stage on every stage skill).
# Paths after -- replace the grep gate's default scan set and limit stage to the stage-skill dirs under them.
# Needs bash, jq, perl, git and claude; shellcheck is optional. No gate reads git history.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 2

GATES=()
PATHS=()
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--" ]; then shift; PATHS=("$@"); break; fi
  GATES+=("$1"); shift
done
[ "${#GATES[@]}" -gt 0 ] || GATES=(validate guard grep lint layout)
[ "${#PATHS[@]}" -gt 0 ] || PATHS=(.claude-plugin plugins README.md LICENSE THIRD_PARTY_NOTICES.md .gitignore tests)

PLUGIN=plugins/senioro
SKILLS="bro check-before-pr decide-step-by-step frame-goal orchestrate preflight resolve-plan-issues resolve-review-findings review-implementation review-spec-plan status technical-writing typescript-best-practices unslop write-prd write-spec"
# Model-invocable skills (SPEC #13, #14): disable-model-invocation must be absent; every other skill has it true.
AUTO_SKILLS="technical-writing typescript-best-practices unslop"
# Workflow-stage skills checked by the stage gate.
STAGE_SKILLS="check-before-pr frame-goal preflight review-spec-plan status write-prd write-spec"
# Skills that read the wallet (spec 002 #12): each holds exactly one wallet line. orchestrate holds the table too.
WALLET_SKILLS="orchestrate check-before-pr resolve-review-findings resolve-plan-issues review-spec-plan frame-goal write-prd write-spec preflight status"
# The wallet table lives in this skill's route section (spec 002 #10); it is the only place a model name may sit in prose.
WALLET_TABLE_SKILL="orchestrate"
# orchestrate must fit the compaction window (spec 002 F12): at most this many characters.
ORCH_MAX_CHARS=16000
# review-spec-plan is a user-mode launcher (spec 002 #24): at most this many characters.
REVIEW_MAX_CHARS=2500
AGENTS="architect implementer investigator runner verifier"
# Agent model:effort as promised by the README components table (SPEC section 1: unchanged per seat).
AGENT_ME="architect:opus:xhigh implementer:opus:high investigator:opus:high runner:haiku:low verifier:sonnet:high"
# shellcheck disable=SC2016
LINE14='          command: "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/tl-guard.sh\""'
# Derived paths under plugins/senioro/skills/ that THIRD_PARTY_NOTICES.md must name, with lens-{...}.md expanded
# to one path per lens.
ATTRIB="check-before-pr/SKILL.md frame-goal/SKILL.md preflight/SKILL.md
review-spec-plan/references/lens-architect.md review-spec-plan/references/lens-blast-radius.md
review-spec-plan/references/lens-root-cause.md review-spec-plan/references/lens-spec-quality.md status/SKILL.md
write-prd/SKILL.md write-prd/references/prd-template.md write-spec/SKILL.md
write-spec/references/hygiene.md write-spec/references/spec-template.md"

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

# G2: every tests/*.test.sh (guard and script fixtures).
gate_guard() {
  local t out bad=""
  for t in tests/*.test.sh; do
    [ -f "$t" ] || { bad+="$t missing; "; continue; }
    out=$(bash "$t" 2>&1) || bad+="$t: $out; "
  done
  [ -z "$bad" ] || { echo "$bad"; return 1; }
}

# G3: ban regexes. Pattern files get only P_PATH; template files get P_ALL and P_TOOL; every other file gets P_ALL.
gate_grep() {
  # shellcheck disable=SC2016
  local P_ALL='(?<!cache/)senioro-(?!stack\b)[a-z*\{][^\s\x60"]*|\$HOME/\.claude|~/\.claude/(?:skills|agents)|/Users/|senioro:tl\b|relesio|additionalDirectories|modelSettings|Fable'
  # shellcheck disable=SC2016
  local P_PATH='/Users/[A-Za-z0-9]|\$HOME/\.claude|~/\.claude/(?:skills|agents)'
  # Skill, agent tool and slash-command names; status, preflight and bro are ordinary words in a template.
  local P_TOOL='senioro:|(?:^|[\s(\x60])/[a-z][a-z-]+\b|\b(?:frame-goal|write-prd|write-spec|review-spec-plan|check-before-pr|decide-step-by-step|resolve-plan-issues|resolve-review-findings|review-implementation|technical-writing|typescript-best-practices|orchestrate|unslop)\b'
  local PF='^(\./)?tests/(check|tl-guard\.test)\.sh$'
  local TF='(^|/)skills/[^/]+/references/[^/]+-template\.md$'
  local FILES hits
  scan() { local p=$1; shift; [ "$#" -eq 0 ] || P="$p" perl -ne 'while (m#$ENV{P}#g) { print "$ARGV:$.: $&\n" } close ARGV if eof' "$@"; }
  FILES=$(find "${PATHS[@]}" -type f | sort) || { echo "find failed on: ${PATHS[*]}"; return 1; }
  # shellcheck disable=SC2046
  hits=$(scan "$P_ALL" $(printf '%s\n' "$FILES" | grep -Ev "$PF" | grep -Ev "$TF"); \
         scan "$P_PATH" $(printf '%s\n' "$FILES" | grep -E "$PF"); \
         scan "$P_ALL|$P_TOOL" $(printf '%s\n' "$FILES" | grep -Ev "$PF" | grep -E "$TF"))
  [ -z "$hits" ] || { echo "$hits"; return 1; }
}

# G4: shellcheck, SKIP when absent.
gate_lint() {
  local out
  command -v shellcheck >/dev/null 2>&1 || { echo "SKIP lint: shellcheck not installed"; return 0; }
  out=$(shellcheck "$PLUGIN"/scripts/*.sh tests/*.sh 2>&1) || { echo "$out"; return 1; }
}

# stage_phrases <skill>: the phrases its SKILL.md must contain, one per line.
stage_phrases() {
  case "$1" in
    frame-goal) printf '%s\n' 'one question at a time' falsifiable Route ;;
    write-prd) printf '%s\n' 'User stories' 'Success measure' ;;
    write-spec) printf '%s\n' 'Alternatives considered' 'Test seams' hygiene.md ;;
    preflight) printf '%s\n' READY baseline ;;
    review-spec-plan) printf '%s\n' 'Spec review' resolve-plan-issues Status ;;
    status) printf '%s\n' DONE LEFT NEXT ;;
    check-before-pr) printf '%s\n' approval untrusted --record ;;
  esac
}

# stage_skills <skill ...>: prints one problem per failed stage check; dirs that are absent are skipped.
stage_skills() {
  local n d f desc p out
  for n in "$@"; do
    d="$PLUGIN/skills/$n"; f="$d/SKILL.md"
    [ -d "$d" ] || continue
    [ -f "$f" ] || { echo "$f missing; "; continue; }
    desc=$(grep -m1 '^description:' "$f")
    printf '%s\n' "$desc" | grep -Eq '^description: "?[A-Z][a-z]+s ' || echo "$f description is not third person; "
    case "$desc" in *"Use when"*) ;; *) echo "$f description lacks 'Use when'; " ;; esac
    [ "$(wc -l < "$f")" -lt 500 ] || echo "$f has 500 or more lines; "
    if [ -d "$d/references" ]; then
      out=$(find "$d/references" -mindepth 2)
      [ -z "$out" ] || echo "$d/references is nested: $(printf '%s' "$out" | tr '\n' ' '); "
      out=$(find "$d/references" -type f -exec grep -l 'references/' {} +)
      [ -z "$out" ] || echo "reference files name references/: $(printf '%s' "$out" | tr '\n' ' '); "
    fi
    while IFS= read -r p; do
      [ -z "$p" ] || grep -qF -- "$p" "$f" || echo "$f lacks '$p'; "
    done < <(stage_phrases "$n")
  done
}

# stage: stage_skills on the stage skills under the -- paths (all of them for the default scan set).
gate_stage() {
  local n p bad sel=()
  for n in $STAGE_SKILLS; do
    for p in "${PATHS[@]}"; do
      p=${p#./}; p=${p%/}
      case "$p" in .|"") sel+=("$n"); break ;; esac
      case "$PLUGIN/skills/$n/" in "$p"/*) sel+=("$n"); break ;; esac
      case "$p/" in "$PLUGIN/skills/$n"/*) sel+=("$n"); break ;; esac
    done
  done
  bad=$(stage_skills ${sel[@]+"${sel[@]}"})
  [ -z "$bad" ] || { echo "$bad"; return 1; }
}

# G5: tree shape, names, frontmatter flags, stage checks, modes, hooks, manifests, LICENSE, third-party notices.
gate_layout() {
  local bad="" got n f e m hits
  fm() { sed -n "s/^$1: *//p" "$2" 2>/dev/null | head -n1; }
  got=$(find "$PLUGIN/skills" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort | tr '\n' ' ')
  [ "$got" = "$SKILLS " ] || bad+="skill dirs are '$got'; "
  got=$(find "$PLUGIN/agents" -mindepth 1 -maxdepth 1 -type f -name '*.md' -exec basename {} .md \; 2>/dev/null | sort | tr '\n' ' ')
  [ "$got" = "$AGENTS " ] || bad+="agent files are '$got'; "
  for n in $SKILLS; do
    f="$PLUGIN/skills/$n/SKILL.md"
    [ "$(sed -n 's/^name: *//p' "$f" 2>/dev/null | head -n1)" = "$n" ] || bad+="$f name != $n; "
    case " $AUTO_SKILLS " in
      *" $n "*) [ -z "$(fm disable-model-invocation "$f")" ] || bad+="$f disable-model-invocation is set; " ;;
      *) [ "$(fm disable-model-invocation "$f")" = true ] || bad+="$f disable-model-invocation != true; " ;;
    esac
  done
  # shellcheck disable=SC2086
  bad+=$(stage_skills $STAGE_SKILLS | tr -d '\n')
  for e in $AGENT_ME; do
    f="$PLUGIN/agents/${e%%:*}.md"
    [ "$(fm model "$f"):$(fm effort "$f")" = "${e#*:}" ] || bad+="$f model:effort != ${e#*:}; "
  done
  for n in $AGENTS; do
    f="$PLUGIN/agents/$n.md"
    [ "$(sed -n 's/^name: *//p' "$f" 2>/dev/null | head -n1)" = "$n" ] || bad+="$f name != $n; "
  done
  for f in tl-guard pr-guard token-spend; do [ -f "$PLUGIN/scripts/$f.sh" ] || bad+="scripts/$f.sh missing; "; [ -f "tests/$f.test.sh" ] || bad+="tests/$f.test.sh missing; "; done
  for f in "$PLUGIN"/scripts/*.sh; do [ -x "$f" ] || bad+="scripts/${f##*/} not executable; "; done
  [ ! -f "$PLUGIN/hooks/hooks.json" ] || jq -e '.hooks.PreToolUse|length>0' "$PLUGIN/hooks/hooks.json" >/dev/null 2>&1 || bad+="hooks/hooks.json has no PreToolUse hooks; "
  [ "$(sed -n 14p "$PLUGIN/skills/orchestrate/SKILL.md" 2>/dev/null)" = "$LINE14" ] || bad+="orchestrate SKILL.md line 14 differs; "
  # Wallet (spec 002 U3): the option, one wallet line per wallet skill, each agent's model in its seat's sushi cells,
  # the model-name ban (#23) and the size cap.
  jq -e '.userConfig.wallet | .type=="string" and .default=="sushi" and (.options|sort)==["omakase-bro","ramen","sushi"]' "$PLUGIN/.claude-plugin/plugin.json" >/dev/null 2>&1 \
    || bad+="plugin.json userConfig.wallet is not a string option with ramen, sushi and omakase-bro and default sushi; "
  for n in $WALLET_SKILLS; do
    f="$PLUGIN/skills/$n/SKILL.md"
    # shellcheck disable=SC2016
    [ "$(grep -oF '${user_config.wallet}' "$f" 2>/dev/null | wc -l | tr -d ' ')" = 1 ] || bad+="$f does not hold exactly one \${user_config.wallet}; "
  done
  f="$PLUGIN/skills/$WALLET_TABLE_SKILL/SKILL.md"
  for n in $AGENTS; do
    m=$(fm model "$PLUGIN/agents/$n.md")
    # Table rows read: | task | seat | ramen | sushi | omakase-bro |
    awk -F'|' -v s="$n" '{ gsub(/^ +| +$/, "", $3) } $3 == s { print $5 }' "$f" 2>/dev/null | grep -qw -- "$m" || bad+="agent $n model '$m' is in none of its sushi cells in $f; "
  done
  # shellcheck disable=SC2016
  hits=$(find "$PLUGIN/agents" "$PLUGIN/skills" -name '*.md' ! -path "$PLUGIN/skills/orchestrate/references/evidence.md" | sort \
    | xargs perl -ne 'next if $ARGV =~ m#/agents/# && $. <= 10 && /^model: /; next if $ARGV =~ m#/skills/orchestrate/SKILL\.md$# && /^\|/; while (/\b(?:opus|sonnet)\b/gi) { print "$ARGV:$.: $&; " } close ARGV if eof')
  [ -z "$hits" ] || bad+="opus or sonnet outside the wallet table rows and frontmatter model lines: $hits"
  [ "$(perl -MEncode -0777 -ne 'print length(decode("UTF-8", $_))' "$f" 2>/dev/null || echo 99999)" -le "$ORCH_MAX_CHARS" ] || bad+="$f is over $ORCH_MAX_CHARS characters; "
  [ "$(perl -MEncode -0777 -ne 'print length(decode("UTF-8", $_))' "$PLUGIN/skills/review-spec-plan/SKILL.md" 2>/dev/null || echo 99999)" -le "$REVIEW_MAX_CHARS" ] || bad+="review-spec-plan SKILL.md is over $REVIEW_MAX_CHARS characters; "
  # Spec review (spec 002 U4): the headings other skills grep, and the After review pointer to the shared flow text.
  for e in '## Route the seat' '## Spec review'; do
    grep -qxF -- "$e" "$f" 2>/dev/null || bad+="$f lacks the heading '$e'; "
  done
  grep -qxF -- '## After-review flow' "$PLUGIN/skills/resolve-plan-issues/SKILL.md" 2>/dev/null || bad+="resolve-plan-issues SKILL.md lacks the heading '## After-review flow'; "
  grep -E 'After-review flow' "$f" 2>/dev/null | grep -qF 'skills/resolve-plan-issues/SKILL.md' || bad+="$f does not point to the After-review flow in resolve-plan-issues; "
  # Review loop and TL text (spec 002 U5): resolve-review-findings reads the flow by path; the diff base is a stash sha, not
  # base..head; the character and line ceilings are gone; the stage criteria file is named where seats are briefed.
  grep -E 'After-review flow' "$PLUGIN/skills/resolve-review-findings/SKILL.md" 2>/dev/null | grep -qF 'skills/resolve-plan-issues/SKILL.md' || bad+="resolve-review-findings SKILL.md does not point to the After-review flow in resolve-plan-issues; "
  hits=$(grep -rnE '<base>\.\.<head>|Base\.\.Head' "$PLUGIN" README.md 2>/dev/null)
  [ -z "$hits" ] || bad+="base..head wording: $hits; "
  hits=$(grep -nE '1,200|200 words|≤ 8 lines' "$f" 2>/dev/null)
  [ -z "$hits" ] || bad+="$f keeps a brief, map or board ceiling: $hits; "
  for e in "$f" "$PLUGIN/skills/review-implementation/SKILL.md"; do
    grep -qF 'stash create' "$e" 2>/dev/null || bad+="$e lacks 'stash create'; "
  done
  [ -f "$PLUGIN/skills/orchestrate/references/stages.md" ] || bad+="orchestrate/references/stages.md missing; "
  for e in "$f" "$PLUGIN/skills/review-spec-plan/SKILL.md"; do
    grep -qF 'orchestrate/references/stages.md' "$e" 2>/dev/null || bad+="$e does not name orchestrate/references/stages.md; "
  done
  # Retro (spec 002 U8): the block template exists with at most 10 lines, orchestrate names its path, the template names the script.
  e="$PLUGIN/skills/orchestrate/references/retro-template.md"
  { [ -f "$e" ] && [ "$(wc -l < "$e")" -le 10 ]; } || bad+="orchestrate/references/retro-template.md is missing or has more than 10 lines; "
  grep -qF 'orchestrate/references/retro-template.md' "$f" 2>/dev/null || bad+="$f does not name orchestrate/references/retro-template.md; "
  # The retro seat reads the template, so it names the script by a path that resolves from the template's directory.
  grep -qF '../../../scripts/token-spend.sh' "$e" 2>/dev/null && [ -f "${e%/*}/../../../scripts/token-spend.sh" ] || bad+="retro-template.md does not name a ../../../scripts/token-spend.sh that resolves; "
  jq -e 'has("version")|not' "$PLUGIN/.claude-plugin/plugin.json" >/dev/null || bad+="plugin.json has version; "
  jq -e '.plugins[0]|has("version")|not' .claude-plugin/marketplace.json >/dev/null || bad+="marketplace plugins[0] has version; "
  jq -e '.plugins[0].name=="senioro" and .plugins[0].source=="./plugins/senioro"' .claude-plugin/marketplace.json >/dev/null || bad+="marketplace plugins[0] name/source; "
  jq -e '.name=="senioro"' "$PLUGIN/.claude-plugin/plugin.json" >/dev/null || bad+="plugin.json name; "
  [ "$(head -n1 LICENSE)" = "MIT License" ] || bad+="LICENSE line 1; "
  { [ -L "$PLUGIN/LICENSE" ] && [ "$(readlink "$PLUGIN/LICENSE")" = ../../LICENSE ] && [ "$(head -n1 "$PLUGIN/LICENSE")" = "MIT License" ]; } || bad+="$PLUGIN/LICENSE is not a resolving symlink to ../../LICENSE; "
  { [ -L "$PLUGIN/THIRD_PARTY_NOTICES.md" ] && [ "$(readlink "$PLUGIN/THIRD_PARTY_NOTICES.md")" = ../../THIRD_PARTY_NOTICES.md ] && [ "$(head -n1 "$PLUGIN/THIRD_PARTY_NOTICES.md")" = "# Third-party notices" ]; } || bad+="$PLUGIN/THIRD_PARTY_NOTICES.md is not a resolving symlink to ../../THIRD_PARTY_NOTICES.md; "
  for e in '## mattpocock/skills (Matt Pocock)' d81f3a183412e71a5b1e84ca21bc1a35eea03a60 'Copyright (c) 2026 Matt Pocock' $ATTRIB; do
    grep -qF -- "$e" THIRD_PARTY_NOTICES.md 2>/dev/null || bad+="THIRD_PARTY_NOTICES.md lacks '$e'; "
  done
  [ -z "$bad" ] || { echo "$bad"; return 1; }
}

rc=0
for g in "${GATES[@]}"; do
  case "$g" in
    validate|guard|grep|lint|layout|stage) ;;
    *) echo "FAIL $g: unknown gate"; rc=1; continue ;;
  esac
  if out=$("gate_$g" 2>&1); then
    case "$out" in SKIP*) echo "$out" ;; *) echo "PASS $g" ;; esac
  else
    echo "FAIL $g: $out"; rc=1
  fi
done
exit "$rc"
