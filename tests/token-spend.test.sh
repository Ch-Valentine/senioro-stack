#!/usr/bin/env bash
# token-spend fixtures (spec 001 #7, section 7; spec 002 U2, #11, #18). Prints PASS n/n; exits non-zero on any failure.
# Runs plugins/senioro/scripts/token-spend.sh on tests/fixtures/token-spend/session.jsonl (TL, two seats, one
# workflow agent) and on tests/fixtures/token-spend/handback/session.jsonl (TL, three seats of three models, a
# foreground and a background hand-back, cut from a real session) and compares its exact stdout; also checks the
# exit codes and the unpriced-model warning. The --usage cases run on tests/fixtures/token-spend/usage/session.jsonl
# (TL, three seats, two workflow agents; synthetic) and on sessions built in a temp dir.
set -uo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$REPO/plugins/senioro/scripts/token-spend.sh"
FIX="$REPO/tests/fixtures/token-spend/session.jsonl"
HB="$REPO/tests/fixtures/token-spend/handback/session.jsonl"
US="$REPO/tests/fixtures/token-spend/usage/session.jsonl"
[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT missing"; exit 1; }
[ -f "$FIX" ] || { echo "FAIL: $FIX missing"; exit 1; }
[ -f "$HB" ] || { echo "FAIL: $HB missing"; exit 1; }
[ -f "$US" ] || { echo "FAIL: $US missing"; exit 1; }
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
#   The seats are claude-sonnet-4-5 (3/3.75/6/0.30/15 per MTok): write a1 400000 + a3 600000 + b1 100000 at 3.75 and
#   a4 100000 at 3.75 + 200000 at 6 = 5.70; read (400000 + 100000) x 0.30 = 0.15; output 47600 x 15 = 0.714; input
#   1500 x 3 = 0.0045; usd 6.5685. Resume a3: 600000 x 3.75 = 2.25. Gap a4: 0.375 + 1.2 = 1.575.
run "$FIX" --until 2026-01-01T01:00:00Z
want 1 0 "TL calls=2 usd=7.10 write=5.00 read=0.20 output=1.50 thinking=25000
seats calls=6 usd=6.57 write=5.70 read=0.15 output=0.71 thinking=28000
workflow calls=2 usd=1.19 write=1.00 read=0.08 output=0.11 thinking=8000
model opus calls=2 usd=7.10 write=5.00 read=0.20 output=1.50 thinking=25000
model sonnet calls=6 usd=6.57 write=5.70 read=0.15 output=0.71 thinking=28000
model haiku calls=2 usd=1.19 write=1.00 read=0.08 output=0.11 thinking=8000
model other calls=0 usd=0.00 write=0.00 read=0.00 output=0.00 thinking=0
seats: 2 (haiku 0, sonnet 2, opus 0)
resumes n=1 tokens=600000 usd=2.25
gaps n=1 tokens=300000 usd=1.58
fetch calls=5 chars=6550 docs_chars=4500 docs_curl_nogrep=2
runreads n=6 unnamed=2 chars=500
tl_bigreads n=1 chars=21000"

# 2 no cutoff: t4 and a5 count (a5 is a second resume); the late message names other.md, so r2 is named and r7 unnamed.
#   a5 adds write 700000 x 3.75 = 2.625 (8.325) and output 1000 x 15 = 0.015 (0.729): usd 9.2085; resumes 2.25 + 2.625.
run "$FIX"
want 2 0 "TL calls=3 usd=11.78 write=9.50 read=0.20 output=1.68 thinking=25000
seats calls=7 usd=9.21 write=8.33 read=0.15 output=0.73 thinking=28000
workflow calls=2 usd=1.19 write=1.00 read=0.08 output=0.11 thinking=8000
model opus calls=3 usd=11.78 write=9.50 read=0.20 output=1.68 thinking=25000
model sonnet calls=7 usd=9.21 write=8.33 read=0.15 output=0.73 thinking=28000
model haiku calls=2 usd=1.19 write=1.00 read=0.08 output=0.11 thinking=8000
model other calls=0 usd=0.00 write=0.00 read=0.00 output=0.00 thinking=0
seats: 2 (haiku 0, sonnet 2, opus 0)
resumes n=2 tokens=1300000 usd=4.88
gaps n=1 tokens=300000 usd=1.58
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
model other calls=1 usd=0.00 write=0.00 read=0.00 output=0.00 thinking=0
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
#   usd (rates in the script's ptab): opus-5-5 TL 0.0428504 + 0.0681070 before the split and 0.1034412 after, opus
#   seat 0.0677514; sonnet-5-5 seat: input 4 x 2 + write 6749 x 2.5 + read 4850 x 0.10 + output 1180 x 10 = 0.0291655;
#   haiku-5-5 seat: input 4 x 0.10 + write 8415 x 0.125 + read 4841 x 0.01 + output 1597 x 0.50 = 0.0018992.
#   spec 0.1420221, build 0.1711926, opus 0.2821500, sonnet 0.0291655, haiku 0.0018992; seats write 0.0700190, read
#   0.0019138, output 0.0268585, usd 0.0988161.

# 8 no split: group lines, per-model lines and the seat count (one haiku, one sonnet, one opus seat)
run "$HB"
want 8 0 "TL calls=3 usd=0.21 write=0.04 read=0.07 output=0.10 thinking=2169
seats calls=6 usd=0.10 write=0.07 read=0.00 output=0.03 thinking=1146
workflow calls=0 usd=0.00 write=0.00 read=0.00 output=0.00 thinking=0
model opus calls=5 usd=0.28 write=0.10 read=0.07 output=0.12 thinking=2481
model sonnet calls=2 usd=0.03 write=0.02 read=0.00 output=0.01 thinking=330
model haiku calls=2 usd=0.00 write=0.00 read=0.00 output=0.00 thinking=504
model other calls=0 usd=0.00 write=0.00 read=0.00 output=0.00 thinking=0
seats: 3 (haiku 1, sonnet 1, opus 1)
resumes n=0 tokens=0 usd=0.00
gaps n=0 tokens=0 usd=0.00
fetch calls=0 chars=0 docs_chars=0 docs_curl_nogrep=0
runreads n=0 unnamed=0 chars=0
tl_bigreads n=0 chars=0"

# 9 --split between the two phases: exactly the retro's three lines
run "$HB" --split 2026-11-07T14:00:00Z
want 9 0 "spec: wall 104.1 min, seats 2.5 min, 205686 tokens, \$0.14 API-equivalent
build: wall 141.5 min, seats 22.4 min, 179448 tokens, \$0.17 API-equivalent
seats: 3 (haiku 1, sonnet 1, opus 1)"

# 10 --phase spec and 11 --phase build: the whole session is one phase, the other prints zeros
run "$HB" --phase spec
want 10 0 "spec: wall 245.6 min, seats 24.9 min, 385134 tokens, \$0.31 API-equivalent
build: wall 0.0 min, seats 0.0 min, 0 tokens, \$0.00 API-equivalent
seats: 3 (haiku 1, sonnet 1, opus 1)"
run "$HB" --phase build
want 11 0 "spec: wall 0.0 min, seats 0.0 min, 0 tokens, \$0.00 API-equivalent
build: wall 245.6 min, seats 24.9 min, 385134 tokens, \$0.31 API-equivalent
seats: 3 (haiku 1, sonnet 1, opus 1)"

# 12 --split with --until 13:00: only the two foreground hand-backs and the seats started before the cutoff remain;
#   wall ends at the 12:40:53.745 hand-back (25.0 min); the opus seat has no request left, so it is not counted
run "$HB" --split 2026-11-07T14:00:00Z --until 2026-11-07T13:00:00Z
want 12 0 "spec: wall 25.0 min, seats 2.5 min, 205686 tokens, \$0.14 API-equivalent
build: wall 0.0 min, seats 0.0 min, 0 tokens, \$0.00 API-equivalent
seats: 2 (haiku 1, sonnet 1, opus 0)"

# 13 the duration field renamed (a missing field) and a report that only quotes "duration_ms: 99999" outside a
#   <usage> block: seats minutes print n/a, the rest stays
mkdir -p "$T/hb13" && cp -R "$REPO/tests/fixtures/token-spend/handback/session" "$T/hb13/session"
sed 's/duration_ms/dur_ms/g' "$HB" > "$T/hb13/session.jsonl"
printf '%s\n' '{"type":"user","timestamp":"2026-11-07T16:21:28.000Z","message":{"role":"user","content":"the report said duration_ms: 99999"}}' >> "$T/hb13/session.jsonl"
run "$T/hb13/session.jsonl" --split 2026-11-07T14:00:00Z
want 13 0 "spec: wall 104.1 min, seats n/a min, 205686 tokens, \$0.14 API-equivalent
build: wall 141.5 min, seats n/a min, 179448 tokens, \$0.17 API-equivalent
seats: 3 (haiku 1, sonnet 1, opus 1)"

# 14-17 --split and --phase together, a malformed --split, an unknown phase, a missing value -> exit 2, usage message
run "$HB" --split 2026-11-07T14:00:00Z --phase spec; want 14 2 "" "usage:"
run "$HB" --split "2026-11-07 14:00:00"; want 15 2 "" "usage:"
run "$HB" --phase deploy; want 16 2 "" "usage:"
run "$HB" --phase; want 17 2 "" "usage:"

# req <id> <model> <usage JSON>: one assistant line at 2026-01-01T00:00:00Z.
req() { printf '{"type":"assistant","timestamp":"2026-01-01T00:00:00Z","requestId":"%s","message":{"model":"%s","usage":%s}}\n' "$1" "$2" "$3"; }
# M1: 1,000,000 tokens of each kind (input, 5m write, 1h write, cache read, output), so usd is the sum of a row's rates.
M1='{"input_tokens":1000000,"cache_creation_input_tokens":2000000,"cache_read_input_tokens":1000000,"output_tokens":1000000,"cache_creation":{"ephemeral_5m_input_tokens":1000000,"ephemeral_1h_input_tokens":1000000}}'
Z='usd=0.00 write=0.00 read=0.00 output=0.00 thinking=0'
ZT="resumes n=0 tokens=0 usd=0.00
gaps n=0 tokens=0 usd=0.00
fetch calls=0 chars=0 docs_chars=0 docs_curl_nogrep=0
runreads n=0 unnamed=0 chars=0
tl_bigreads n=0 chars=0"

# 18 one request each of fable-5-2 (8 + 10 + 16 + 0.20 + 40 = 74.20), opus-5 (5 + 6.25 + 10 + 0.50 + 25 = 46.75) and
#   mythos-5-2 (the fable-5-2 rates, 74.20), priced from the table; fable and mythos are model other.
{ req f1 claude-fable-5-2 "$M1"; req f2 claude-opus-5 "$M1"; req f3 claude-mythos-5-2 "$M1"; } > "$T/new.jsonl"
run "$T/new.jsonl"
want 18 0 "TL calls=3 usd=195.15 write=68.25 read=0.90 output=105.00 thinking=0
seats calls=0 $Z
workflow calls=0 $Z
model opus calls=1 usd=46.75 write=16.25 read=0.50 output=25.00 thinking=0
model sonnet calls=0 $Z
model haiku calls=0 $Z
model other calls=2 usd=148.40 write=52.00 read=0.40 output=80.00 thinking=0
seats: 0 (haiku 0, sonnet 0, opus 0)
$ZT"

# 19 a dated id: claude-haiku-4-5-20251001 is haiku-4-5 (input 1 + read 0.10 + output 5 = 6.10), with no warning; the
#   haiku-5-5 fallback would give 3.05 and a warning.
req d1 claude-haiku-4-5-20251001 '{"input_tokens":1000000,"cache_read_input_tokens":1000000,"output_tokens":1000000}' > "$T/dated.jsonl"
run "$T/dated.jsonl"
want 19 0 "TL calls=1 usd=6.10 write=0.00 read=0.10 output=5.00 thinking=0
seats calls=0 $Z
workflow calls=0 $Z
model opus calls=0 $Z
model sonnet calls=0 $Z
model haiku calls=1 usd=6.10 write=0.00 read=0.10 output=5.00 thinking=0
model other calls=0 $Z
seats: 0 (haiku 0, sonnet 0, opus 0)
$ZT"

# 20 haiku-5-5 long context: the TL request's prompt is 40,000 input + 30,000 read + 30,000 write = 100,000 tokens (base
#   rates: 0.004 + 0.0003 + 0.00375 + output 1M x 0.50 = 0.50805); the seat's is 100,001 (40,001 input; long rates:
#   0.0200005 + 0.0015 + 0.01875 + 1M x 2.50 = 2.5402505). Both: write 0.0225, read 0.0018, usd 3.0483005.
mkdir -p "$T/hk/s/subagents"
req h1 claude-haiku-5-5 '{"input_tokens":40000,"cache_creation_input_tokens":30000,"cache_read_input_tokens":30000,"output_tokens":1000000}' > "$T/hk/s.jsonl"
req h2 claude-haiku-5-5 '{"input_tokens":40001,"cache_creation_input_tokens":30000,"cache_read_input_tokens":30000,"output_tokens":1000000}' > "$T/hk/s/subagents/agent-h2.jsonl"
run "$T/hk/s.jsonl"
want 20 0 "TL calls=1 usd=0.51 write=0.00 read=0.00 output=0.50 thinking=0
seats calls=1 usd=2.54 write=0.02 read=0.00 output=2.50 thinking=0
workflow calls=0 $Z
model opus calls=0 $Z
model sonnet calls=0 $Z
model haiku calls=2 usd=3.05 write=0.02 read=0.00 output=3.00 thinking=0
model other calls=0 $Z
seats: 1 (haiku 1, sonnet 0, opus 0)
$ZT"

# 21 an id of a known family that is not in the table: priced as that family's newest row (opus-5-5, input 1M = 4.00),
#   named on stderr.
req o1 claude-opus-9-9 '{"input_tokens":1000000}' > "$T/approx.jsonl"
run "$T/approx.jsonl"
want 21 0 "TL calls=1 usd=4.00 write=0.00 read=0.00 output=0.00 thinking=0
seats calls=0 $Z
workflow calls=0 $Z
model opus calls=1 usd=4.00 write=0.00 read=0.00 output=0.00 thinking=0
model sonnet calls=0 $Z
model haiku calls=0 $Z
model other calls=0 $Z
seats: 0 (haiku 0, sonnet 0, opus 0)
$ZT" "1 requests of model claude-opus-9-9 priced approximately as opus-5-5"

# 22 invariant: the four model lines add up to the three group lines (calls and usd). TL opus-5-5 output 1M (20) and
#   fable-5-2 input 1M (8); seat sonnet-5-5 read 1M (0.10) and mythos-5-1 output 1M (50); workflow haiku-4-5 output 1M
#   (5) and claude-x-1 (unpriced, 0): 83.10 in all.
mkdir -p "$T/inv/s/subagents/workflows/wf_1"
{ req i1 claude-opus-5-5 '{"output_tokens":1000000}'; req i2 claude-fable-5-2 '{"input_tokens":1000000}'; } > "$T/inv/s.jsonl"
{ req i3 claude-sonnet-5-5 '{"cache_read_input_tokens":1000000}'; req i4 claude-mythos-5-1 '{"output_tokens":1000000}'; } > "$T/inv/s/subagents/agent-i3.jsonl"
{ req i5 claude-haiku-4-5 '{"output_tokens":1000000}'; req i6 claude-x-1 '{"output_tokens":1000000}'; } > "$T/inv/s/subagents/workflows/wf_1/agent-i5.jsonl"
run "$T/inv/s.jsonl"
# sums <sed range>: total calls and usd cents of those stdout lines.
sums() { printf '%s\n' "$OUT" | sed -n "$1" | awk '{ for (i = 1; i <= NF; i++) { split($i, f, "="); if (f[1] == "calls") n += f[2]; if (f[1] == "usd") s += f[2] * 100 } } END { printf "%d %.0f", n, s }'; }
d=""
[ "$RC" -eq 0 ] || d+="exit $RC "
[ "$(sums '1,3p')" = "6 8310" ] || d+="group lines sum to '$(sums '1,3p')', expected '6 8310' "
[ "$(sums '4,7p')" = "6 8310" ] || d+="model lines sum to '$(sums '4,7p')', expected '6 8310' "
case "$ERR" in *"1 requests of model claude-x-1 have no price"*) ;; *) d+="stderr lacks the claude-x-1 warning: $ERR " ;; esac
pass 22 "$d"

