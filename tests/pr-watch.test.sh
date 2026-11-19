#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016
# pr-watch fixtures (design U3). Prints PASS n/n; exits non-zero on any failure.
# Runs plugins/senioro/scripts/pr-watch.sh against a stub gh on PATH. The stub serves $STUB/<view|inline|issue>.<poll>
# (the highest poll number at or below the current one) and advances a fake clock by $STEP seconds per gh pr view, so
# PR_WATCH_INTERVAL=0 and PR_WATCH_CLOCK make every timed rule run in no wall time. Every gh call is logged and checked
# for writes at the end.
set -uo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
W="$REPO/plugins/senioro/scripts/pr-watch.sh"
[ -f "$W" ] || { echo "FAIL: $W missing"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq missing"; exit 1; }

T=$(mktemp -d) || { echo "FAIL: mktemp -d"; exit 1; }
T=$(cd "$T" && pwd -P)
trap 'rm -rf "${T:?}"' EXIT
mkdir -p "$T/bin"
cat > "$T/bin/gh" <<'STUB'
#!/usr/bin/env bash
d=$STUB
echo "$*" >> "$d/calls"
pick() {
  local n; n=$(cat "$d/poll")
  while [ "$n" -gt 0 ]; do [ -f "$d/$1.$n" ] && { cat "$d/$1.$n"; return 0; }; n=$((n - 1)); done
  [ "$1" != view ] || { echo "stub: no view fixture" >&2; return 1; }
  echo '[]'
}
case "$*" in
  "pr view "*)
    echo $(( $(cat "$d/poll") + 1 )) > "$d/poll"
    echo $(( $(cat "$d/clock") + ${STEP:-60} )) > "$d/clock"
    if [ -f "$d/fails" ] && [ "$(cat "$d/fails")" -gt 0 ]; then
      echo $(( $(cat "$d/fails") - 1 )) > "$d/fails"; echo "HTTP 502: Bad Gateway" >&2; exit 1
    fi
    pick view ;;
  "api --paginate repos/{owner}/{repo}/pulls/"*"/comments"*) pick inline ;;
  "api --paginate repos/{owner}/{repo}/issues/"*"/comments"*) pick issue ;;
  "run view "*" --log-failed") cat "$d/run.$3.log" ;;
  *) echo "stub: unexpected gh $*" >&2; exit 9 ;;
esac
STUB
chmod +x "$T/bin/gh"

SHA=abc1234def5678abc1234def5678abc1234def56
C0=1000000
total=0; passed=0; S=""; OUT=""; RC=0

# pass <case> [failure detail]: counts the case; an empty detail is a pass. Always returns 0, so "x && pass c || pass c d" is safe.
pass() {
  total=$((total + 1))
  if [ -z "${2:-}" ]; then passed=$((passed + 1)); else echo "FAIL case $1: $2"; fi
}

# new <name>: a fresh stub dir at poll 0 and clock C0; sets S.
new() { S="$T/$1"; mkdir -p "$S"; echo 0 > "$S/poll"; echo "$C0" > "$S/clock"; : > "$S/calls"; }

# cr <name> <status> [conclusion] [url]: one CheckRun; sc <context> <state>: one StatusContext.
cr() { jq -cn --arg n "$1" --arg s "$2" --arg c "${3:-}" --arg u "${4:-https://ci.example/$1}" \
  '{__typename: "CheckRun", name: $n, status: $s, conclusion: (if $c == "" then null else $c end), detailsUrl: $u}'; }
sc() { jq -cn --arg n "$1" --arg s "$2" '{__typename: "StatusContext", context: $n, state: $s, targetUrl: "https://ci.example/s"}'; }

# view <poll> <state> <head oid> <mergeable> <rollup json array> [reviews json array]: writes $S/view.<poll>.
view() {
  jq -n --arg s "$2" --arg o "$3" --arg m "$4" --argjson r "$5" --argjson rv "${6:-[]}" \
    '{number: 7, url: "https://github.com/o/r/pull/7", state: $s, headRefName: "feat/x", headRefOid: $o, baseRefName: "main", mergeable: $m,
      mergeStateStatus: (if $m == "CONFLICTING" then "DIRTY" else "CLEAN" end), statusCheckRollup: $r, reviews: $rv,
      commits: [{oid: "0000000", committedDate: "2026-11-18T09:00:00Z"}, {oid: $o, committedDate: "2026-11-18T10:00:00Z"}]}' \
    > "$S/view.$1"
}

