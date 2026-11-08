#!/usr/bin/env bash
# token-spend fixtures (spec 001 #7, section 7; spec 002 U2, #11, #18). Prints PASS n/n; exits non-zero on any failure.
# Runs plugins/senioro/scripts/token-spend.sh on tests/fixtures/token-spend/session.jsonl (TL, two seats, one
# workflow agent) and on tests/fixtures/token-spend/handback/session.jsonl (TL, three seats of three models, a
# foreground and a background hand-back, cut from a real session) and compares its exact stdout; also checks the
# exit codes and the unpriced-model warning.
set -uo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$REPO/plugins/senioro/scripts/token-spend.sh"
FIX="$REPO/tests/fixtures/token-spend/session.jsonl"
HB="$REPO/tests/fixtures/token-spend/handback/session.jsonl"
[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT missing"; exit 1; }
[ -f "$FIX" ] || { echo "FAIL: $FIX missing"; exit 1; }
[ -f "$HB" ] || { echo "FAIL: $HB missing"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq missing"; exit 1; }

T=$(mktemp -d) || { echo "FAIL: mktemp -d"; exit 1; }
trap 'rm -rf "${T:?}"' EXIT

total=0; passed=0; OUT=""; ERR=""; RC=0

# run <args>: runs the script; sets OUT (stdout), ERR (stderr) and RC (exit code).
run() { OUT=$(bash "$SCRIPT" "$@" 2>"$T/err"); RC=$?; ERR=$(cat "$T/err"); }

# pass <case> [failure detail]: counts the case; an empty detail is a pass.
pass() {
  total=$((total + 1))
  if [ -z "${2:-}" ]; then passed=$((passed + 1)); else echo "FAIL case $1: $2"; fi
}

# want <case> <rc> <stdout> [stderr substring]: the last run exited <rc> with exactly <stdout>.
want() {
  local d=""
  [ "$RC" -eq "$2" ] || d+="exit $RC, expected $2 "
  [ "$OUT" = "$3" ] || d+="stdout differs: $(diff <(printf '%s\n' "$3") <(printf '%s\n' "$OUT") | tr '\n' ' ') "
  if [ -n "${4:-}" ]; then
    case "$ERR" in *"$4"*) ;; *) d+="stderr lacks '$4': $ERR " ;; esac
  else
    [ -z "$ERR" ] || d+="unexpected stderr: $ERR "
  fi
  pass "$1" "$d"
}

# 1 --until: request t1 on two lines priced by its final line; the <synthetic> line, t4, a5 and r7 are after the
#   cutoff or excluded; 5m, 1h and unsplit writes; opus, sonnet, haiku; one resume (a3), one gap from a long turn (a4);
#   docs fetches w1, w4, w5 count, w2 follows a failed curl in its agent; b2 and b4 curl docs with no grep;
#   run-dir reads: named r1, r4; unnamed r2, r3; seat-written r5 (Write), r6 (redirect); TL reads 21,000 and 20,000 chars.
run "$FIX" --until 2026-01-01T01:00:00Z
want 1 0 "TL calls=2 usd=7.10 write=5.00 read=0.20 output=1.50 thinking=25000
seats calls=6 usd=4.38 write=3.80 read=0.10 output=0.48 thinking=28000
workflow calls=2 usd=1.19 write=1.00 read=0.08 output=0.11 thinking=8000
model opus calls=2 usd=7.10 write=5.00 read=0.20 output=1.50 thinking=25000
model sonnet calls=6 usd=4.38 write=3.80 read=0.10 output=0.48 thinking=28000
model haiku calls=2 usd=1.19 write=1.00 read=0.08 output=0.11 thinking=8000
seats: 2 (haiku 0, sonnet 2, opus 0)
resumes n=1 tokens=600000 usd=1.50
gaps n=1 tokens=300000 usd=1.05
fetch calls=5 chars=6550 docs_chars=4500 docs_curl_nogrep=2
runreads n=6 unnamed=2 chars=500
tl_bigreads n=1 chars=21000"

