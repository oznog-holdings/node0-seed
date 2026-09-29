#!/bin/bash
# Nightly application dumps on infra (design › Backups: "database consistency comes from the
# application's own nightly dump, never from copying a live data directory", R1.61).
# Each dump is checked before it counts; any failure exits non-zero before the timestamp is
# written, so the monitoring sees a stale "last success" (R1.79) rather than a false green.
# Backrest's daily plan to B2 then backs up the dumps directories (flow 1).
# Local dumps are kept; removing old ones is a separate, verified step (principle 10).
set -euo pipefail
umask 077   # dumps hold password hashes and tokens
ts=$(date -u +%Y%m%dT%H%M%SZ); state=/mnt/data/system/seed-state; mkdir -p $state
log() { echo "$(date -u +%FT%TZ) $*"; }

# Vaultwarden: its own backup command (a consistent SQLite copy), integrity-checked, plus the key
V=/mnt/data/appdata/vaultwarden; mkdir -p $V/dumps
docker exec vaultwarden /vaultwarden backup >/dev/null
new=$(ls -t $V/data/db_*.sqlite3 | head -1); mv "$new" "$V/dumps/"; f=$V/dumps/$(basename "$new")
[ "$(docker run --rm -v $V/dumps:$V/dumps:ro seed/sqlite:alpine3.24 "$f" 'PRAGMA integrity_check;')" = ok ]
[ -s $V/data/rsa_key.pem ]
log "vaultwarden $(basename "$f") ok"

# Forgejo: forgejo dump (with its database) and a verified bundle of every repo of record
F=/mnt/data/appdata/forgejo/dumps; mkdir -p $F
docker exec forgejo forgejo dump --type tar.gz --file - > $F/forgejo-dump-$ts.tar.gz 2>/dev/null
tar tzf $F/forgejo-dump-$ts.tar.gz | grep -qx 'forgejo-db.sql'
for r in $(docker exec forgejo sh -c 'cd /var/lib/gitea/git/repositories && ls -d */*.git' | sed 's/\.git$//'); do
  b=$F/${r//\//_}-$ts.bundle
  docker exec forgejo git -C /var/lib/gitea/git/repositories/$r.git bundle create - --all > "$b" 2>/dev/null
  docker exec -i forgejo sh -c 'rm -rf /tmp/vb && git init -q /tmp/vb && cat > /tmp/vb.bundle && git -C /tmp/vb bundle verify /tmp/vb.bundle >/dev/null 2>&1; rc=$?; rm -rf /tmp/vb /tmp/vb.bundle; exit $rc' < "$b"
done
log "forgejo dump and bundles ok"

# Postgres: one custom-format dump per database, listed back by pg_restore before it counts
P=/mnt/data/appdata/postgres/dumps; mkdir -p $P
for db in $(docker exec postgres psql -U postgres -Atc "select datname from pg_database where not datistemplate and datname <> 'postgres'"); do
  docker exec postgres pg_dump -U postgres -Fc "$db" > $P/$db-$ts.dump
  n=$(docker exec -i postgres pg_restore --list < $P/$db-$ts.dump | grep -c 'TABLE DATA' || true)
  [ "$n" -gt 0 ] || { log "postgres $db: dump lists no table data"; exit 5; }
  log "postgres $db: $n tables with data"
done

date +%s > $state/seed-dumps.last