# icom <id> <login> <updated_at> <body>, inl <id> <login> <updated_at> <body>: one issue or inline comment (REST shape).
icom() { jq -cn --argjson i "$1" --arg l "$2" --arg t "$3" --arg b "$4" \
  '{id: $i, user: {login: $l}, created_at: $t, updated_at: $t, html_url: "https://github.com/o/r/pull/7#issuecomment-\($i)", body: $b}'; }
inl() { jq -cn --argjson i "$1" --arg l "$2" --arg t "$3" --arg b "$4" \
  '{id: $i, user: {login: $l}, created_at: $t, updated_at: $t, path: "src/a.ts", line: 3, html_url: "https://github.com/o/r/pull/7#discussion_r\($i)", body: $b}'; }

# watch [survey file ...]: runs the watcher on PR 7 in $S; sets OUT, RC, POLLS.
watch() {
  OUT=$(cd "$S" && PATH="$T/bin:$PATH" STUB="$S" PR_WATCH_INTERVAL=0 PR_WATCH_CLOCK="$S/clock" \
    bash "$W" 7 "$SHA" "$S/seen.txt" "$S/digest.md" "$@" 2> "$S/stderr")
  RC=$?; POLLS=$(cat "$S/poll"); cat "$S/calls" >> "$T/allcalls"
}

# expect <case> <exit code> <polls or -> [stdout substring ...]: checks the run just made.
expect() {
  local c=$1 rc=$2 polls=$3 d="" s; shift 3
  [ "$RC" -eq "$rc" ] || d+="exit $RC, expected $rc ($(head -c 300 "$S/stderr")) "
  [ "$polls" = - ] || [ "$POLLS" -eq "$polls" ] || d+="$POLLS polls, expected $polls "
  for s in "$@"; do printf '%s' "$OUT" | grep -qF -- "$s" || d+="stdout lacks '$s' "; done
  case $rc in 0|3|4|5|6) [ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" -eq 3 ] || d+="stdout is not 3 lines: $OUT " ;; esac
  pass "$c" "$d"
}

# has <case> <fixed string> / lacks <case> <fixed string>: the digest holds it or not.
has() { grep -qF -- "$2" "$S/digest.md" && pass "$1" || pass "$1" "digest lacks '$2'"; }
lacks() { grep -qF -- "$2" "$S/digest.md" && pass "$1" "digest holds '$2'" || pass "$1"; }

PEND=$(cr build IN_PROGRESS); OK=$(cr build COMPLETED SUCCESS)

# 1 pending, then pass (a CheckRun and a StatusContext): settles at the 3-min grace, poll 4.
new c1
view 1 OPEN "$SHA" MERGEABLE "[$PEND,$(sc ci/legacy PENDING)]"
view 2 OPEN "$SHA" MERGEABLE "[$OK,$(sc ci/legacy SUCCESS)]"
watch; expect 1 0 4 "STATE OPEN settled mergeable=MERGEABLE" "CHECKS 2 pass / 0 fail / 0 pending" "NEW 0 reviews / 0 inline / 0 comments → $S/digest.md"
has 1b "- pass: build, ci/legacy"
# 1c the header carries the PR, head, base and state lines babysit-pr --digest reads.
d=""; for l in "PR: #7 https://github.com/o/r/pull/7" "HEAD: $SHA (feat/x), watched $SHA" "BASE: main" "STATE: OPEN, result settled" "MERGEABLE: MERGEABLE, mergeStateStatus CLEAN"; do
  grep -qF -- "$l" "$S/digest.md" || d+="no '$l' line; "; done; pass 1c "$d"

# 2 no checks at the first polls, present later: a surveyed check holds the watch past the grace until it registers.
new c2; echo "check build 5" > "$S/survey-ci.md"
view 1 OPEN "$SHA" MERGEABLE '[]'; view 6 OPEN "$SHA" MERGEABLE "[$PEND]"; view 7 OPEN "$SHA" MERGEABLE "[$OK]"
watch "$S/survey-ci.md" "$S/babysit-survey-*.md"; expect 2 0 7 "CHECKS 1 pass / 0 fail / 0 pending"
grep -qF 'survey file' "$S/stderr" && pass 2b || pass 2b "an unmatched survey glob was not reported as skipped"
# 3 no survey and no checks yet: no exit before the 3-min grace.
new c3; view 1 OPEN "$SHA" MERGEABLE '[]'
watch; expect 3 0 4 "CHECKS 0 pass / 0 fail / 0 pending"

