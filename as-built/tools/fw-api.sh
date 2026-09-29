#!/usr/bin/env bash
# OPNsense's API on the firewall (fw, 192.168.1.2 until the cut-over): fw-api.sh <GET|POST> <path under /api> [json].
# The key is the vault item "opnsense api root" (username = key, password = secret), vault -> curl's config on stdin,
# never argv. The GUI's self-signed certificate is pinned by its public key (taken 20260929; re-pin if it's renewed).
# Every read of the configuration goes through the redacting export instead (seed-config-export), never config.xml.
set -euo pipefail
FW=${FW:-192.168.1.2}; PIN='sha256//YOUR-FIREWALL-CERTIFICATE-PIN'
. "${SEED_REPO:-/work/agent/seed-lab}/tools/vault-env.sh"
BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null); export BW_SESSION; unset BW_PASSWORD BW_CLIENTSECRET
it=$(bw get item 'opnsense api root'); bw lock >/dev/null 2>&1; unset BW_SESSION
jq -r '"user = \"\(.login.username):\(.login.password)\""' <<<"$it" | curl -s -k --pinnedpubkey "$PIN" -K - -X "$1" \
  ${3:+-H 'Content-Type: application/json' -d "$3"} "https://$FW/api/$2"; echo
