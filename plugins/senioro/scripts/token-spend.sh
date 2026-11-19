#!/usr/bin/env bash
# Token spend of one Claude Code session (spec 001 #7, section 5 definitions), for re-measuring the TL workflow.
# Usage: token-spend.sh <session.jsonl> [--until <ISO-8601 UTC>] [--split <ISO-8601 UTC> | --phase spec|build | --usage]
#   Reads the session file (TL), <session>/subagents/agent-*.jsonl (seats) and
#   <session>/subagents/workflows/*/agent-*.jsonl (workflow agents). Prints 13 lines:
#   <TL|seats|workflow> calls=N usd=X write=X read=X output=X thinking=N   (one line per group)
#   model <opus|sonnet|haiku|other> calls=N usd=X write=X read=X output=X thinking=N   (one line per model family, all
#   groups; other is every model outside the three, so the four model lines add up to the three group lines)
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
# With --usage it prints only the retro's Usage block, at most 30 lines of markdown: est. $ by where (TL, seat,
#   workflow) x agent type x model (at most 12 rows, the rest folded), the top 5 spenders (the TL main loop and each
#   agent file) and what each was for, and a footer naming what is not counted or priced approximately. Agent type is
#   the agent's meta.json agentType, else its lines' attributionAgent, else "(unknown)"; for what is the meta
#   description ("<workflowPhase>: <description>" for a workflow agent). Ties go to where, agent type, model (rows)
#   and id (spenders), ascending.
# Exit 0; 2 on a usage error, a missing session file or a missing jq.
# Requests: assistant lines, model not <synthetic>, the final line per request id; none whose first line is after --until.
# Prices: the ptab table below, one row per model of https://platform.claude.com/docs/en/about-claude/pricing (global
# inference, standard speed), in USD mills per MTok (input, 5m write, 1h write, cache read, output); haiku-5-5 has a
# second row for a prompt (input + cache read + cache write) over 100,000 tokens. A model id is looked up without its
# "claude-" prefix and a -YYYYMMDD suffix. An id not in the table that names a family (opus, sonnet, haiku, fable, mythos)
# is priced at that family's newest row, and any other id at 0; both get a warning on stderr. A write with no 5m/1h
# split counts as 5m.
set -uo pipefail