# 4 a surveyed check that never registers: listed as missing after 2x its minutes (4 min, poll 5).
new c4; printf '%s\n' '# CI survey' 'check build 2' '- `check lint 2`' > "$S/survey-ci.md"
view 1 OPEN "$SHA" MERGEABLE "[$OK]"
watch "$S/survey-ci.md"; expect 4 0 5 "CHECKS 1 pass / 0 fail / 0 pending"
has 4b "- MISSING lint (surveyed, not registered after 4 min)"

# 5 a late comment-only bot: its pre-head comment does not count; settles on the poll it posts (poll 6).
new c5; echo "bot coderabbitai[bot] comment 3" > "$S/survey-rev.md"
view 1 OPEN "$SHA" MERGEABLE "[$OK]"
echo "[$(icom 1 'coderabbitai[bot]' 2026-11-18T09:30:00Z 'old summary')]" > "$S/issue.1"
echo "[$(icom 1 'coderabbitai[bot]' 2026-11-18T09:30:00Z 'old summary'),$(icom 2 'coderabbitai[bot]' 2026-11-18T10:05:00Z 'late review body')]" > "$S/issue.6"
watch "$S/survey-rev.md"; expect 5 0 6 "NEW 0 reviews / 0 inline / 2 comments"
has 5b "late review body"
# 6 a surveyed bot that never posts: settles 10 min after the checks finished (poll 11).
new c6; echo "bot coderabbitai[bot] comment 3" > "$S/survey-rev.md"
view 1 OPEN "$SHA" MERGEABLE "[$OK]"
watch "$S/survey-rev.md"; expect 6 0 11
has 6b "bots not heard from since the head commit: coderabbitai"
# 7 a review bot: the REST login "sonarcloud[bot]" matches the gh pr view login "sonarcloud" (posts at poll 2).
new c7; echo "bot sonarcloud[bot] review 2" > "$S/survey-rev.md"
view 1 OPEN "$SHA" MERGEABLE "[$OK]"
view 2 OPEN "$SHA" MERGEABLE "[$OK]" '[{"id":"PRR_1","author":{"login":"sonarcloud"},"body":"Quality Gate failed","state":"COMMENTED","submittedAt":"2026-11-18T10:02:00Z"}]'
watch "$S/survey-rev.md"; expect 7 0 4 "NEW 1 reviews / 0 inline / 0 comments"
has 7b "### review:PRR_1, sonarcloud, COMMENTED, 2026-11-18T10:02:00Z"

# 8 timeout: PR_WATCH_TIMEOUT_MIN=5 and a check pending forever -> exit 3 at 5 min (poll 6).
new c8; view 1 OPEN "$SHA" MERGEABLE "[$PEND]"
PR_WATCH_TIMEOUT_MIN=5 watch; expect 8 3 6 "STATE OPEN timeout" "timeout=5m" "CHECKS 0 pass / 0 fail / 1 pending"
has 8b "- PENDING build"
# 9-12 the timeout formula min(max(45, largest surveyed minutes + 15), 115), 10-min polls.
new c9; view 1 OPEN "$SHA" MERGEABLE "[$PEND]"
STEP=600 watch; expect "9 default 45" 3 6 "timeout=45m"
new c10; view 1 OPEN "$SHA" MERGEABLE "[$PEND]"; echo "check build 40" > "$S/s.md"
STEP=600 watch "$S/s.md"; expect "10 surveyed 40 -> 55" 3 7 "timeout=55m"
new c11; view 1 OPEN "$SHA" MERGEABLE "[$PEND]"; echo "check slow 200" > "$S/s.md"
STEP=600 watch "$S/s.md"; expect "11 cap at 115" 3 13 "timeout=115m" "elapsed=120m"
new c12; view 1 OPEN "$SHA" MERGEABLE "[$PEND]"
PR_WATCH_TIMEOUT_MIN=500 STEP=600 watch; expect "12 env cap at 115" 3 13 "timeout=115m"

