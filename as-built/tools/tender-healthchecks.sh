#!/usr/bin/env bash
# The site agents' heartbeats (briefs/agents.md › G): Healthchecks.io checks in the site's project, made idempotently
# (by slug), each ping URL stored in the site vault as "tender hc <name>" (then tools/tender-bundle-make.sh puts it
# in sops for tender). A new check is "new" until its first ping and alerts nobody before that.
#   tender-hermes-work   pinged by Hermes only when its periodic task in its session completes (intake read, log written)
#   tender-claude-work   the same for Claude Code
#   tender-qwen-route    pinged by a host timer when the gateway's local-embed route (compute's resident embedder) answers with tender's key
#   tender-telegram      pinged by a host timer when Hermes's gateway reports Telegram connected
# Timing (timeout, grace): Claude Code and the host checks 15 + 10 min (tasks every 10 or 5 min). Hermes 30 + 20 min:
# its task runs every 15 min and, with Qwen to itself, a run with a small replay took 8.5 min (20260930); an
# incident takes longer, and a tighter check would page the owner exactly when Hermes is busy. Existing checks updated.
set -euo pipefail
cd "$(dirname "$0")/.."
API=https://healthchecks.io/api/v3/checks
. tools/vault-env.sh
S=$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null); unset BW_PASSWORD BW_CLIENTSECRET
K=$(BW_SESSION=$S bw get password 'healthchecks api key' 2>/dev/null); BW_SESSION=$S bw lock >/dev/null 2>&1; unset S
[ -n "$K" ] || { echo "no API key"; exit 1; }
H() { curl -sf -m 20 -H @<(printf 'X-Api-Key: %s\n' "$K") "$@"; }
declare -A TIMING=([tender-hermes-work]="1800 1200" [tender-claude-work]="900 600" [tender-qwen-route]="900 600" [tender-telegram]="900 600")
declare -A DESC=(
  [tender-hermes-work]="Hermes (site agent) completed its periodic task: intake read, log written. Silent = Hermes stuck, dead, or its intake broken."
  [tender-claude-work]="Claude Code (site agent) completed its periodic task: intake read, log written. Silent = Claude Code stuck, dead, or its intake broken."
  [tender-qwen-route]="The gateway's local-embed route (compute's resident embedder; the chat models load on demand from the same server) answered the site agents' key. Silent = compute's models are unreachable."
  [tender-telegram]="Hermes's gateway reports Telegram connected. Silent = Hermes can't reach the owner by chat.")
existing=$(H "$API/")
for slug in tender-hermes-work tender-claude-work tender-qwen-route tender-telegram; do
  ping=$(jq -r --arg s "$slug" '.checks[] | select(.slug==$s) | .ping_url' <<<"$existing")
  read -r to gr <<<"${TIMING[$slug]}"
  body=$(jq -nc --arg n "$slug" --arg d "${DESC[$slug]}" --argjson to "$to" --argjson gr "$gr" '{name: $n, slug: $n, desc: $d, tags: "site-agents", timeout: $to, grace: $gr, channels: "*", unique: ["slug"]}')
  if [ -z "$ping" ]; then
    ping=$(H -X POST -H 'Content-Type: application/json' -d "$body" "$API/" | jq -r .ping_url)
    echo "created $slug"
  else
    uuid=$(jq -r --arg s "$slug" '.checks[] | select(.slug==$s) | .update_url | split("/") | last' <<<"$existing")
    H -X POST -H 'Content-Type: application/json' -d "$body" "$API/$uuid" | jq -r '"exists \(.slug): timeout \(.timeout) s, grace \(.grace) s"'
  fi
  [[ $ping == https://hc-ping.com/* ]] || { echo "no ping URL for $slug"; exit 1; }
  printf '%s' "$ping" | tools/vault-put.sh "tender hc ${slug#tender-}" tender "Healthchecks ping URL for $slug (the site agents' heartbeats; tools/tender-healthchecks.sh)" 2>&1 | grep -v '^exists' || true
done
unset K