# The --usage fixture, by hand (USD per MTok in the script's ptab):
#   TL: t1 (two lines, the last counts) opus-5-5 input 1000 x 4 + 1h write 100000 x 8 + output 2000 x 20 = 0.844; a
#     compact_boundary; t2 opus-5-5 read 200000 x 0.20 + output 5000 x 20 = 0.14 at speed fast; t3 haiku-5-5 input
#     2000 x 0.10 + output 1000 x 0.50 = 0.0007; t4 <synthetic> is not counted.
#   seat aaaa1111 (meta demo:architect; its description holds "|", a newline and backticks): a1 opus-5-5 input 10 x 4 +
#     unsplit write 200000 x 5 + output 10000 x 20 = 1.20004; a2 fable-5-2 read 100000 x 0.20 + output 20000 x 40 = 0.82.
#   seat bbbb2222 (no meta, attributionAgent demo:verifier): b1 sonnet-5-5 input 100 x 2 + 5m write 50000 x 2.5 + read
#     100000 x 0.10 + output 3000 x 10 = 0.1652; b2 claude-sonnet-9-9 (priced as sonnet-5-5) output 10000 x 10 = 0.10;
#     b3 claude-x-1 (unpriced) 0.
#   seat cccc3333 (meta demo:architect) at 10:41: c1 opus-5-5 output 30000 x 20 = 0.60.
#   workflow dddd4444 (meta demo:implementer, phase Build): d1 opus-5-5 1h write 50000 x 8 + output 5000 x 20 = 0.50.
#   workflow eeee5555 (no meta, no attributionAgent): e1 haiku-4-5 input 50000 x 1 + output 10000 x 5 = 0.10.
#   Total 4.46994: TL 0.9847 (22.0%), seats 2.88524 (64.5%), workflow 0.60 (13.4%). The sonnet-9-9 and haiku-4-5 rows tie
#   at 0.10 and go by where (seat first). The top 5 drops eeee5555.
# 23 the full block: a seat without meta (attributionAgent), a workflow agent without meta ((unknown)), one agent type
#   on two models and one agent on two models (the "+" join), equal rows, the description escaped and cut to 40
#   characters, the unpriced and approximate ids, a compaction and a non-standard speed in the footer.
run --usage "$US"
E=$(cat <<'EOF'
## Usage 2026-03-01 10:45 UTC, session session
Estimated at API list prices from this session's transcripts; not a bill. Per-model totals: /usage.
TL main loop $0.98 (22.0%) · seats $2.89 (64.5%) · workflow agents $0.60 (13.4%) · total $4.47, 11 requests

| where | agent type | model | agents | requests | est. $ | share |
|---|---|---|---|---|---|---|
| seat | demo:architect | opus-5-5 | 2 | 2 | 1.80 | 40.3% |
| TL | (TL main loop) | opus-5-5 | 1 | 2 | 0.98 | 22.0% |
| seat | demo:architect | fable-5-2 | 1 | 1 | 0.82 | 18.3% |
| workflow | demo:implementer | opus-5-5 | 1 | 1 | 0.50 | 11.2% |
| seat | demo:verifier | sonnet-5-5 | 1 | 1 | 0.17 | 3.7% |
| seat | demo:verifier | sonnet-9-9 | 1 | 1 | 0.10 | 2.2% |
| workflow | (unknown) | haiku-4-5 | 1 | 1 | 0.10 | 2.2% |
| TL | (TL main loop) | haiku-5-5 | 1 | 1 | 0.00 | 0.0% |
| seat | demo:verifier | x-1 | 1 | 1 | 0.00 | 0.0% |

| top spender | where | agent type | model | for what | est. $ |
|---|---|---|---|---|---|
| seat aaaa1111 | seat | demo:architect | opus-5-5+fable-5-2 | Design the \| widget with  ticks  and a l | 2.02 |
| TL main loop | TL | (TL main loop) | opus-5-5+haiku-5-5 |  | 0.98 |
| seat cccc3333 | seat | demo:architect | opus-5-5 | Second design | 0.60 |
| workflow dddd4444 | workflow | demo:implementer | opus-5-5 | Build: B1 | 0.50 |
| seat bbbb2222 | seat | demo:verifier | sonnet-5-5+sonnet-9-9+x-1 |  | 0.27 |

Not in transcripts, so not counted: 1 compactions, title and web-fetch-summary calls. Priced approximately: sonnet-9-9 1.
Unpriced ($0): x-1 1. Non-standard speed or region: 1 requests, priced as standard. This session id only; this retro's seat is excluded.
EOF
)
want 23 0 "$E" "1 requests of model claude-sonnet-9-9 priced approximately as sonnet-5-5"

