#!/usr/bin/env bash
# Gate functions are called indirectly as "gate_$g".
# shellcheck disable=SC2317,SC2329
# Deterministic gates G1-G5 (SPEC section 7) and stage, scope, rubric (SPEC-workflow section 11).
# Usage: tests/check.sh [validate|guard|grep|lint|layout|stage|scope|rubric ...] [-- <path> ...]
# No gate named = validate guard grep lint layout scope rubric (layout runs stage on every stage skill).
# Paths after -- replace the grep gate's default scan set and limit stage to the stage-skill dirs under them.
# Needs bash, jq, perl, git and claude; shellcheck and node are optional. No gate reads git history.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 2

GATES=()
PATHS=()
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--" ]; then shift; PATHS=("$@"); break; fi
  GATES+=("$1"); shift
done
[ "${#GATES[@]}" -gt 0 ] || GATES=(validate guard grep lint layout scope rubric)
[ "${#PATHS[@]}" -gt 0 ] || PATHS=(.claude-plugin plugins README.md LICENSE THIRD_PARTY_NOTICES.md .gitignore tests)

PLUGIN=plugins/senioro
SKILLS="bro check-before-pr decide-step-by-step frame-goal orchestrate preflight resolve-plan-issues resolve-review-findings review-implementation review-spec-plan status technical-writing typescript-best-practices unslop write-prd write-spec"
# Model-invocable skills (SPEC #13, #14): disable-model-invocation must be absent; every other skill has it true.
AUTO_SKILLS="technical-writing typescript-best-practices unslop"
# Workflow-stage skills checked by the stage gate (SPEC-workflow section 11).
STAGE_SKILLS="check-before-pr frame-goal preflight review-spec-plan status write-prd write-spec"
AGENTS="architect implementer investigator runner verifier"
# Agent model:effort as promised by the README components table (SPEC section 1: unchanged per seat).
AGENT_ME="architect:opus:xhigh implementer:opus:high investigator:opus:high runner:haiku:low verifier:sonnet:high"
# shellcheck disable=SC2016
LINE14='          command: "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/tl-guard.sh\""'
# Derived paths under plugins/senioro/skills/ that THIRD_PARTY_NOTICES.md must name: the "our path" column
# of the SPEC-workflow section 12 mapping table, deduplicated, with lens-{...}.md expanded to one path per lens.
ATTRIB="check-before-pr/SKILL.md frame-goal/SKILL.md preflight/SKILL.md
review-spec-plan/references/lead-judgment.md review-spec-plan/references/lens-architect.md
review-spec-plan/references/lens-blast-radius.md review-spec-plan/references/lens-root-cause.md
review-spec-plan/references/lens-spec-quality.md review-spec-plan/review.workflow.js status/SKILL.md
write-prd/SKILL.md write-prd/references/prd-template.md write-spec/SKILL.md
write-spec/references/hygiene.md write-spec/references/spec-template.md"

# hashes <file>: sha256 of each line, one per line; the routine that made tests/baseline/*.sha256 at 4f092cc.
hashes() { perl -MDigest::SHA=sha256_hex -ne 'chomp; print sha256_hex($_), "\n"' "$1"; }

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

# G2: tl-guard and pr-guard fixtures.
gate_guard() {
  local t out bad=""
  for t in tests/tl-guard.test.sh tests/pr-guard.test.sh; do
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
    review-spec-plan) printf '%s\n' review.workflow.js '### Must Fix' ;;
    preflight) printf '%s\n' READY baseline ;;
    status) printf '%s\n' DONE LEFT NEXT ;;
    check-before-pr) printf '%s\n' approval untrusted --record ;;
  esac
}

