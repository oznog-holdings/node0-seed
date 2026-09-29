#!/usr/bin/env bash
# Ensure a login item exists in the Seed/routine collection with a generated password (never
# displayed). Idempotent: an existing item of that name is left untouched.
# Usage: vault-ensure.sh <name> <username> <notes> [length] [charset flags for bw generate]
# It creates in the vault tools/vault-env.sh picks: the site's Vaultwarden by default. If the item
# belongs in the break-glass set, add it to tools/vault-breakglass.txt and run
# tools/vault-breakglass.sh sync.
set -euo pipefail
name=$1 user=$2 notes=$3 len=${4:-40} flags=${5:--ulns}
. "${SEED_REPO:-/work/agent/seed-lab}/tools/vault-env.sh"   # the site vault (SEED_VAULT=hosted: break-glass)
BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null); export BW_SESSION; unset BW_PASSWORD BW_CLIENTSECRET
trap 'bw lock >/dev/null 2>&1' EXIT
bw sync >/dev/null
if bw list items --search "$name" | jq -e --arg n "$name" 'map(select(.name==$n)) | length > 0' >/dev/null; then echo "exists: $name"; exit 0; fi
org=$(bw list organizations | jq -r '.[]|select(.name=="Seed").id'); col=$(bw list collections --organizationid "$org" | jq -r '.[]|select(.name=="routine").id')
[[ -n $org && -n $col ]] || { echo "org/collection lookup failed"; exit 1; }
bw get template item | PW=$(bw generate $flags --length "$len") N="$name" U="$user" NOTES="$notes" O="$org" C="$col" \
  jq '.organizationId=env.O | .collectionIds=[env.C] | .name=env.N | .notes=env.NOTES | .fields=[] | .login={username:env.U,password:env.PW,uris:[]}' \
  | bw encode | bw create item | jq -r '"created: " + .name'