# 13-16 closed, merged, head moved, conflicting: exit at once.
new c13; view 1 CLOSED "$SHA" MERGEABLE "[$PEND]"; watch; expect "13 closed" 4 1 "STATE CLOSED closed"
new c14; view 1 OPEN "$SHA" MERGEABLE "[$PEND]"; view 2 MERGED "$SHA" UNKNOWN "[$OK]"; watch; expect "14 merged" 4 2 "STATE MERGED merged"
new c15; view 1 OPEN "$SHA" MERGEABLE "[$PEND]"; view 3 OPEN fff0000 MERGEABLE "[$PEND]"; watch; expect "15 head moved" 5 3 "head-moved"
has 15b "HEAD: fff0000 (feat/x), watched $SHA"
new c16; view 1 OPEN "$SHA" CONFLICTING '[]'; watch; expect "16 conflict" 6 1 "conflict mergeable=CONFLICTING mergeStateStatus=DIRTY"

# 17-19 the seen file: one watch, a comment posted during the fix round, then a sticky comment edited in place.
new c17; view 1 OPEN "$SHA" MERGEABLE "[$OK]"
echo "[$(icom 1 alice 2026-11-18T10:01:00Z 'first comment')]" > "$S/issue.1"
echo "[$(inl 11 bob 2026-11-18T10:01:00Z 'inline nit')]" > "$S/inline.1"
watch; expect 17 0 4 "NEW 0 reviews / 1 inline / 1 comments"
has 17b "### inline:11, bob, src/a.ts:3, 2026-11-18T10:01:00Z"
has 17d "### comment:1, alice, 2026-11-18T10:01:00Z"
d=""; grep -qx 'comment:1 2026-11-18T10:01:00Z' "$S/seen.txt" || d+="comment:1 not recorded "
grep -qx 'inline:11 2026-11-18T10:01:00Z' "$S/seen.txt" || d+="inline:11 not recorded "; pass 17c "$d"
cp "$S/seen.txt" "$T/seen.keep"
new c18; cp "$T/seen.keep" "$S/seen.txt"; view 1 OPEN "$SHA" MERGEABLE "[$OK]"
echo "[$(icom 1 alice 2026-11-18T10:01:00Z 'first comment'),$(icom 2 carol 2026-11-18T10:03:00Z 'posted during the fix round')]" > "$S/issue.1"
echo "[$(inl 11 bob 2026-11-18T10:01:00Z 'inline nit')]" > "$S/inline.1"
watch; expect "18 between digests" 0 4 "NEW 0 reviews / 0 inline / 1 comments"
has 18b "posted during the fix round"; lacks "18c seen excluded" "first comment"; lacks "18d seen inline excluded" "inline nit"
cp "$S/seen.txt" "$T/seen.keep"
new c19; cp "$T/seen.keep" "$S/seen.txt"; view 1 OPEN "$SHA" MERGEABLE "[$OK]"
echo "[$(icom 1 alice 2026-11-18T10:20:00Z 'first comment, edited'),$(icom 2 carol 2026-11-18T10:03:00Z 'posted during the fix round')]" > "$S/issue.1"
watch; expect "19 sticky edited" 0 4 "NEW 0 reviews / 0 inline / 1 comments"
has 19b "first comment, edited"; lacks 19c "posted during the fix round"
grep -qx 'comment:1 2026-11-18T10:20:00Z' "$S/seen.txt" && pass 19d || pass 19d "comment:1 time not advanced"

# 20 the 1,500-character cut.
new c20; view 1 OPEN "$SHA" MERGEABLE "[$OK]"
X3000=$(printf 'x%.0s' $(seq 1 3000))
echo "[$(icom 5 dave 2026-11-18T10:01:00Z "$X3000")]" > "$S/issue.1"
watch; expect 20 0 4
run=$(grep -oE 'x+' "$S/digest.md" | awk '{ if (length > m) m = length } END { print m + 0 }')
[ "$run" -eq 1500 ] && pass 20b || pass 20b "longest body run $run, expected 1500"
has 20c "[cut at 1,500 characters]"