# 24 --usage --until 10:40: t3 and c1 are cut, so seat cccc3333 has no counted request and drops out. Total 3.86924:
#   TL 0.984 (25.4%), seats 2.28524 (59.1%), workflow 0.60 (15.5%).
run --usage "$US" --until 2026-03-01T10:40:00Z
E=$(cat <<'EOF'
## Usage 2026-03-01 10:31 UTC, session session
Estimated at API list prices from this session's transcripts; not a bill. Per-model totals: /usage.
TL main loop $0.98 (25.4%) · seats $2.29 (59.1%) · workflow agents $0.60 (15.5%) · total $3.87, 9 requests

| where | agent type | model | agents | requests | est. $ | share |
|---|---|---|---|---|---|---|
| seat | demo:architect | opus-5-5 | 1 | 1 | 1.20 | 31.0% |
| TL | (TL main loop) | opus-5-5 | 1 | 2 | 0.98 | 25.4% |
| seat | demo:architect | fable-5-2 | 1 | 1 | 0.82 | 21.2% |
| workflow | demo:implementer | opus-5-5 | 1 | 1 | 0.50 | 12.9% |
| seat | demo:verifier | sonnet-5-5 | 1 | 1 | 0.17 | 4.3% |
| seat | demo:verifier | sonnet-9-9 | 1 | 1 | 0.10 | 2.6% |
| workflow | (unknown) | haiku-4-5 | 1 | 1 | 0.10 | 2.6% |
| seat | demo:verifier | x-1 | 1 | 1 | 0.00 | 0.0% |

| top spender | where | agent type | model | for what | est. $ |
|---|---|---|---|---|---|
| seat aaaa1111 | seat | demo:architect | opus-5-5+fable-5-2 | Design the \| widget with  ticks  and a l | 2.02 |
| TL main loop | TL | (TL main loop) | opus-5-5 |  | 0.98 |
| workflow dddd4444 | workflow | demo:implementer | opus-5-5 | Build: B1 | 0.50 |
| seat bbbb2222 | seat | demo:verifier | sonnet-5-5+sonnet-9-9+x-1 |  | 0.27 |
| workflow eeee5555 | workflow | (unknown) | haiku-4-5 |  | 0.10 |

Not in transcripts, so not counted: 1 compactions, title and web-fetch-summary calls. Priced approximately: sonnet-9-9 1.
Unpriced ($0): x-1 1. Non-standard speed or region: 1 requests, priced as standard. This session id only; this retro's seat is excluded.
EOF
)
want 24 0 "$E" "1 requests of model claude-x-1 have no price"

