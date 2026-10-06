#!/bin/bash
# The inference supervisor, run AS seed: starts llama-server's router (serve.sh; rung4b.md) and gives the machine back to
# the person's work first (owner, 20260927: rung 4 on his daily Mac). Every 15 s it:
#   yields  - stops the server when macOS memory pressure leaves "normal" or the system-wide free
#             percentage falls below YIELD_FREE;
#   holds   - stops it and writes $S/held if the server's real memory (tree_mem: footprint) passes the ceiling (a
#             config fault: no automatic return; a person reads events.log and removes `held`);
#   resumes - starts it again after CALM_S seconds of normal pressure with RESUME_FREE% free.
#   unloads - first, before any of those (20261002, the utility tier: many models on one box): when the tree nears the
#             ceiling (CEILING_MIB - SOFT_MARGIN_MIB) or pressure leaves normal, it unloads one on-demand model a tick
#             through the router's API, in ON_DEMAND's order (the 27B, then the general model), skipping one that is
#             serving a request while another is idle. Only with no on-demand model left loaded does it hold or yield.
# A person pauses it with `touch $S/held` (as seed, or with sudo) and resumes by removing the file.
# Every change is one line in $S/events.log; the current state is in $S/status (key=value).
# Run by the LaunchDaemon co.oznog.seed.inference (inference-admin-setup.sh), and by nothing else:
# the interim nohup start was retired 20260927 once the daemon ran.
set -uo pipefail
D=$(cd "$(dirname "$0")" && pwd); . "$D/pins"
S=$HOME/.local/state/seed/inference; mkdir -p "$S"
YIELD_FREE=${YIELD_FREE:-20}; RESUME_FREE=${RESUME_FREE:-45}; CALM_S=${CALM_S:-900}; TICK=15   # from pins
# another supervisor: a process whose whole command line is bash running this script (not any command that mentions its
# path: a shell running `pgrep inference/supervise.sh` blocked every start for 13 minutes, 20261002)
pgrep -u "$(id -u)" -f '^/bin/bash [^ ]*/inference/supervise\.sh$' | grep -vx "$$" | grep -q . && { echo "already running"; exit 1; }
pid=; calm_since=; warned=; state=running; [ -f "$S/held" ] && state=held
log() { echo "$(date -u +%FT%TZ) $*" >> "$S/events.log"; }
# the resident total of a process and all its descendants, in MiB (rung 4b: the router's children)
tree_rss() { ps -A -o pid=,ppid=,rss= | awk -v root="$1" '{p[$1]=$2; r[$1]=$3} END {
  for (x in p) { y=x; while (y != "" && y != 0 && y != 1) { if (y == root) { t += r[x]; break } y=p[y] } } print int(t/1024) }'; }
# the tree's real memory, in MiB (20260930): footprint's dirty memory, which includes what macOS has compressed, plus
# its resident clean pages (the mapped model files). `ps` RSS drops compressed pages: a full RAM prompt cache,
# compressed, took ~6 GB that RSS never showed, and the ceiling couldn't see it (evidence/20260930-qwen-ram-cache.md).
# Falls back to RSS, and says so, if footprint gives nothing.
tree_pids() { ps -A -o pid=,ppid= | awk -v root="$1" '{p[$1]=$2} END { for (x in p) { y=x; while (y != "" && y != 0 && y != 1) { if (y == root) { print x; break } y=p[y] } } }'; }
tree_mem() {
  local a=() x m; for x in $(tree_pids "$1"); do a+=(-p "$x"); done
  m=$(footprint -f bytes "${a[@]}" 2>/dev/null | awk '/^Summary Footprint/ {s=1} s && / TOTAL$/ {print int(($1 + $3) / 1048576); exit}')
  if [ -n "$m" ]; then echo "$m"; else echo "$(tree_rss "$1") rss"; fi
}
stop() { [ -n "$pid" ] && kill -TERM "$pid" 2>/dev/null && wait "$pid" 2>/dev/null; pid=; }
# the router's API, with the key it answers (the gateway's)
api() { curl -s -m 20 -H "Authorization: Bearer $(cat "$HOME/.config/seed/llama.key")" "$@"; }
loaded() { api "http://$LISTEN:$PORT/models" | python3 -c "import json,sys; print(' '.join(m['id'] for m in json.load(sys.stdin)['data'] if m['status']['value']=='loaded'))" 2>/dev/null; }
# busy unless the router says every slot is idle: an error, a timeout or an odd answer counts as busy (Codex's review)
busy() { api "http://$LISTEN:$PORT/slots?model=$1" | python3 -c "
import json,sys
try: s = json.load(sys.stdin); sys.exit(1 if isinstance(s, list) and s and all(isinstance(x, dict) and x.get('is_processing') is False for x in s) else 0)
except Exception: sys.exit(0)" 2>/dev/null; }
# a model that keeps coming back (a request reloads it) is unloaded at most 3 times in 10 minutes, counted per model
# ($S/evicted-<model>: one time a line); after that the supervisor falls through to hold or yield as before
ev_count=0
again() { local f="$S/evicted-$1" now; now=$(date +%s)
  { [ -f "$f" ] && awk -v n="$now" 'n - $1 < 600' "$f"; echo "$now"; } > "$f.tmp" && mv "$f.tmp" "$f"
  ev_count=$(wc -l < "$f" | tr -d ' '); [ "$ev_count" -le 3 ]; }
# "in use": seen serving a request within IDLE_S (10 min). An agent's run leaves its model idle between calls while its
# tools run; a check of this instant alone would unload it mid-run. Each tick records every loaded on-demand model
# seen busy ($S/used-<model>).
IDLE_S=${IDLE_S:-600}
mark_used() { local l m; l=" $(loaded) "
  for m in ${ON_DEMAND:-}; do case "$l" in *" $m "*) busy "$m" && date +%s > "$S/used-$m";; esac; done; }