# 2 no cutoff: t4 and a5 count (a5 is a second resume); the late message names other.md, so r2 is named and r7 unnamed.
run "$FIX"
want 2 0 "TL calls=3 usd=11.78 write=9.50 read=0.20 output=1.68 thinking=25000
seats calls=7 usd=6.14 write=5.55 read=0.10 output=0.49 thinking=28000
workflow calls=2 usd=1.19 write=1.00 read=0.08 output=0.11 thinking=8000
model opus calls=3 usd=11.78 write=9.50 read=0.20 output=1.68 thinking=25000
model sonnet calls=7 usd=6.14 write=5.55 read=0.10 output=0.49 thinking=28000
model haiku calls=2 usd=1.19 write=1.00 read=0.08 output=0.11 thinking=8000
seats: 2 (haiku 0, sonnet 2, opus 0)
resumes n=2 tokens=1300000 usd=3.25
gaps n=1 tokens=300000 usd=1.05
fetch calls=5 chars=6550 docs_chars=4500 docs_curl_nogrep=2
runreads n=7 unnamed=2 chars=350
tl_bigreads n=1 chars=21000"

# 3 a model of no known family: counted, priced 0, named on stderr; no subagents dir.
printf '%s\n' '{"type":"assistant","timestamp":"2026-01-01T00:00:00Z","requestId":"x1","message":{"model":"claude-x-1","usage":{"input_tokens":5,"output_tokens":7}}}' > "$T/one.jsonl"
run "$T/one.jsonl"
want 3 0 "TL calls=1 usd=0.00 write=0.00 read=0.00 output=0.00 thinking=0
seats calls=0 usd=0.00 write=0.00 read=0.00 output=0.00 thinking=0
workflow calls=0 usd=0.00 write=0.00 read=0.00 output=0.00 thinking=0
model opus calls=0 usd=0.00 write=0.00 read=0.00 output=0.00 thinking=0
model sonnet calls=0 usd=0.00 write=0.00 read=0.00 output=0.00 thinking=0
model haiku calls=0 usd=0.00 write=0.00 read=0.00 output=0.00 thinking=0
seats: 0 (haiku 0, sonnet 0, opus 0)
resumes n=0 tokens=0 usd=0.00
gaps n=0 tokens=0 usd=0.00
fetch calls=0 chars=0 docs_chars=0 docs_curl_nogrep=0
runreads n=0 unnamed=0 chars=0
tl_bigreads n=0 chars=0" "1 requests of model claude-x-1 have no price"

# 4 a missing session file -> exit 2
run "$T/none.jsonl"; want 4 2 "" "not found"

# 5 no session argument -> exit 2
run; want 5 2 "" "usage:"

# 6 no jq on PATH -> exit 2
OUT=$(PATH="$T/empty" "$BASH" "$SCRIPT" "$FIX" 2>"$T/err"); RC=$?; ERR=$(cat "$T/err"); want 6 2 "" "jq not found"

# 7 a malformed --until (space instead of T) -> exit 2, usage message
run "$FIX" --until "2026-01-01 01:00:00"; want 7 2 "" "usage:"

# The hand-back fixture is cut from a real session: a foreground hand-back ("<usage>subagent_tokens: N", "tool_uses: N",
# "duration_ms: N") for a haiku and a sonnet seat before the split, and a background task notification
# ("<duration_ms>N</duration_ms>") for an opus seat after it. Expected values by hand:
#   spec = 12:15:51.969 to 14:00:00 = 104.1 min; seats (88179 + 59525) ms = 2.5 min; tokens: TL 86339 + 91707, haiku seat
#   5358 + 9499, sonnet seat 5316 + 7467 = 205686; build = 14:00:00 to 16:21:27.091 = 141.5 min; seats 1346154 ms = 22.4
#   min; tokens: TL 161410, opus seat 7533 + 10505 = 179448. Tokens are input + cache write + cache read + output.
#   usd: spec 0.1596, build 0.1712 (rates in the script header), opus 0.2821, sonnet 0.0297, haiku 0.0190.