# 25 --until before every request: the header and "No counted requests.", exit 0
run --usage "$US" --until 2026-03-01T09:00:00Z
want 25 0 "## Usage n/a UTC, session session
No counted requests."

# 26 a TL-only session with no subagents dir: opus-5-5 output 100000 x 20 = 2.00
req u1 claude-opus-5-5 '{"output_tokens":100000}' > "$T/only.jsonl"
run --usage "$T/only.jsonl"
E=$(cat <<'EOF'
## Usage 2026-01-01 00:00 UTC, session only
Estimated at API list prices from this session's transcripts; not a bill. Per-model totals: /usage.
TL main loop $2.00 (100.0%) · seats $0.00 (0.0%) · workflow agents $0.00 (0.0%) · total $2.00, 1 requests

| where | agent type | model | agents | requests | est. $ | share |
|---|---|---|---|---|---|---|
| TL | (TL main loop) | opus-5-5 | 1 | 1 | 2.00 | 100.0% |

| top spender | where | agent type | model | for what | est. $ |
|---|---|---|---|---|---|
| TL main loop | TL | (TL main loop) | opus-5-5 |  | 2.00 |

Not in transcripts, so not counted: 0 compactions, title and web-fetch-summary calls. Priced approximately: none.
Unpriced ($0): none. Non-standard speed or region: 0 requests, priced as standard. This session id only; this retro's seat is excluded.
EOF
)
want 26 0 "$E"

