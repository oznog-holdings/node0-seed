#!/bin/bash
# Vaultwarden to B2 (deviation D.01; design › Backups). The app's own dump (R1.61), checked,
# then restic with --host pinned. Fails closed: no dump, a bad dump or a missing key stops it
# before restic runs. Writes a completion timestamp for the monitoring (R1.79).
set -euo pipefail
umask 077
D=/mnt/data/appdata/vaultwarden; OUT=$D/dumps; BIN=$(dirname "$0")
mkdir -p $OUT /mnt/data/system/restic-cache /mnt/data/system/restore-test /mnt/data/system/seed-state
docker exec vaultwarden /vaultwarden backup
new=$(ls -t $D/data/db_*.sqlite3 | head -1); [ -n "$new" ]
mv "$new" "$OUT/"; f=$OUT/$(basename "$new")
chk=$(docker run --rm -v $OUT:$OUT:ro seed/sqlite:alpine3.24 "$f" 'PRAGMA integrity_check;')
[ "$chk" = ok ] || { echo "integrity_check: $chk"; exit 2; }
[ -s $D/data/rsa_key.pem ] || { echo "rsa_key.pem missing"; exit 3; }
echo "dump $(basename "$f") $(stat -c %s "$f") bytes, integrity ok"
$BIN/restic.sh backup --host infra --tag vaultwarden --exclude "$D/data/db.sqlite3*" --exclude "$D/data/tmp" "$D"
date +%s > /mnt/data/system/seed-state/vaultwarden-backup.last
