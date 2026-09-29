#!/bin/bash
# sample.sh <out.csv> <process pattern>: every 5 s, the runtime's resident size and the machine's
# memory state, until killed. Pages are 16 KiB. Runs as seed on compute.
out=$1; pat=$2
echo "ts,rss_mib,free_pct,level,swapouts,compressor_pages,wired_pages" > "$out"
while :; do
  pid=$(pgrep -u "$(id -u)" -f "$pat" | head -1); rss=0
  [ -n "$pid" ] && rss=$(( $(ps -o rss= -p "$pid" | tr -d ' ') / 1024 ))
  v=$(vm_stat)
  pg() { awk -F: -v k="$1" '$1==k {gsub(/[ .]/,"",$2); print $2}' <<<"$v"; }
  echo "$(date +%s),$rss,$(memory_pressure -Q | awk -F': ' '/free percentage/ {print $2+0}'),$(sysctl -n kern.memorystatus_vm_pressure_level),$(pg Swapouts),$(pg 'Pages occupied by compressor'),$(pg 'Pages wired down')" >> "$out"
  sleep 5
done
