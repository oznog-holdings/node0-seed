#!/usr/bin/env bash
# The router's credential for lease updates (rung 5 › B): a non-expiring API token for ns1's user
# dhcp-router (made by site/dns/technitium/push: no groups, view and modify on lan.seed.example.com only),
# created by the admin and stored as the site vault item "technitium ddns router" (the password). The
# token goes API -> jq -> bw; never printed, never on disk. Once: it refuses if the item exists (to
# rotate: delete the session in Technitium, the item with the owner's approval, then run this again).
set -euo pipefail
cd "$(dirname "$0")/.."
. tools/vault-env.sh
BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null); export BW_SESSION; unset BW_PASSWORD BW_CLIENTSECRET
trap 'bw lock >/dev/null 2>&1 || true' EXIT
bw sync >/dev/null
items=$(bw list items)
[[ $(jq '[.[] | select(.name=="technitium ddns router")] | length' <<<"$items") == 0 ]] || { echo "exists: technitium ddns router"; exit 0; }
pw=$(jq -r '[.[] | select(.name=="technitium core admin")][0].login.password' <<<"$items")
org=$(bw list organizations | jq -r '.[]|select(.name=="Seed").id'); col=$(bw list collections --organizationid "$org" | jq -r '.[]|select(.name=="routine").id')
A=http://192.168.1.15:5380/api
tok=$(printf 'user=admin&pass=%s' "$(jq -rn --arg p "$pw" '$p|@uri')" | curl -sf --data-binary @- "$A/user/login" | jq -r .token); unset pw
# one token, straight into the vault item (a second, unstored token would be a credential nobody holds)
printf 'user=dhcp-router&tokenName=router%%20dhcp%%20leases' | curl -sf -H "Authorization: Bearer $tok" --data-binary @- "$A/admin/sessions/createToken" \
  | jq -r '.response.token' | { IFS= read -r t; [[ $t =~ ^[0-9a-f]{64}$ ]] || { echo "unexpected token form"; exit 1; }
    bw get template item | T="$t" O="$org" C="$col" jq '.organizationId=env.O | .collectionIds=[env.C] | .name="technitium ddns router"
      | .notes="Technitium ns1: API token of user dhcp-router (view and modify on lan.seed.example.com only). On the router as /etc/seed/ddns.token (site/router/config-tool). Rung 5." | .fields=[] | .login={username:"dhcp-router",password:env.T,uris:[]}' \
    | bw encode | bw create item | jq -r '"created: " + .name'; }
curl -sf -H "Authorization: Bearer $tok" -X POST "$A/user/logout" >/dev/null; unset tok