in_use() { local u; u=$(cat "$S/used-$1" 2>/dev/null || echo 0); [ $(( $(date +%s) - u )) -lt "$IDLE_S" ]; }
# the on-demand model to unload now: the first in ON_DEMAND that is loaded and not in use; one in use (the first
# loaded) only when it must ($1 = hard: over the ceiling itself, or pressure off normal)
victim() { local l m first=; l=" $(loaded) "
  for m in ${ON_DEMAND:-}; do case "$l" in *" $m "*) first=${first:-$m}; in_use "$m" || { echo "$m"; return; };; esac; done
  [ "${1:-}" = hard ] && echo "$first"; }
trap 'stop; log "supervisor stopped"; exit 0' TERM INT
log "supervisor started (pid $$, ceiling ${CEILING_MIB} MiB, router mode, the models in presets.ini)"
while :; do
  level=$(sysctl -n kern.memorystatus_vm_pressure_level)          # 1 normal, 2 warn, 4 critical
  free=$(memory_pressure -Q | awk -F': ' '/free percentage/ {sub("%","",$2); print $2+0}')
  [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null && { wait "$pid"; log "server exited ($?)"; pid=; }
  rss=0; mem=0; [ -n "$pid" ] && { rss=$(tree_rss "$pid"); mem=$(tree_mem "$pid"); }
  case "$mem" in *rss) mem=${mem% rss}; [ "$warned" = 1 ] || { log "footprint gave nothing: the ceiling uses RSS"; warned=1; };; esac
  [ "$state" = running ] && [ -n "$pid" ] && mark_used
  over=0; [ "$mem" -gt $(( CEILING_MIB - ${SOFT_MARGIN_MIB:-0} )) ] && over=1
  hard=; { [ "$mem" -gt "$CEILING_MIB" ] || [ "$level" -ne 1 ] || [ "$free" -lt "$YIELD_FREE" ]; } && hard=hard
  if [ "$state" = running ] && [ -n "$pid" ] && [ ! -f "$S/held" ] && { [ $over = 1 ] || [ -n "$hard" ]; } \
     && v=$(victim $hard) && [ -n "$v" ] && again "$v" \
     && api -X POST -H 'Content-Type: application/json' -d "{\"model\":\"$v\"}" "http://$LISTEN:$PORT/models/unload" | grep -q '"success": *true'; then
    log "unloaded $v: footprint ${mem} MiB, pressure level $level, free ${free}% (on demand, before any stop; #$ev_count in 10 min)"
  elif [ -f "$S/held" ]; then
    [ "$state" != held ] && { stop; log "held (by a person or the ceiling); server stopped"; }; state=held
  elif [ "$mem" -gt "$CEILING_MIB" ]; then
    stop; touch "$S/held"; state=held; log "HELD: server footprint ${mem} MiB (RSS ${rss}) > ceiling ${CEILING_MIB} MiB"
  elif [ "$state" = running ] && { [ "$level" -ne 1 ] || [ "$free" -lt "$YIELD_FREE" ]; }; then
    stop; state=yielded; calm_since=; log "yield: pressure level $level, free ${free}%, server was ${mem} MiB (RSS ${rss})"
  elif [ "$state" != running ]; then            # yielded, or held just cleared
    if [ "$level" -eq 1 ] && [ "$free" -ge "$RESUME_FREE" ]; then
      calm_since=${calm_since:-$(date +%s)}
      if [ "$state" = held ] || [ $(( $(date +%s) - calm_since )) -ge "$CALM_S" ]; then
        state=running; calm_since=; log "resume: level 1, free ${free}%"
      fi
    else calm_since=; fi
  fi
  if [ "$state" = running ] && [ -z "$pid" ]; then
    "$D/serve.sh" >> "$S/server.log" 2>&1 & pid=$!; log "server started (pid $pid)"
  fi
  printf 'ts=%s\nstate=%s\nlevel=%s\nfree_pct=%s\nserver_rss_mib=%s\nserver_footprint_mib=%s\nceiling_mib=%s\n' \
    "$(date -u +%FT%TZ)" "$state" "$level" "$free" "$rss" "$mem" "$CEILING_MIB" > "$S/status.tmp" && mv "$S/status.tmp" "$S/status"
  sleep "$TICK" & wait $!
done