# 27 equal est. $: four agents at 0.10 each (sonnet-5-5 output 10000 x 10, haiku-4-5 output 20000 x 5). Rows go by
#   where, then agent type, then model; spenders by id.
mkdir -p "$T/tie/s/subagents/workflows/wf_1"
req v0 claude-opus-5-5 '{"output_tokens":100000}' > "$T/tie/s.jsonl"
req v1 claude-sonnet-5-5 '{"output_tokens":10000}' > "$T/tie/s/subagents/agent-b1.jsonl"
req v2 claude-sonnet-5-5 '{"output_tokens":10000}' > "$T/tie/s/subagents/agent-a1.jsonl"
req v3 claude-haiku-4-5 '{"output_tokens":20000}' > "$T/tie/s/subagents/agent-a2.jsonl"
req v4 claude-sonnet-5-5 '{"output_tokens":10000}' > "$T/tie/s/subagents/workflows/wf_1/agent-c1.jsonl"
printf '%s\n' '{"agentType":"alpha","description":"tie b1"}' > "$T/tie/s/subagents/agent-b1.meta.json"
printf '%s\n' '{"agentType":"beta","description":"tie a1"}' > "$T/tie/s/subagents/agent-a1.meta.json"
printf '%s\n' '{"agentType":"beta","description":"tie a2"}' > "$T/tie/s/subagents/agent-a2.meta.json"
printf '%s\n' '{"agentType":"alpha","description":"c1","workflowPhase":"Build"}' > "$T/tie/s/subagents/workflows/wf_1/agent-c1.meta.json"
run --usage "$T/tie/s.jsonl"
E=$(cat <<'EOF'
## Usage 2026-01-01 00:00 UTC, session s
Estimated at API list prices from this session's transcripts; not a bill. Per-model totals: /usage.
TL main loop $2.00 (83.3%) · seats $0.30 (12.5%) · workflow agents $0.10 (4.2%) · total $2.40, 5 requests

| where | agent type | model | agents | requests | est. $ | share |
|---|---|---|---|---|---|---|
| TL | (TL main loop) | opus-5-5 | 1 | 1 | 2.00 | 83.3% |
| seat | alpha | sonnet-5-5 | 1 | 1 | 0.10 | 4.2% |
| seat | beta | haiku-4-5 | 1 | 1 | 0.10 | 4.2% |
| seat | beta | sonnet-5-5 | 1 | 1 | 0.10 | 4.2% |
| workflow | alpha | sonnet-5-5 | 1 | 1 | 0.10 | 4.2% |

| top spender | where | agent type | model | for what | est. $ |
|---|---|---|---|---|---|
| TL main loop | TL | (TL main loop) | opus-5-5 |  | 2.00 |
| seat a1 | seat | beta | sonnet-5-5 | tie a1 | 0.10 |
| seat a2 | seat | beta | haiku-4-5 | tie a2 | 0.10 |
| seat b1 | seat | alpha | sonnet-5-5 | tie b1 | 0.10 |
| workflow c1 | workflow | alpha | sonnet-5-5 | Build: c1 | 0.10 |

Not in transcripts, so not counted: 0 compactions, title and web-fetch-summary calls. Priced approximately: none.
Unpriced ($0): none. Non-standard speed or region: 0 requests, priced as standard. This session id only; this retro's seat is excluded.
EOF
)
want 27 0 "$E"

