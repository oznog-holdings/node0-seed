#!/bin/bash
# The inference supervisor, run AS seed: starts llama-server's router (serve.sh; rung4b.md) and gives the machine back to
# the person's work first (owner, 20260927: rung 4 on his daily Mac). Every 15 s it:
#   yields  - stops the server when macOS memory pressure leaves "normal" or the system-wide free
#             percentage falls below YIELD_FREE;
#   holds   - stops it and writes $S/held if the server's own resident size passes the ceiling (a
#             config fault: no automatic return; a person reads events.log and removes `held`);
#   resumes - starts it again after CALM_S seconds of normal pressure with RESUME_FREE% free.
# A person pauses it with `touch $S/held` (as seed, or with sudo) and resumes by removing the file.
# Every change is one line in $S/events.log; the current state is in $S/status (key=value).
# Run by the LaunchDaemon co.oznog.seed.inference (inference-admin-setup.sh), and by nothing else:
# the interim nohup start was retired 20260927 once the daemon ran.
set -uo pipefail
D=$(cd "$(dirname "$0")" && pwd); . "$D/pins"
S=$HOME/.local/state/seed/inference; mkdir -p "$S"
YIELD_FREE=${YIELD_FREE:-20}; RESUME_FREE=${RESUME_FREE:-45}; CALM_S=${CALM_S:-900}; TICK=15   # from pins
pgrep -u "$(id -u)" -f "inference/supervise.sh" | grep -vx "$$" | grep -q . && { echo "already running"; exit 1; }
pid=; calm_since=; state=running; [ -f "$S/held" ] && state=held
log() { echo "$(date -u +%FT%TZ) $*" >> "$S/events.log"; }
# the resident total of a process and all its descendants, in MiB (rung 4b: the router's children)
tree_rss() { ps -A -o pid=,ppid=,rss= | awk -v root="$1" '{p[$1]=$2; r[$1]=$3} END {
  for (x in p) { y=x; while (y != "" && y != 0 && y != 1) { if (y == root) { t += r[x]; break } y=p[y] } } print int(t/1024) }'; }
stop() { [ -n "$pid" ] && kill -TERM "$pid" 2>/dev/null && wait "$pid" 2>/dev/null; pid=; }
trap 'stop; log "supervisor stopped"; exit 0' TERM INT
log "supervisor started (pid $$, ceiling ${CEILING_MIB} MiB, router mode, the models in presets.ini)"
while :; do
  level=$(sysctl -n kern.memorystatus_vm_pressure_level)          # 1 normal, 2 warn, 4 critical
  free=$(memory_pressure -Q | awk -F': ' '/free percentage/ {sub("%","",$2); print $2+0}')
  [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null && { wait "$pid"; log "server exited ($?)"; pid=; }
  rss=0; [ -n "$pid" ] && rss=$(tree_rss "$pid")   # MiB resident: the router and every model it loaded
  if [ -f "$S/held" ]; then
    [ "$state" != held ] && { stop; log "held (by a person or the ceiling); server stopped"; }; state=held
  elif [ "$rss" -gt "$CEILING_MIB" ]; then
    stop; touch "$S/held"; state=held; log "HELD: server resident ${rss} MiB > ceiling ${CEILING_MIB} MiB"
  elif [ "$state" = running ] && { [ "$level" -ne 1 ] || [ "$free" -lt "$YIELD_FREE" ]; }; then
    stop; state=yielded; calm_since=; log "yield: pressure level $level, free ${free}%, server was ${rss} MiB"
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
  printf 'ts=%s\nstate=%s\nlevel=%s\nfree_pct=%s\nserver_rss_mib=%s\nceiling_mib=%s\n' \
    "$(date -u +%FT%TZ)" "$state" "$level" "$free" "$rss" "$CEILING_MIB" > "$S/status.tmp" && mv "$S/status.tmp" "$S/status"
  sleep "$TICK" & wait $!
done
