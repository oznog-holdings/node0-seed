#!/usr/bin/env bash
# Store a value made elsewhere (an API token, a generated key) as a login item in the site vault's Seed/routine
# collection: the value arrives on stdin (a pipe from where it was made), never argv, never printed.
# Refuses if an item of that name exists (a rotation replaces it by hand, with the owner's approval).
# Usage: <producer> | vault-put.sh <name> <username> <notes>
set -euo pipefail
name=${1:?name}; user=${2:?username}; notes=${3:?notes}
val=$(cat); [ -n "$val" ] || { echo "empty value on stdin: nothing stored"; exit 1; }
. "${SEED_REPO:-/work/agent/seed-lab}/tools/vault-env.sh"
BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null); export BW_SESSION; unset BW_PASSWORD BW_CLIENTSECRET
trap 'bw lock >/dev/null 2>&1 || true; unset val' EXIT
bw sync >/dev/null
if bw list items --search "$name" | jq -e --arg n "$name" 'map(select(.name==$n)) | length > 0' >/dev/null; then echo "exists: $name (nothing stored)"; exit 1; fi
org=$(bw list organizations | jq -r '.[]|select(.name=="Seed").id'); col=$(bw list collections --organizationid "$org" | jq -r '.[]|select(.name=="routine").id')
[[ -n $org && -n $col ]] || { echo "org/collection lookup failed"; exit 1; }
bw get template item | PW="$val" N="$name" U="$user" NOTES="$notes" O="$org" C="$col" \
  jq '.organizationId=env.O | .collectionIds=[env.C] | .name=env.N | .notes=env.NOTES | .fields=[] | .login={username:env.U,password:env.PW,uris:[]}' \
  | bw encode | bw create item | jq -r '"created: " + .name'
