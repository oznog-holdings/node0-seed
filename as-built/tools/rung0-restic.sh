#!/bin/bash
# Rung 0, the laptop flow: restic to the seed bucket over B2's S3 endpoint.
# Credentials fetched from the vault at run time into this process only, then unset; never printed.
# Usage: rung0-restic.sh <restic args...>   e.g.  rung0-restic.sh snapshots
#        rung0-restic.sh backup-now          (the pinned plan: fail-closed source check, then backup)
set -euo pipefail
REPO="s3:https://s3.us-east-005.backblazeb2.com/your-seed-bucket/restic/laptop"
HOST="laptop"                                   # pinned (design: Backups, --host)
SOURCES=( "$HOME/seed-data/documents" "$HOME/seed-data/finance" "$HOME/seed-data/photos" "$HOME/work/seed-lab" )
. "${SEED_REPO:-/work/agent/seed-lab}/tools/vault-env.sh"   # the site vault (SEED_VAULT=hosted: break-glass)
export BW_SESSION; BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null); unset BW_PASSWORD BW_CLIENTSECRET
bw sync >/dev/null
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY RESTIC_PASSWORD
AWS_ACCESS_KEY_ID=$(bw get username "b2 seed-writer"); AWS_SECRET_ACCESS_KEY=$(bw get password "b2 seed-writer")
RESTIC_PASSWORD=$(bw get password "restic seed laptop")
bw lock >/dev/null; unset BW_SESSION BW_CLIENTID
trap 'unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY RESTIC_PASSWORD' EXIT
if [ "${1:-}" = backup-now ]; then
  for s in "${SOURCES[@]}"; do            # fail closed: a missing or empty source is an error, not an empty backup
    [ -d "$s" ] && [ -n "$(find "$s" -mindepth 1 -print -quit)" ] || { echo "source missing or empty: $s" >&2; exit 3; }
  done
  exec restic -r "$REPO" backup --host "$HOST" --tag rung0 "${SOURCES[@]}"
fi
exec restic -r "$REPO" "$@"