# 21 the failing Actions log: last 150 lines, one log per run, the failing check named with its link.
new c21; for i in $(seq 1 200); do echo "log line $i"; done > "$S/run.123.log"
U=https://github.com/o/r/actions/runs/123/job
view 1 OPEN "$SHA" MERGEABLE "[$(cr test COMPLETED FAILURE "$U/9"),$(cr e2e COMPLETED TIMED_OUT "$U/10"),$(cr lint COMPLETED SKIPPED)]"
watch; expect 21 0 4 "CHECKS 1 pass / 2 fail / 0 pending"
has 21b "- FAIL test $U/9"; has 21c "log line 200"; has 21d "log line 51"
grep -qx 'log line 50' "$S/digest.md" && pass 21e "line 50 is past the 150-line tail" || pass 21e
[ "$(grep -c '^run view 123 --log-failed$' "$S/calls")" -eq 1 ] && pass 21f || pass 21f "run 123 log not fetched exactly once"

# 22 the 60 KB cap: 60 comments of 1,500 characters and a failing log; what does not fit stays unseen for the next watch.
new c22; for i in $(seq 1 200); do echo "log line $i"; done > "$S/run.123.log"
B1500=$(printf 'y%.0s' $(seq 1 1500))
for i in $(seq 10 69); do icom "$i" bot "2026-11-18T10:$i:00Z" "$B1500"; done | jq -s . > "$S/issue.1"
view 1 OPEN "$SHA" MERGEABLE "[$(cr test COMPLETED FAILURE "$U/9")]"
watch; expect 22 0 4 "more next watch"
size=$(wc -c < "$S/digest.md" | tr -d ' ')
[ "$size" -le 61440 ] && pass 22b || pass 22b "digest is $size bytes"
has 22c "[truncated: the digest is capped at 60 KB"
n1=$(grep -c '^### comment:' "$S/digest.md"); s1=$(wc -l < "$S/seen.txt" | tr -d ' ')
[ "$n1" -gt 0 ] && [ "$n1" -lt 60 ] && [ "$s1" -eq "$n1" ] && pass 22d || pass 22d "$n1 comments in the digest, $s1 recorded"
echo 0 > "$S/poll"; echo "$C0" > "$S/clock"; watch
n2=$(grep -c '^### comment:' "$S/digest.md")
[ $((n1 + n2)) -eq 60 ] && pass 22e || pass 22e "first watch $n1 + second $n2 != 60"

# 23 exit 1: gh fails on 3 polls in a row; 24 one failed poll is retried.
new c23; view 1 OPEN "$SHA" MERGEABLE "[$OK]"; echo 99 > "$S/fails"
watch; expect "23 gh error" 1 3 "STATE ERROR gh failed 3 polls in a row: HTTP 502"
new c24; view 1 OPEN "$SHA" MERGEABLE "[$OK]"; echo 1 > "$S/fails"
watch; expect "24 gh retry" 0 4 "STATE OPEN settled"

# 25 exit 2: usage errors.
d=""
for a in "" "7" "x7 $SHA s d" "7 nothex s d" "7 abc s d"; do
  # shellcheck disable=SC2086
  PATH="$T/bin:$PATH" bash "$W" $a >/dev/null 2>&1; r=$?; [ "$r" -eq 2 ] || d+="args '$a' exit $r; "
done
PR_WATCH_INTERVAL=x bash "$W" 7 "$SHA" "$T/s" "$T/d" >/dev/null 2>&1; r=$?; [ "$r" -eq 2 ] || d+="bad interval exit $r; "
PR_WATCH_TIMEOUT_MIN=0 bash "$W" 7 "$SHA" "$T/s" "$T/d" >/dev/null 2>&1; r=$?; [ "$r" -eq 2 ] || d+="bad timeout exit $r; "
pass "25 usage" "$d"

# 26 read-only: no gh call is a write.
w=$(grep -E -- '(^| )(-X|--method|-f|-F|--field|--raw-field|--input)( |=|$)|^(pr|issue) (comment|review|merge|close|edit)' "$T/allcalls")
[ -z "$w" ] && pass "26 read-only" || pass "26 read-only" "write calls: $w"
grep -qvE '^(pr view 7 |api --paginate repos/\{owner\}/\{repo\}/(pulls|issues)/7/comments|run view 123 --log-failed$)' "$T/allcalls" \
  && pass "26b known calls" "unexpected call: $(grep -vE '^(pr view|api --paginate|run view)' "$T/allcalls" | head -n 1)" || pass "26b known calls"

# 27 the script is executable.
[ -x "$W" ] && pass 27 || pass 27 "pr-watch.sh is not executable"

if [ "$passed" -eq "$total" ]; then
  echo "PASS $passed/$total"
else
  echo "FAIL $passed/$total"; exit 1
fi
