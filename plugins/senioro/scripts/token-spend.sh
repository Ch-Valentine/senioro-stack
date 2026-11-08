#!/usr/bin/env bash
# Token spend of one Claude Code session (spec 001 #7, section 5 definitions), for re-measuring the TL workflow.
# Usage: token-spend.sh <session.jsonl> [--until <ISO-8601 UTC>] [--split <ISO-8601 UTC> | --phase spec|build]
#   Reads the session file (TL), <session>/subagents/agent-*.jsonl (seats) and
#   <session>/subagents/workflows/*/agent-*.jsonl (workflow agents). Prints 12 lines:
#   <TL|seats|workflow> calls=N usd=X write=X read=X output=X thinking=N   (one line per group)
#   model <opus|sonnet|haiku> calls=N usd=X write=X read=X output=X thinking=N   (one line per model, all groups)
#   seats: N (haiku n, sonnet n, opus n)   (one seat per subagents/agent-*.jsonl with a counted request, by its first model)
#   resumes|gaps n=N tokens=N usd=X; fetch calls=N chars=N docs_chars=N docs_curl_nogrep=N
#   runreads n=N unnamed=N chars=N; tl_bigreads n=N chars=N
# With --split or --phase it prints only the retro's 3 lines (spec 002 U2, #11, #18):
#   spec: wall <m> min, seats <m> min, <N> tokens, $<X> API-equivalent
#   build: the same
#   seats: N (haiku n, sonnet n, opus n)
#   --split <ts>: requests, hand-backs and wall time up to <ts> are spec, the rest build. --phase spec|build: the whole
#   (cut) session is that phase and the other prints zeros.
#   wall: first to last user or assistant line of the session file, minutes to one decimal. seats <m>: the sum of the
#   hand-back duration_ms in the session file, from "<usage>... duration_ms: N</usage>" (a foreground hand-back) and
#   "<usage>...<duration_ms>N</duration_ms></usage>" (a background task notification); "n/a" when there are seat
#   requests and no such field anywhere. <N> tokens: input + cache write + cache read + output tokens of every counted
#   request (TL, seats, workflow); the hand-back subagent_tokens is the seat's last context size, so it is not summed.
# Exit 0; 2 on a usage error, a missing session file or a missing jq.
# Requests: assistant lines, model not <synthetic>, the final line per request id; none whose first line is after --until.
# Prices per MTok (input, 5m write, 1h write, read, output): opus 4/5/8/0.20/20, sonnet 2/2.5/4/0.20/10,
# haiku 1/1.25/2/0.10/5; a write with no 5m/1h split counts as 5m; a model of no known family is priced 0 (a warning on stderr).
set -uo pipefail

usage() { echo "usage: token-spend.sh <session.jsonl> [--until <ISO-8601 UTC>] [--split <ISO-8601 UTC> | --phase spec|build]" >&2; exit 2; }
TS_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z?$'
session="" until="" split="" mode=none
while [ "$#" -gt 0 ]; do
  case "$1" in
    --until) [ "$#" -ge 2 ] || usage; until=$2; shift 2 ;;
    --split) [ "$#" -ge 2 ] && [ "$mode" = none ] || usage; [[ "$2" =~ $TS_RE ]] || usage; split=$2; mode="split"; shift 2 ;;
    --phase) [ "$#" -ge 2 ] && [ "$mode" = none ] || usage; case "$2" in spec|build) mode=$2 ;; *) usage ;; esac; shift 2 ;;
    -*) usage ;;
    *) [ -z "$session" ] || usage; session=$1; shift ;;
  esac
done
[ -n "$session" ] || usage
[[ -z "$until" || "$until" =~ $TS_RE ]] || usage
command -v jq >/dev/null 2>&1 || { echo "token-spend.sh: jq not found" >&2; exit 2; }
[ -f "$session" ] || { echo "token-spend.sh: $session not found" >&2; exit 2; }

dir=${session%.jsonl}
# Each file is passed whole as --rawfile <group>_<n> (jq 1.6 -R can split a multibyte character at a read boundary).
files=(--rawfile TL_0 "$session")
n=0
for f in "$dir"/subagents/agent-*.jsonl; do
  [ -f "$f" ] && { n=$((n + 1)); files+=(--rawfile "seats_$n" "$f"); }