# 28 more than 12 rows: TL opus-5-5 output 1M (20.00) and 14 seats of types t01-t14, seat k at sonnet-5-5 output
#   k x 10000 (0.10 k). Total 30.50; 11 rows are shown and t04-t01 (1.00) fold into one row. At most 30 lines.
mkdir -p "$T/fold/s/subagents"
req f0 claude-opus-5-5 '{"output_tokens":1000000}' > "$T/fold/s.jsonl"
for k in $(seq 1 14); do
  printf -v kk '%02d' "$k"
  req "f$kk" claude-sonnet-5-5 "{\"output_tokens\":$((k * 10000))}" > "$T/fold/s/subagents/agent-s$kk.jsonl"
  printf '{"agentType":"t%s","description":"fold %s"}\n' "$kk" "$kk" > "$T/fold/s/subagents/agent-s$kk.meta.json"
done
run --usage "$T/fold/s.jsonl"
E=$(cat <<'EOF'
## Usage 2026-01-01 00:00 UTC, session s
Estimated at API list prices from this session's transcripts; not a bill. Per-model totals: /usage.
TL main loop $20.00 (65.6%) · seats $10.50 (34.4%) · workflow agents $0.00 (0.0%) · total $30.50, 15 requests

| where | agent type | model | agents | requests | est. $ | share |
|---|---|---|---|---|---|---|
| TL | (TL main loop) | opus-5-5 | 1 | 1 | 20.00 | 65.6% |
| seat | t14 | sonnet-5-5 | 1 | 1 | 1.40 | 4.6% |
| seat | t13 | sonnet-5-5 | 1 | 1 | 1.30 | 4.3% |
| seat | t12 | sonnet-5-5 | 1 | 1 | 1.20 | 3.9% |
| seat | t11 | sonnet-5-5 | 1 | 1 | 1.10 | 3.6% |
| seat | t10 | sonnet-5-5 | 1 | 1 | 1.00 | 3.3% |
| seat | t09 | sonnet-5-5 | 1 | 1 | 0.90 | 3.0% |
| seat | t08 | sonnet-5-5 | 1 | 1 | 0.80 | 2.6% |
| seat | t07 | sonnet-5-5 | 1 | 1 | 0.70 | 2.3% |
| seat | t06 | sonnet-5-5 | 1 | 1 | 0.60 | 2.0% |
| seat | t05 | sonnet-5-5 | 1 | 1 | 0.50 | 1.6% |
| (other: 4 rows) |  |  | 4 | 4 | 1.00 | 3.3% |

| top spender | where | agent type | model | for what | est. $ |
|---|---|---|---|---|---|
| TL main loop | TL | (TL main loop) | opus-5-5 |  | 20.00 |
| seat s14 | seat | t14 | sonnet-5-5 | fold 14 | 1.40 |
| seat s13 | seat | t13 | sonnet-5-5 | fold 13 | 1.30 |
| seat s12 | seat | t12 | sonnet-5-5 | fold 12 | 1.20 |
| seat s11 | seat | t11 | sonnet-5-5 | fold 11 | 1.10 |

Not in transcripts, so not counted: 0 compactions, title and web-fetch-summary calls. Priced approximately: none.
Unpriced ($0): none. Non-standard speed or region: 0 requests, priced as standard. This session id only; this retro's seat is excluded.
EOF
)
want 28 0 "$E"
n=$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')
d=""; [ "$n" -le 30 ] || d="$n lines, more than 30"
pass 29 "$d"

# 30-31 --usage with --split or --phase -> exit 2, usage message
run --usage "$US" --split 2026-03-01T10:00:00Z; want 30 2 "" "usage:"
run --usage "$US" --phase spec; want 31 2 "" "usage:"

if [ "$passed" -eq "$total" ] && [ "$total" -eq 31 ]; then
  echo "PASS $passed/$total"
else
  echo "FAIL $passed/$total"; exit 1
fi