# 8 no split: group lines, per-model lines and the seat count (one haiku, one sonnet, one opus seat)
run "$HB"
want 8 0 "TL calls=3 usd=0.21 write=0.04 read=0.07 output=0.10 thinking=2169
seats calls=6 usd=0.12 write=0.08 read=0.00 output=0.03 thinking=1146
workflow calls=0 usd=0.00 write=0.00 read=0.00 output=0.00 thinking=0
model opus calls=5 usd=0.28 write=0.10 read=0.07 output=0.12 thinking=2481
model sonnet calls=2 usd=0.03 write=0.02 read=0.00 output=0.01 thinking=330
model haiku calls=2 usd=0.02 write=0.01 read=0.00 output=0.01 thinking=504
seats: 3 (haiku 1, sonnet 1, opus 1)
resumes n=0 tokens=0 usd=0.00
gaps n=0 tokens=0 usd=0.00
fetch calls=0 chars=0 docs_chars=0 docs_curl_nogrep=0
runreads n=0 unnamed=0 chars=0
tl_bigreads n=0 chars=0"

# 9 --split between the two phases: exactly the retro's three lines
run "$HB" --split 2026-11-07T14:00:00Z
want 9 0 "spec: wall 104.1 min, seats 2.5 min, 205686 tokens, \$0.16 API-equivalent
build: wall 141.5 min, seats 22.4 min, 179448 tokens, \$0.17 API-equivalent
seats: 3 (haiku 1, sonnet 1, opus 1)"

# 10 --phase spec and 11 --phase build: the whole session is one phase, the other prints zeros
run "$HB" --phase spec
want 10 0 "spec: wall 245.6 min, seats 24.9 min, 385134 tokens, \$0.33 API-equivalent
build: wall 0.0 min, seats 0.0 min, 0 tokens, \$0.00 API-equivalent
seats: 3 (haiku 1, sonnet 1, opus 1)"
run "$HB" --phase build
want 11 0 "spec: wall 0.0 min, seats 0.0 min, 0 tokens, \$0.00 API-equivalent
build: wall 245.6 min, seats 24.9 min, 385134 tokens, \$0.33 API-equivalent
seats: 3 (haiku 1, sonnet 1, opus 1)"

# 12 --split with --until 13:00: only the two foreground hand-backs and the seats started before the cutoff remain;
#   wall ends at the 12:40:53.745 hand-back (25.0 min); the opus seat has no request left, so it is not counted
run "$HB" --split 2026-11-07T14:00:00Z --until 2026-11-07T13:00:00Z
want 12 0 "spec: wall 25.0 min, seats 2.5 min, 205686 tokens, \$0.16 API-equivalent
build: wall 0.0 min, seats 0.0 min, 0 tokens, \$0.00 API-equivalent
seats: 2 (haiku 1, sonnet 1, opus 0)"

# 13 the duration field renamed (a missing field) and a report that only quotes "duration_ms: 99999" outside a
#   <usage> block: seats minutes print n/a, the rest stays
mkdir -p "$T/hb13" && cp -R "$REPO/tests/fixtures/token-spend/handback/session" "$T/hb13/session"
sed 's/duration_ms/dur_ms/g' "$HB" > "$T/hb13/session.jsonl"
printf '%s\n' '{"type":"user","timestamp":"2026-11-07T16:21:28.000Z","message":{"role":"user","content":"the report said duration_ms: 99999"}}' >> "$T/hb13/session.jsonl"
run "$T/hb13/session.jsonl" --split 2026-11-07T14:00:00Z
want 13 0 "spec: wall 104.1 min, seats n/a min, 205686 tokens, \$0.16 API-equivalent
build: wall 141.5 min, seats n/a min, 179448 tokens, \$0.17 API-equivalent
seats: 3 (haiku 1, sonnet 1, opus 1)"

# 14-17 --split and --phase together, a malformed --split, an unknown phase, a missing value -> exit 2, usage message
run "$HB" --split 2026-11-07T14:00:00Z --phase spec; want 14 2 "" "usage:"
run "$HB" --split "2026-11-07 14:00:00"; want 15 2 "" "usage:"
run "$HB" --phase deploy; want 16 2 "" "usage:"
run "$HB" --phase; want 17 2 "" "usage:"

if [ "$passed" -eq "$total" ] && [ "$total" -eq 17 ]; then
  echo "PASS $passed/$total"
else
  echo "FAIL $passed/$total"; exit 1
fi
