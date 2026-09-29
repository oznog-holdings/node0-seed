#!/usr/bin/env bash
# rpcd (ubus over HTTP) session on the router, the backend LuCI itself uses. The root
# password goes vault -> jq -> the JSON body on stdin; never argv, never a file.
# Usage: router-ubus.sh login   -> writes the session id to $STATE/sid (0600)
#        router-ubus.sh call <object> <method> '<json args>'
set -euo pipefail
STATE=${ROUTER_STATE:-$HOME/.local/state/seed/router}; mkdir -p "$STATE"; chmod 700 "$STATE"
U=http://192.168.1.1/ubus
case "$1" in
login)
  . "${SEED_REPO:-/work/agent/seed-lab}/tools/vault-env.sh"   # the site vault (SEED_VAULT=hosted: break-glass)
  BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null); export BW_SESSION
  unset BW_PASSWORD BW_CLIENTSECRET
  sid=$(bw get item 'router root' 2>/dev/null \
    | jq -c '{jsonrpc:"2.0",id:1,method:"call",params:["00000000000000000000000000000000","session","login",{username:.login.username,password:.login.password,timeout:1800}]}' \
    | curl -s -X POST --data-binary @- "$U" | jq -r '.result[1].ubus_rpc_session // empty')
  bw lock >/dev/null
  [[ -n "$sid" ]] || { echo "login failed"; exit 1; }
  umask 077; printf '%s' "$sid" > "$STATE/sid"; echo "login ok";;
call)
  sid=$(cat "$STATE/sid")
  jq -nc --arg s "$sid" --arg o "$2" --arg m "$3" --argjson a "${4:-{\}}" \
    '{jsonrpc:"2.0",id:1,method:"call",params:[$s,$o,$m,$a]}' | curl -s -X POST --data-binary @- "$U";;
esac
