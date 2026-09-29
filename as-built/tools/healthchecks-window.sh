#!/usr/bin/env bash
# A planned-outage window for the external dead-man (Healthchecks.io check "seed monitoring
# dead-man", slug seed-watchdog), so a planned test doesn't page the owner.
#   healthchecks-window.sh status   status, manual_resume, last ping
#   healthchecks-window.sh pause    manual_resume=true (else the next ping un-pauses it), then pause
#   healthchecks-window.sh resume   resume, manual_resume back to false, then wait for a ping (up)
# Healthchecks.io: "a paused check is re-activated by the next ping" unless manual_resume is set;
# Alertmanager pings every 1 to 2 min, so a bare pause taken before the shutdown undoes itself.
# API key: vault "healthchecks api key" (read-write), sent as a header from a pipe, never argv.
set -euo pipefail
API=https://healthchecks.io/api/v3/checks; SLUG=seed-watchdog
. "${SEED_REPO:-/work/agent/seed-lab}/tools/vault-env.sh"   # the site vault (SEED_VAULT=hosted: break-glass)
S=$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null); unset BW_PASSWORD BW_CLIENTSECRET
K=$(BW_SESSION=$S bw get password 'healthchecks api key' 2>/dev/null); BW_SESSION=$S bw lock >/dev/null 2>&1; unset S
[ -n "$K" ] || { echo "no API key"; exit 1; }
H() { curl -sf -m 20 -H @<(printf 'X-Api-Key: %s\n' "$K") "$@"; }
uuid=$(H "$API/" | jq -r --arg s $SLUG '.checks[] | select(.slug==$s) | .uuid')
[[ $uuid =~ ^[0-9a-f-]{36}$ ]] || { echo "check $SLUG not found"; exit 1; }
show() { H "$API/$uuid" | jq -r '"\(now | todate) \(.slug): status=\(.status) manual_resume=\(.manual_resume) last_ping=\(.last_ping) timeout=\(.timeout)s grace=\(.grace)s"'; }
case "${1:-status}" in
status) show ;;
pause)
  H -X POST "$API/$uuid" -H 'Content-Type: application/json' -d '{"manual_resume": true}' >/dev/null
  H -X POST "$API/$uuid/pause" >/dev/null
  show ;;
resume)
  H -X POST "$API/$uuid/resume" >/dev/null
  H -X POST "$API/$uuid" -H 'Content-Type: application/json' -d '{"manual_resume": false}' >/dev/null
  show
  for i in $(seq 1 40); do [ "$(H "$API/$uuid" | jq -r .status)" = up ] && break; sleep 15; done
  show ;;
*) echo "usage: $0 status|pause|resume"; exit 2 ;;
esac
