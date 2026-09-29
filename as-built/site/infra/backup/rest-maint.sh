#!/bin/bash
# Nightly maintenance of the rest-server repositories (design › Backups, flow 2): "Forget and
# prune run nightly on the server, since the clients cannot delete, and that job is the one
# writer." It works on the repositories' directories directly, with each repository's own
# password (restic-rest.env), never through the append-only server.
# Retention (the pages give none; finding F-RETAIN): 48 hourly, 14 daily, 8 weekly,
# 12 monthly, 10 yearly, per host and path.
# Then (design: "an rclone mirror to a separate bucket ... from a ZFS snapshot taken after the
# maintenance window"): the snapshot and mirror step, ON since 20260924 (the switch file
# seed-state/mirror.enabled), with the replaced b2 seed-machines-writer: list, read and write
# only; upload and hide proven, permanent delete refused (401).
set -euo pipefail
umask 077
ENVF=/mnt/data/system/secrets/restic-rest.env; ROOT=/mnt/data/backups/rest; state=/mnt/data/system/seed-state
log() { echo "$(date -u +%FT%TZ) $*"; }
fail=0
for dir in "$ROOT"/*/; do
  m=$(basename "$dir"); [ -f "$dir/config" ] || { log "$m: not a repository, skipped"; continue; }
  pw=$(grep "^RESTIC_PASSWORD_$m=" "$ENVF" | cut -d= -f2-) || true
  [ -n "$pw" ] || { log "$m: no password in restic-rest.env"; fail=1; continue; }
  if printf '%s' "$pw" | docker run --rm -i --hostname infra -v "$ROOT:$ROOT" \
      restic/restic:0.19.1@sha256:136600b6ff6843d61d355f7f71f460a166429f35de6fd11b568fece3c9a4d510 \
      -r "$ROOT/$m" --password-command 'cat /dev/stdin' --no-cache \
      forget --prune --group-by host,paths \
      --keep-hourly 48 --keep-daily 14 --keep-weekly 8 --keep-monthly 12 --keep-yearly 10 2>&1 | tail -3; then
    date +%s > "$state/rest-maint-$m.last"; log "$m: forget and prune done"
  else log "$m: maintenance FAILED"; fail=1; fi
done
# The mirror (design: "an rclone mirror to a separate bucket ... from a ZFS snapshot taken
# after the maintenance window"; "the 30-day window stops the mirror mirroring a deletion").
# Only if maintenance succeeded and the switch file exists. Key: rclone-machines.env (0600,
# from "b2 seed-machines-writer": list/read/write, no delete). No --b2-hard-delete: files
# the sync removes become hidden versions, kept 30 days by the bucket's lifecycle rule.
if [ $fail = 0 ] && [ -f /mnt/data/system/seed-state/mirror.enabled ]; then
  snap="data/backups@mirror-$(date -u +%Y%m%dT%H%M%SZ)"; RC=rclone/rclone:1.75.1@sha256:45401ad7410db1d67ffdb58e19059ad20b0d8e0285a60e38bbec55cc1019c7a5
  zfs snapshot "$snap" && src=/mnt/data/backups/.zfs/snapshot/${snap#*@}/rest
  rc() { docker run --rm --env-file /mnt/data/system/secrets/rclone-machines.env -v "$src:/src:ro" $RC "$@"; }
  if rc sync /src b2m:your-seed-machines-bucket/rest --fast-list --transfers 4 --checksum 2>&1 | tail -3 \
     && rc check /src b2m:your-seed-machines-bucket/rest --one-way --fast-list 2>&1 | tail -2; then
    date +%s > "$state/mirror.last"; log "mirror: synced and checked from $snap"
  else log "mirror: FAILED from $snap"; fail=1; fi
  # the snapshot was only the frozen source for this run: destroyed as its own step, after the check
  zfs destroy "$snap" && log "mirror: $snap destroyed"
elif [ -f /mnt/data/system/seed-state/mirror.enabled ]; then
  log "mirror: skipped because maintenance failed"
else
  log "mirror: disabled (no mirror.enabled switch); no snapshot taken"
fi
[ $fail = 0 ] && date +%s > "$state/rest-maint.last"
exit $fail
