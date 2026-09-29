#!/bin/bash
# Hourly snapshots of the datasets the second site replicates (rung 5 › E), made here by infra, since
# site2's key may only send and hold (zfs-send-guard.sh). Named as sanoid names its own
# (autosnap_<UTC date>_<UTC time>_hourly, and _daily at 00h UTC), so sanoid on site2 prunes what arrives.
# Kept here: hourly for 48 h, daily for 30 days; a held snapshot (site2's newest common one, held by
# syncoid) is never destroyed. Hourly from User Scripts (5 * * * *); writes seed-state/replica-snap.last
# on success (JobStale).
set -euo pipefail
DS="data/documents data/finance data/photos data/appdata"
state=/mnt/data/system/seed-state
log() { echo "$(date -u +%FT%TZ) $*"; }
stamp=$(date -u +%Y-%m-%d_%H:%M:%S); hour=$(date -u +%H); now=$(date +%s)
made=0; pruned=0
for d in $DS; do
  zfs snapshot "$d@autosnap_${stamp}_hourly"; made=$((made+1))
  if [ "$hour" = 00 ]; then zfs snapshot "$d@autosnap_${stamp}_daily"; made=$((made+1)); fi
  while read -r n c; do
    case $n in
      *@autosnap_*_hourly) [ "$c" -lt $((now - 48*3600)) ] || continue ;;
      *@autosnap_*_daily)  [ "$c" -lt $((now - 30*86400)) ] || continue ;;
      *) continue ;;
    esac
    if [ -n "$(zfs holds -H "$n")" ]; then log "kept (held): $n"; continue; fi
    zfs destroy "$n"; pruned=$((pruned+1))
  done < <(zfs list -Hp -t snapshot -o name,creation -d 1 "$d")
done
log "snapshots made $made, pruned $pruned"
date +%s > "$state/replica-snap.last"