# stage_skills <skill ...>: prints one problem per failed stage check; dirs that are absent are skipped.
stage_skills() {
  local n d f desc p r out
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
    [ "$n" = review-spec-plan ] || continue
    f="$d/review.workflow.js"
    [ -f "$f" ] || { echo "$f missing; "; continue; }
    # FW7: the script compiles as an async function body once ^export is stripped; skipped without node.
    if command -v node >/dev/null 2>&1; then
      out=$(node -e 'const s=require("fs").readFileSync(process.argv[1],"utf8").replace(/^export /gm,"");const AF=Object.getPrototypeOf(async function(){}).constructor;new AF("args","agent","parallel","phase","log",s);' "$f" 2>&1) \
        || echo "$f does not compile: $(printf '%s' "$out" | head -n5 | tr '\n' ' '); "
    fi
    while IFS= read -r r; do
      [ -f "$d/references/$r" ] || echo "$f names references/$r, which is missing; "
    done < <(grep -oE '(lens-[a-z0-9-]+|lead-judgment)\.md' "$f" | sort -u)
    # agentType literals, and every string literal that starts with senioro: (seat tables), must be allowed seats.
    out=$(perl -ne 'print "$1\n" while /\bagentType\s*:\s*[\x27"\x60]([^\x27"\x60]*)/g; print "$1\n" while /[\x27"\x60](senioro:[^\x27"\x60]*)/g' "$f" | sort -u)
    [ -n "$out" ] || echo "$f names no agentType; "
    for r in $out; do
      case "$r" in senioro:architect|senioro:investigator|senioro:verifier) ;; *) echo "$f agentType '$r' is not senioro:architect|investigator|verifier; " ;; esac
    done
    grep -qE 'args\.dir\b' "$f" || echo "$f does not read args.dir; "
    grep -qE 'args\.prior\b' "$f" || echo "$f does not read args.prior; "
    grep -qF 'new evidence' "$f" || echo "$f lacks 'new evidence'; "
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
  local bad="" got n f e
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
  [ -x "$PLUGIN/scripts/tl-guard.sh" ] || bad+="scripts/tl-guard.sh not executable; "
  [ -x "$PLUGIN/scripts/pr-guard.sh" ] || bad+="scripts/pr-guard.sh not executable; "
  [ -f "$PLUGIN/skills/review-spec-plan/review.workflow.js" ] || bad+="review-spec-plan/review.workflow.js missing; "
  [ ! -f "$PLUGIN/hooks/hooks.json" ] || jq -e '.hooks.PreToolUse|length>0' "$PLUGIN/hooks/hooks.json" >/dev/null 2>&1 || bad+="hooks/hooks.json has no PreToolUse hooks; "
  [ "$(sed -n 14p "$PLUGIN/skills/orchestrate/SKILL.md" 2>/dev/null)" = "$LINE14" ] || bad+="orchestrate SKILL.md line 14 differs; "
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

# scope_check <skill> "<allowed old lines>" "<allowed a-hunk old lines>": diffs tests/baseline/<skill>.sha256
# against the current SKILL.md line hashes; prints every hunk whose old range leaves the allowed lines.
scope_check() {
  local f="$PLUGIN/skills/$1/SKILL.md" b="tests/baseline/$1.sha256"
  { [ -f "$f" ] && [ -f "$b" ]; } || { echo "$1: $f or $b missing; "; return; }
  diff "$b" <(hashes "$f") | S="$1" ALLOW=" $2 " APPEND=" $3 " perl -ne '
    next unless /^(\d+)(?:,(\d+))?([acd])\d+(?:,\d+)?$/;
    my ($a1, $a2, $op) = ($1, $2 // $1, $3);
    if ($op eq "a") { print "$ENV{S}: hunk $_" unless $ENV{APPEND} =~ / $a1 /; next }
    for my $n ($a1 .. $a2) { print "$ENV{S}: old line $n\n" unless $ENV{ALLOW} =~ / $n / }'
}

# scope: frozen skills change only on the lines SPEC-workflow section 8 lists (in the style of SPEC.md G7).
gate_scope() {
  local bad
  bad=$(scope_check orchestrate "38 77 80 92 111" "80"
        scope_check decide-step-by-step "7 16 22" ""
        scope_check resolve-plan-issues "6 17 18" "")
  [ -z "$bad" ] || { echo "$bad"; return 1; }
}

# rubric: baseline lines 26-92 and 126-138 of review-spec-plan appear, in order, in lens-spec-quality.md.
gate_rubric() {
  local f="$PLUGIN/skills/review-spec-plan/references/lens-spec-quality.md" b=tests/baseline/review-spec-plan.sha256 out
  [ -f "$f" ] || { echo "$f missing"; return 1; }
  [ -f "$b" ] || { echo "$b missing"; return 1; }
  out=$(hashes "$f" | B="$b" perl -e '
    open my $fh, "<", $ENV{B} or die "$ENV{B}: $!\n"; my @b = <$fh>; chomp @b;
    die "$ENV{B} has fewer than 138 lines\n" if @b < 138;
    my @n = (26 .. 92, 126 .. 138); my $i = 0;
    while (my $h = <STDIN>) { chomp $h; $i++ if $i < @n && $h eq $b[$n[$i] - 1] }
    print "baseline line $n[$i] not found in order (", @n - $i, " of ", scalar @n, " rubric lines missing)\n" if $i < @n;' 2>&1)
  [ -z "$out" ] || { echo "$out"; return 1; }
}

rc=0
for g in "${GATES[@]}"; do
  case "$g" in
    validate|guard|grep|lint|layout|stage|scope|rubric) ;;
    *) echo "FAIL $g: unknown gate"; rc=1; continue ;;
  esac
  if out=$("gate_$g" 2>&1); then
    case "$out" in SKIP*) echo "$out" ;; *) echo "PASS $g" ;; esac
  else
    echo "FAIL $g: $out"; rc=1
  fi
done
exit "$rc"
