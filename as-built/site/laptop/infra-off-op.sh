#!/bin/bash
# The infra-off gate's one real operation, run on compute as seed (site/runbooks/laptop-infra-off-gate.md):
# with infra off and caches cold, restore a document of the site's from the offsite store (B2,
# flow 1), using credentials the laptop decrypts from core's secrets.age with its own key.
# It exercises the laptop's identity, name resolution without infra (external names through
# Technitium ns1 on core (ns2 is on infra) or the external fallbacks; the site's names from the hosts block), and the
# offsite path; restic runs with --no-cache, so nothing is served from the laptop's cache.
# Read-only on the bucket (--no-lock: the key is b2 seed-restore-reader from 20260927, which cannot
# write a lock). Secrets live in this process's environment only; the restored file
# goes to a 0700 directory that is deleted at the end. Prints names, sizes and hashes only.
set -euo pipefail
umask 077
export PATH=$HOME/.local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
REPO=$HOME/seed-lab; KEY=$HOME/.ssh/id_ed25519; ZONE=seed.example.com
FILE=${1:-/mnt/data/documents/doc-08.txt}
log() { echo "$(date -u +%FT%TZ) $*"; }
S="ssh -n -i $KEY -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=6"

log "infra: $(if $S root@infra.$ZONE true 2>/dev/null; then echo 'ANSWERS (the gate wants it off)'; else echo 'unreachable'; fi)"
log "resolve s3.us-east-005.backblazeb2.com: $(dscacheutil -q host -a name s3.us-east-005.backblazeb2.com | awk '/^ip_address:/{print $2; exit}')"
log "core by name: $($S admin@core.$ZONE 'cat /proc/sys/kernel/hostname') (ssh), ntfy $(curl -s -m 8 -o /dev/null -w '%{http_code}' https://ntfy.$ZONE/v1/health)"

set -a
eval "$(age -d -i "$KEY" "$REPO/site/core/secrets.age" | grep -E '^(AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|RESTIC_PASSWORD)=')"
set +a
[ -n "${AWS_ACCESS_KEY_ID:-}" ] && [ -n "${RESTIC_PASSWORD:-}" ] || { log "FAIL: the laptop key did not yield the credentials"; exit 1; }
log "credentials: decrypted from core's secrets.age with the laptop key (3 values, not shown)"
export RESTIC_REPOSITORY=s3:https://s3.us-east-005.backblazeb2.com/your-seed-bucket/restic/infra

snap=$(restic snapshots --no-lock --no-cache --json --host infra --path /mnt/data/documents --latest 1 | python3 -c 'import json,sys; s=json.load(sys.stdin)[-1]; print(s["short_id"], s["time"][:19])')
log "newest snapshot with the documents: $snap"
t=$(mktemp -d "$HOME/.local/state/seed/restore.XXXXXX"); trap 'rm -rf "$t"' EXIT
restic restore --no-lock --no-cache "${snap%% *}" --target "$t" --include "$FILE" --verify 2>&1 | tail -1
f=$t$FILE; [ -s "$f" ] || { log "FAIL: $FILE not restored"; exit 1; }
log "restored $FILE: $(wc -c < "$f" | tr -d ' ') bytes, sha256 $(shasum -a 256 "$f" | cut -c1-16), verified by restic against the snapshot"
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY RESTIC_PASSWORD
log "done: restored directory removed"