usage() { echo "usage: token-spend.sh <session.jsonl> [--until <ISO-8601 UTC>] [--split <ISO-8601 UTC> | --phase spec|build | --usage]" >&2; exit 2; }
TS_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z?$'
session="" until="" split="" mode=none
while [ "$#" -gt 0 ]; do
  case "$1" in
    --until) [ "$#" -ge 2 ] || usage; until=$2; shift 2 ;;
    --split) [ "$#" -ge 2 ] && [ "$mode" = none ] || usage; [[ "$2" =~ $TS_RE ]] || usage; split=$2; mode="split"; shift 2 ;;
    --phase) [ "$#" -ge 2 ] && [ "$mode" = none ] || usage; case "$2" in spec|build) mode=$2 ;; *) usage ;; esac; shift 2 ;;
    --usage) [ "$mode" = none ] || usage; mode=usage; shift ;;
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
# --usage also passes its id as --arg id_<n> and its meta.json, if any, as --rawfile meta_<n>.
files=(--rawfile TL_0 "$session")
n=0
add() {
  files+=(--rawfile "$1_$n" "$2")
  if [ "$mode" = usage ]; then
    id=${2##*/}; id=${id#agent-}; files+=(--arg "id_$n" "${id%.jsonl}")
    [ ! -f "${2%.jsonl}.meta.json" ] || files+=(--rawfile "meta_$n" "${2%.jsonl}.meta.json")
  fi
}
[ "$mode" != usage ] || { id=${session##*/}; files+=(--arg id_0 "${id%.jsonl}"); }
for f in "$dir"/subagents/agent-*.jsonl; do
  [ -f "$f" ] && { n=$((n + 1)); add seats "$f"; }
done
for f in "$dir"/subagents/workflows/*/agent-*.jsonl; do
  [ -f "$f" ] && { n=$((n + 1)); add workflow "$f"; }
done

# Money is summed as integer mills per MTok times tokens, then rounded half up to cents.
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
def ptab: {"fable-5-2": [8000, 10000, 16000, 200, 40000], "fable-5-1": [10000, 12500, 20000, 250, 50000],
  "fable-5": [10000, 12500, 20000, 1000, 50000], "mythos-5-2": [8000, 10000, 16000, 200, 40000],
  "mythos-5-1": [10000, 12500, 20000, 250, 50000], "mythos-5": [10000, 12500, 20000, 1000, 50000],
  "opus-5-5": [4000, 5000, 8000, 200, 20000], "opus-5": [5000, 6250, 10000, 500, 25000],
  "opus-4-8": [5000, 6250, 10000, 500, 25000], "opus-4-7": [5000, 6250, 10000, 500, 25000],
  "opus-4-6": [5000, 6250, 10000, 500, 25000], "opus-4-5": [5000, 6250, 10000, 500, 25000],
  "opus-4-1": [15000, 18750, 30000, 1500, 75000], "opus-4": [15000, 18750, 30000, 1500, 75000],
  "sonnet-5-5": [2000, 2500, 4000, 100, 10000], "sonnet-5": [2000, 2500, 4000, 200, 10000],
  "sonnet-4-6": [3000, 3750, 6000, 300, 15000], "sonnet-4-5": [3000, 3750, 6000, 300, 15000],
  "sonnet-4": [3000, 3750, 6000, 300, 15000], "haiku-5-5": [100, 125, 200, 10, 500],
  "haiku-4-5": [1000, 1250, 2000, 100, 5000]};
def mid: (.model // "") | tostring | sub("^claude-"; "") | sub("-[0-9]{8}$"; "");
def prow: mid as $i
  | if ptab[$i] != null then $i
    else [[["fable", "fable-5-2"], ["mythos", "mythos-5-2"], ["opus", "opus-5-5"], ["sonnet", "sonnet-5-5"], ["haiku", "haiku-5-5"]][]
      | select(.[0] as $f | $i | contains($f)) | .[1]][0] end;
def price: prow as $r
  | if $r == null then [0, 0, 0, 0, 0]
    elif $r == "haiku-5-5" and .inp + .cr + (if .cw5 + .cw1 == 0 then .cw else .cw5 + .cw1 end) > 100000 then [500, 625, 1000, 50, 2500]
    else ptab[$r] end;
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
def usd: (. + 5000000) / 10000000 | floor | "\(. / 100 | floor).\(. % 100 | tostring | if length < 2 then "0" + . else . end)";
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
     th: (.output_tokens_details.thinking_tokens // 0),
     ns: ((.speed // "standard") != "standard" or (.inference_geo // "global") != "global")};
def assistant($d):
  ($d.message // {}) as $m
  | .attr //= $d.attributionAgent
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
def cell: tostring | gsub("[\r\n\t`]"; " ") | gsub("\\|"; "\\|");
def pct($t): if $t == 0 then "0.0" else . * 1000 / $t + 0.5 | floor | tenths end;
def list: group_by(.m) | map("\(.[0].m) \(length)") | join(", ") | if . == "" then "none" else . end;
# The Usage block (--usage) over the per-file records: one row per counted request, then the tables and the footer.
def ublock:
  . as $F
  | [.[] | . as $f
      | ($f.meta.description // "" | tostring) as $d
      | {g, id, w: ({TL: "TL", seats: "seat", workflow: "workflow"}[.g]),
         t: (if .g == "TL" then "(TL main loop)" else $f.meta.agentType // $f.attr // "(unknown)" | cell end),
         d: (if ($f.meta.workflowPhase // "") != "" then "\($f.meta.workflowPhase): \($d)" else $d end
           | gsub("[\r\n\t`]"; " ") | .[0:40] | gsub("\\|"; "\\|"))}
      + (.reqs[] | select(after(.ts) | not)
        | {ts, ns, m: (.model // "none" | tostring | sub("^claude-"; "")), c: (cost | total),
           px: (prow != null and ptab[mid] == null), un: (prow == null)})] as $R
  | ($R | map(.c) | add // 0) as $tot
  | "## Usage \(if ($R | length) == 0 then "n/a" else $R | map(.ts) | max | .[0:10] + " " + .[11:16] end) UTC, session \($F[] | select(.g == "TL") | .id | .[0:8])",
    if ($R | length) == 0 then "No counted requests." else
      "Estimated at API list prices from this session's transcripts; not a bill. Per-model totals: /usage.",
      ([[["TL", "TL main loop"], ["seat", "seats"], ["workflow", "workflow agents"]][] as [$w, $l]
        | ($R | map(select(.w == $w) | .c) | add // 0) as $c | "\($l) $\($c | usd) (\($c | pct($tot))%)"]
        | join(" · ")) + " · total $\($tot | usd), \($R | length) requests",
      "",
      "| where | agent type | model | agents | requests | est. $ | share |",
      "|---|---|---|---|---|---|---|",
      ($R | group_by([.w, .t, .m])
        | map({w: .[0].w, t: .[0].t, m: .[0].m, f: (map(.g + "/" + .id) | unique), n: length, c: (map(.c) | add)})
        | sort_by([-.c, {TL: 0, seat: 1, workflow: 2}[.w], .t, .m])
        | if length > 12 then .[0:11] + [.[11:] | {w: "(other: \(length) rows)", t: "", m: "", f: (map(.f[]) | unique),
            n: (map(.n) | add), c: (map(.c) | add)}] else . end
        | .[] | "| \(.w) | \(.t) | \(.m | cell) | \(.f | length) | \(.n) | \(.c | usd) | \(.c | pct($tot))% |"),
      "",
      "| top spender | where | agent type | model | for what | est. $ |",
      "|---|---|---|---|---|---|",
      ($R | group_by([.g, .id])
        | map({w: .[0].w, id: .[0].id, t: .[0].t, d: .[0].d, c: (map(.c) | add),
            m: (group_by(.m) | map({m: .[0].m, c: (map(.c) | add)}) | sort_by([-.c, .m]) | map(.m | cell) | join("+"))})
        | sort_by([-.c, .id]) | .[0:5][]
        | "| \(if .w == "TL" then "TL main loop" else "\(.w) \(.id | .[0:8] | cell)" end) | \(.w) | \(.t) | \(.m) | \(.d) | \(.c | usd) |"),
      "",
      "Not in transcripts, so not counted: \([$F[] | select(.g == "TL") | .cb] | add // 0) compactions, title and web-fetch-summary calls. Priced approximately: \($R | map(select(.px)) | list).",
      "Unpriced ($0): \($R | map(select(.un)) | list). Non-standard speed or region: \($R | map(select(.ns)) | length) requests, priced as standard. This session id only; this retro's seat is excluded."
    end;

[$ARGS.named | to_entries[] | select(.key | test("^(TL|seats|workflow)_[0-9]+$"))
  | (.key | sub("^[A-Za-z]+_"; "")) as $n
  | {g: (.key | sub("_[0-9]+$"; "")), id: ($ARGS.named["id_" + $n] // ""),
     meta: ($ARGS.named["meta_" + $n] // "" | if . == "" then {} else (try fromjson catch {}) end | if type == "object" then . else {} end)}
    + (reduce (.value | split("\n")[] | fromjson? | select(type == "object")) as $d
        ({reqs: [], ix: {}, tu: {}, res: [], ut: [], wr: {}, lu: null, lk: null, dur: [], t0: null, t1: null, attr: null, cb: 0};
        (if ($d.type == "assistant" or $d.type == "user") and (($d.timestamp | type) == "string")
            and ($d.timestamp | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}")) and (after($d.timestamp) | not)
          then ($d.timestamp | secs) as $x | .t0 = (if .t0 == null or $x < .t0 then $x else .t0 end) | .t1 = (if .t1 == null or $x > .t1 then $x else .t1 end)
          else . end)
        | if $d.type == "assistant" then assistant($d) elif $d.type == "user" then user($d)
          elif $d.type == "system" and $d.subtype == "compact_boundary" and (after($d.timestamp) | not) then .cb += 1
          else . end))] as $F
| $F | reduce (.[] | .reqs |= map(select(after(.ts) | not))) as $s
    ({TL: zero, seats: zero, workflow: zero, res: [0, 0, 0], gap: [0, 0, 0], fet: [0, 0, 0, 0], rr: [0, 0, 0], big: [0, 0],
      mod: {opus: zero, sonnet: zero, haiku: zero, other: zero}, ph: {spec: {tk: 0, c: 0}, build: {tk: 0, c: 0}},
      sc: {n: 0, opus: 0, sonnet: 0, haiku: 0}, dur: [], t: [null, null]};
    reduce ($s.reqs[] | {th, ts, f: fam, tk: toks, c: cost}) as $r (.; .[$s.g] |= (.calls += 1 | .th += $r.th
        | .inp += $r.c.inp | .write += $r.c.write | .read += $r.c.read | .output += $r.c.output)
      | .mod[if $r.f == "" then "other" else $r.f end] |= (.calls += 1 | .th += $r.th
          | .inp += $r.c.inp | .write += $r.c.write | .read += $r.c.read | .output += $r.c.output)
      | .ph[phase($r.ts)] |= (.tk += $r.tk | .c += ($r.c | total)))
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
    (["opus", "sonnet", "haiku", "other"][] as $f | .mod[$f]
      | "model \($f) calls=\(.calls) usd=\(.inp + .write + .read + .output | usd) write=\(.write | usd) read=\(.read | usd) output=\(.output | usd) thinking=\(.th)"),
    "seats: \(.sc.n) (haiku \(.sc.haiku), sonnet \(.sc.sonnet), opus \(.sc.opus))",
    "resumes n=\(.res[0]) tokens=\(.res[1]) usd=\(.res[2] | usd)",
    "gaps n=\(.gap[0]) tokens=\(.gap[1]) usd=\(.gap[2] | usd)",
    "fetch calls=\(.fet[0]) chars=\(.fet[1]) docs_chars=\(.fet[2]) docs_curl_nogrep=\(.fet[3])",
    "runreads n=\(.rr[0]) unnamed=\(.rr[1]) chars=\(.rr[2])",
    "tl_bigreads n=\(.big[0]) chars=\(.big[1])"
  elif $mode == "usage" then $F | ublock
  else
    phline("spec"), phline("build"),
    "seats: \(.sc.n) (haiku \(.sc.haiku), sonnet \(.sc.sonnet), opus \(.sc.opus))"
  end),
  ([$F[].reqs[] | select(after(.ts) | not) | {m: (.model // "none"), r: prow, x: (ptab[mid] != null)} | select(.x | not)]
    | group_by(.m)[] | "token-spend.sh: \(length) requests of model \(.[0].m) "
      + (if .[0].r == null then "have no price; counted at 0" else "priced approximately as \(.[0].r)" end))
JQ

out=$(jq -nr --arg cut "${until:0:19}" --arg split "${split:0:19}" --arg mode "$mode" "${files[@]}" "$PROG") || exit
# Warnings (unpriced and approximately priced models) go to stderr; stdout keeps the 13 lines (3 with --split or --phase,
# the Usage block with --usage).
while IFS= read -r line; do
  case "$line" in "token-spend.sh: "*) printf '%s\n' "$line" >&2 ;; *) printf '%s\n' "$line" ;; esac
done <<< "$out"
