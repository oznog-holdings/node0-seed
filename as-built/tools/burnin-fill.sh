#!/bin/bash
# Burn-in fill: W writers x N files x 1 GiB of AES-CTR keystream (incompressible) into DIR.
# Throwaway random keys per writer; no secrets. Logs progress and writes DIR/FILL_DONE (or FILL_FAILED).
set -u
DIR=${1:?dir}; W=${2:-8}; N=${3:-92}
mkdir -p "$DIR"; LOG="$DIR/fill.log"
echo "start $(date -Iseconds) writers=$W files_each=$N" >> "$LOG"
writer() {
  local w=$1 i key iv
  for i in $(seq 1 "$N"); do
    key=$(openssl rand -hex 16); iv=$(openssl rand -hex 16)
    if ! openssl enc -aes-128-ctr -K "$key" -iv "$iv" -in /dev/zero 2>/dev/null | head -c 1073741824 > "$DIR/w$w-$i.bin"; then
      echo "writer $w file $i FAILED $(date -Iseconds)" >> "$LOG"; return 1; fi
    [ "$(stat -c %s "$DIR/w$w-$i.bin")" = 1073741824 ] || { echo "writer $w file $i SHORT" >> "$LOG"; return 1; }
  done
  echo "writer $w done $(date -Iseconds)" >> "$LOG"
}
pids=(); for w in $(seq 1 "$W"); do writer "$w" & pids+=($!); done
rc=0; for p in "${pids[@]}"; do wait "$p" || rc=1; done
sync
if [ $rc = 0 ]; then echo "done $(date -Iseconds)" >> "$LOG"; date -Iseconds > "$DIR/FILL_DONE"; else echo "failed $(date -Iseconds)" >> "$LOG"; date -Iseconds > "$DIR/FILL_FAILED"; fi