done
for f in "$dir"/subagents/workflows/*/agent-*.jsonl; do
  [ -f "$f" ] && { n=$((n + 1)); files+=(--rawfile "workflow_$n" "$f"); }
done

# Money is summed as integer cents per MTok times tokens, then rounded half up to cents.
read -r -d '' PROG <<'JQ'
def after($t): $cut != "" and ((($t // "") | .[0:19]) > $cut);
def secs: (.[0:19] + "Z" | fromdateiso8601) + ((.[19:] | capture("^\\.(?<f>[0-9]+)") | "0." + .f | tonumber) // 0);
def base: split("/") | last // "";
def ctext: if type == "string" then . elif type == "array" then [.[] | select(type == "object" and .type == "text") | .text // ""] | join(" ") else "" end;
def hbtext: if type == "string" then . elif type == "array" then [.[] | select(type == "object")
    | if .type == "tool_result" then (.content | ctext) elif .type == "text" then (.text // "") else "" end] | join("\n") else "" end;
def hbms: [match("<usage>[^<]*duration_ms: *([0-9]+)"; "g"), match("<usage>(?:<[a-z_]+>[0-9]+</[a-z_]+>)*<duration_ms>([0-9]+)</duration_ms>"; "g")
  | .captures[0].string | tonumber];
def clen: if type == "string" then length elif type == "array" then [.[] | select(type == "object" and .type == "text") | .text // "" | length] | add // 0 else 0 end;
def price: (.model // "") as $m
  | if ($m | contains("opus")) then [400, 500, 800, 20, 2000]
    elif ($m | contains("sonnet")) then [200, 250, 400, 20, 1000]
    elif ($m | contains("haiku")) then [100, 125, 200, 10, 500]
    else [0, 0, 0, 0, 0] end;
def unpriced: (.model // "") | test("opus|sonnet|haiku") | not;
def fam: (.model // "") | if contains("opus") then "opus" elif contains("sonnet") then "sonnet" elif contains("haiku") then "haiku" else "" end;
def toks: .inp + (if .cw5 + .cw1 == 0 then .cw else .cw5 + .cw1 end) + .cr + .out;
def total: .inp + .write + .read + .output;
def phase($t): if $mode == "spec" or $mode == "build" then $mode
  elif $mode == "split" and ((($t // "") | .[0:19]) > $split) then "build" else "spec" end;
def tenths: . as $t | "\($t / 10 | floor).\($t % 10)";
def cost: price as $p
  | {inp: (.inp * $p[0]),
     write: (if .cw5 + .cw1 == 0 then .cw * $p[1] else .cw5 * $p[1] + .cw1 * $p[2] end),
     read: (.cr * $p[3]), output: (.out * $p[4])};
def usd: (. + 500000) / 1000000 | floor | "\(. / 100 | floor).\(. % 100 | tostring | if length < 2 then "0" + . else . end)";
def segs: [splits("&&|;|\\|\\||\n") | sub("^\\s+"; "") | sub("\\s+$"; "")];
def docs: ["code.claude.com", "platform.claude.com"];
def runreads:
  if .nm == "Read" then (if (.fp | contains("/.cache/senioro-tl/runs/")) then [.fp | base] else [] end)
  elif .nm == "Bash" then [.cmd | segs[] | select(test("^(cat|sed|head|tail|nl|awk)\\b"))
    | scan("(?:/\\.cache/senioro-tl/runs/[^/\\s]+/|\\$\\{?R\\}?/)(?:reports/)?([A-Za-z0-9._-]+\\.(?:md|diff))")[0]]
  else [] end;
def nogrep: . as $c | ($c | contains("curl")) and any(docs[]; . as $h | $c | contains($h))
  and any($c | segs[]; test("\\bcurl\\b") and (test("\\|\\s*grep\\b") | not));
def urow: (.cache_creation // {}) as $cc
  | {inp: (.input_tokens // 0), cw: (.cache_creation_input_tokens // 0),
     cw5: ($cc.ephemeral_5m_input_tokens // 0), cw1: ($cc.ephemeral_1h_input_tokens // 0),
     cr: (.cache_read_input_tokens // 0), out: (.output_tokens // 0),
     th: (.output_tokens_details.thinking_tokens // 0)};
def assistant($d):
  ($d.message // {}) as $m
  | reduce (($m.content // []) | if type == "array" then .[] else empty end
            | select(type == "object" and .type == "tool_use")) as $b (.;
      ($b.input // {}) as $i
      | .tu[$b.id | tostring] = {nm: $b.name, cmd: ($i.command // ""), url: ($i.url // ""), fp: ($i.file_path // "")}
      | if after($d.timestamp) then .
        elif ($b.name == "Write" or $b.name == "Edit") and ($i.file_path // "") != "" then .wr[$i.file_path | base] = true
        elif $b.name == "Bash" then reduce (($i.command // "")
            | scan("(?:>>?|\\btee\\b(?:\\s+-a)?|\\s-o)\\s*['\"]?([^\\s'\";|&)]+)")[0] | base) as $w (.; .wr[$w] = true)
        else . end)
  | if $m.model == "<synthetic>" or ($m.usage | type) != "object" then .
    else (($d.requestId // $m.id) | tostring) as $k | ($m.usage | urow) as $u
      | if .ix[$k] == null then .ix[$k] = (.reqs | length)
          | .reqs += [{ts: $d.timestamp, start: (.lu // $d.timestamp), lastin: .lk, model: $m.model} + $u]
        else .reqs[.ix[$k]] += $u end
    end;
def user($d):
  ($d.message.content) as $c
  | .lu = $d.timestamp
  | .lk = (if ($c | type) == "array" and any($c[]; type == "object" and .type == "tool_result") then "tool" else "msg" end)
  | .dur += (if after($d.timestamp) then [] else [($c | hbtext | hbms[]) as $ms | {ts: $d.timestamp, ms: $ms}] end)
  | if after($d.timestamp) then .
    elif ($c | type) == "string" then .ut += [$c]
    elif ($c | type) == "array" then reduce ($c[] | select(type == "object")) as $b (.;
        if $b.type == "tool_result" then (.tu[$b.tool_use_id | tostring] // {nm: "?"}) as $t
          | if ($t.nm == "Read" or $t.nm == "Bash" or $t.nm == "WebFetch")
            then .res += [$t + {n: ($b.content | clen), cf: ($b.content | ctext | contains("curl: ("))}] else . end
        elif $b.type == "text" then .ut += [$b.text // ""]
        else . end)
    else . end;
def zero: {calls: 0, inp: 0, write: 0, read: 0, output: 0, th: 0};
def wallsecs($p): .t[0] as $a | .t[1] as $b
  | if $a == null then 0
    elif $mode == "spec" or $mode == "build" then (if $p == $mode then $b - $a else 0 end)
    else ($split | secs) as $s
      | if $p == "spec" then ([([$s, $b] | min) - $a, 0] | max) else ([$b - ([$s, $a] | max), 0] | max) end end;
def phline($p):
  ([.dur[] | select(phase(.ts) == $p) | .ms] | add // 0) as $ms
  | (if (.dur | length) == 0 and .sc.n > 0 then "n/a" else $ms / 6000 | round | tenths end) as $sm
  | "\($p): wall \(wallsecs($p) / 6 | round | tenths) min, seats \($sm) min, \(.ph[$p].tk) tokens, $\(.ph[$p].c | usd) API-equivalent";

[$ARGS.named | to_entries[] | select(.key | test("^(TL|seats|workflow)_[0-9]+$"))
  | {g: (.key | sub("_[0-9]+$"; ""))}
    + (reduce (.value | split("\n")[] | fromjson? | select(type == "object")) as $d
        ({reqs: [], ix: {}, tu: {}, res: [], ut: [], wr: {}, lu: null, lk: null, dur: [], t0: null, t1: null};
        (if ($d.type == "assistant" or $d.type == "user") and (($d.timestamp | type) == "string")
            and ($d.timestamp | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}")) and (after($d.timestamp) | not)
          then ($d.timestamp | secs) as $x | .t0 = (if .t0 == null or $x < .t0 then $x else .t0 end) | .t1 = (if .t1 == null or $x > .t1 then $x else .t1 end)
          else . end)
        | if $d.type == "assistant" then assistant($d) elif $d.type == "user" then user($d) else . end))]
| reduce (.[] | .reqs |= map(select(after(.ts) | not))) as $s
    ({TL: zero, seats: zero, workflow: zero, res: [0, 0, 0], gap: [0, 0, 0], fet: [0, 0, 0, 0], rr: [0, 0, 0], big: [0, 0],
      mod: {opus: zero, sonnet: zero, haiku: zero}, ph: {spec: {tk: 0, c: 0}, build: {tk: 0, c: 0}},
      sc: {n: 0, opus: 0, sonnet: 0, haiku: 0}, dur: [], t: [null, null]};
    reduce ($s.reqs[] | {th, ts, f: fam, tk: toks, c: cost, u: (if unpriced then .model // "none" else null end)}) as $r (.; .[$s.g] |= (.calls += 1 | .th += $r.th
        | .inp += $r.c.inp | .write += $r.c.write | .read += $r.c.read | .output += $r.c.output)
      | if $r.f != "" then .mod[$r.f] |= (.calls += 1 | .th += $r.th
          | .inp += $r.c.inp | .write += $r.c.write | .read += $r.c.read | .output += $r.c.output) else . end
      | .ph[phase($r.ts)] |= (.tk += $r.tk | .c += ($r.c | total))
      | if $r.u != null then .unpriced[$r.u] += 1 else . end)
    | if $s.g == "TL" then
        reduce ($s.res[] | select(.nm == "Read" and .n > 20000)) as $r (.; .big[0] += 1 | .big[1] += $r.n)
      else
        reduce range(1; $s.reqs | length) as $i (.; $s.reqs[$i] as $r
          | if ($r.start | secs) - ($s.reqs[$i - 1].start | secs) > 300
            then (if $r.lastin == "msg" then "res" else "gap" end) as $k
              | .[$k][0] += 1 | .[$k][1] += $r.cw | .[$k][2] += ($r | cost | .write)
            else . end)
        | ($s.ut | join(" ")) as $ut
        | (reduce $s.res[] as $r ({failed: {}, acc: .};
            (if $r.nm == "Bash" then
               (if $r.cf then reduce (docs[] | select(. as $h | $r.cmd | contains($h))) as $h (.; .failed[$h] = true) else . end)
               | if ($r.cmd | nogrep) then .acc.fet[3] += 1 else . end
             elif $r.nm == "WebFetch" then
               .acc.fet[0] += 1 | .acc.fet[1] += $r.n
               | ([docs[] | select(. as $h | $r.url | contains($h))][0]) as $h
               | if $h != null and .failed[$h] != true then .acc.fet[2] += $r.n else . end
             else . end)
            | ($r | runreads) as $names
            | if ($names | length) > 0 then .acc.rr[0] += 1
                | if any($names[]; . as $x | ($ut | contains($x) | not) and $s.wr[$x] != true)
                  then .acc.rr[1] += 1 | .acc.rr[2] += $r.n else . end
              else . end) | .acc)
      end
      | if $s.g == "seats" and ($s.reqs | length) > 0
        then ($s.reqs[0] | fam) as $f | .sc.n += 1 | (if $f != "" then .sc[$f] += 1 else . end) else . end
      | if $s.g == "TL" then .dur = $s.dur | .t = [$s.t0, $s.t1] else . end)
| (if $mode == "none" then
    (["TL", "seats", "workflow"][] as $g | .[$g]
      | "\($g) calls=\(.calls) usd=\(.inp + .write + .read + .output | usd) write=\(.write | usd) read=\(.read | usd) output=\(.output | usd) thinking=\(.th)"),
    (["opus", "sonnet", "haiku"][] as $f | .mod[$f]
      | "model \($f) calls=\(.calls) usd=\(.inp + .write + .read + .output | usd) write=\(.write | usd) read=\(.read | usd) output=\(.output | usd) thinking=\(.th)"),
    "seats: \(.sc.n) (haiku \(.sc.haiku), sonnet \(.sc.sonnet), opus \(.sc.opus))",
    "resumes n=\(.res[0]) tokens=\(.res[1]) usd=\(.res[2] | usd)",
    "gaps n=\(.gap[0]) tokens=\(.gap[1]) usd=\(.gap[2] | usd)",
    "fetch calls=\(.fet[0]) chars=\(.fet[1]) docs_chars=\(.fet[2]) docs_curl_nogrep=\(.fet[3])",
    "runreads n=\(.rr[0]) unnamed=\(.rr[1]) chars=\(.rr[2])",
    "tl_bigreads n=\(.big[0]) chars=\(.big[1])"
  else
    phline("spec"), phline("build"),
    "seats: \(.sc.n) (haiku \(.sc.haiku), sonnet \(.sc.sonnet), opus \(.sc.opus))"
  end),
  (.unpriced // {} | to_entries[] | "token-spend.sh: \(.value) requests of model \(.key) have no price; counted at 0")
JQ

out=$(jq -nr --arg cut "${until:0:19}" --arg split "${split:0:19}" --arg mode "$mode" "${files[@]}" "$PROG") || exit
# Warnings (unpriced models) go to stderr; stdout keeps the 12 lines (3 with --split or --phase).
while IFS= read -r line; do
  case "$line" in "token-spend.sh: "*) printf '%s\n' "$line" >&2 ;; *) printf '%s\n' "$line" ;; esac
done <<< "$out"
