#!/usr/bin/env bash
# ntfy-alertmanager-password.sh: Alertmanager signs in to core's ntfy by password (basic auth), not by token
# (20261003). ntfy 2.28's token path fails a few concurrent publishes with 403 "forbidden" for a valid user: 4-8 in 200
# when 20 go at once, as Alertmanager sends one webhook per group in the same second; basic auth: 0 in 200 (measured on
# core's own binary, evidence/20261003-ntfy-403). Alertmanager doesn't retry a 4xx: those alerts were lost.
#   1. the vault: "ntfy core alertmanager password" (login alertmanager, a generated password), made if absent
#   2. infra: /mnt/data/system/secrets/monitoring/ntfy-core-password (0400, as the other files there), for
#      alertmanager.yml's basic_auth password_file
# The value goes vault -> pipe -> file: never printed, never an argument. core's side is tools/core-secrets-make.sh
# (the bcrypt hash of this item for the alertmanager user), then a core deploy.
set -euo pipefail
cd "$(dirname "$0")/.."
ITEM="ntfy core alertmanager password"; F=/mnt/data/system/secrets/monitoring/ntfy-core-password
mkdir -p /tmp/reh; exec 9>/tmp/reh/bw.lock; flock 9   # the lock every vault user here shares
. tools/vault-env.sh; BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null); export BW_SESSION; unset BW_PASSWORD BW_CLIENTSECRET
trap 'bw lock >/dev/null 2>&1' EXIT
bw sync >/dev/null
n=$(bw list items --search "$ITEM" | jq --arg n "$ITEM" '[.[] | select(.name == $n)] | length')
if [ "$n" = 0 ]; then
  ref=$(bw list items --search "ntfy core alertmanager" | jq -c '[.[] | select(.name == "ntfy core alertmanager")][0] | {organizationId, collectionIds}')
  bw get template item | jq --arg n "$ITEM" --argjson r "$ref" --rawfile p <(bw generate -uln --length 40) \
    '.name = $n | .organizationId = $r.organizationId | .collectionIds = $r.collectionIds | .notes = "core ntfy: Alertmanager on infra signs in by password (basic auth), 20261003; tools/ntfy-alertmanager-password.sh" | .login = {username: "alertmanager", password: ($p | rtrimstr("\n"))}' \
    | bw encode | bw create item >/dev/null && echo "vault: $ITEM made"
  bw sync >/dev/null
elif [ "$n" != 1 ]; then echo "vault: $n items named '$ITEM'" >&2; exit 1; else echo "vault: $ITEM present"; fi
bw get password "$ITEM" | ssh -o BatchMode=yes -o LogLevel=ERROR root@192.168.1.10 "umask 077; cat > $F.new && chown 65534 $F.new && chmod 0400 $F.new && mv $F.new $F && echo \"infra: $F written (\$(stat -c '%U %a %s' $F) bytes)\""
bw get password "$ITEM" | sha256sum | cut -c1-12 | sed 's/^/vault value sha256 /'
ssh -o BatchMode=yes -o LogLevel=ERROR root@192.168.1.10 "sha256sum < $F | cut -c1-12 | sed 's/^/infra file sha256 /'"
