#!/bin/bash
# Forgejo to B2 (deviation D.03; design › Backups: "the Forgejo data" is in the B2 set).
# (1) forgejo dump, the app's own consistent dump (R1.61); (2) a git bundle of every repo of
# record, the "bare mirror of the config repo" for the recovery pack; (3) restic, --host pinned.
# Fails closed: an empty dump, a dump without its database or a bundle that doesn't verify
# stops it before restic runs. Writes a completion timestamp (R1.79).
set -euo pipefail
umask 077
OUT=/mnt/data/appdata/forgejo/dumps; BIN=$(dirname "$0"); ts=$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p $OUT /mnt/data/system/seed-state
docker exec forgejo forgejo dump --type tar.gz --file - > $OUT/forgejo-dump-$ts.tar.gz 2>/dev/null
[ -s $OUT/forgejo-dump-$ts.tar.gz ] || { echo "empty dump"; exit 2; }
tar tzf $OUT/forgejo-dump-$ts.tar.gz | grep -qx 'forgejo-db.sql' || { echo "dump has no forgejo-db.sql"; exit 3; }
for r in seed/seed-lab; do
  b=$OUT/${r//\//_}-$ts.bundle
  docker exec forgejo git -C /var/lib/gitea/git/repositories/$r.git bundle create - --all > "$b" 2>/dev/null
  docker exec -i forgejo sh -c 'rm -rf /tmp/vb && git init -q /tmp/vb && cat > /tmp/vb.bundle && git -C /tmp/vb bundle verify /tmp/vb.bundle >/dev/null 2>&1; rc=$?; rm -rf /tmp/vb /tmp/vb.bundle; exit $rc' < "$b" \
    || { echo "bundle $r does not verify"; exit 4; }
done
echo "dump $(stat -c %s $OUT/forgejo-dump-$ts.tar.gz) bytes; bundles: $(ls $OUT/*-$ts.bundle | xargs -n1 basename | tr '\n' ' ')"
$BIN/restic.sh backup --host infra --tag forgejo $OUT
date +%s > /mnt/data/system/seed-state/forgejo-backup.last
