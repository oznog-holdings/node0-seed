#!/usr/bin/env bash
# Log into the Unraid web UI with the vault's `infra root user`, keeping the session cookie
# in a 0700 state dir outside every repo. The password goes vault -> stdin -> curl; it is
# never in argv, the environment of other processes, or any file.
set -euo pipefail
STATE=${UNRAID_STATE:-$HOME/.local/state/seed/unraid}
mkdir -p "$STATE"; chmod 700 "$STATE"
JAR="$STATE/cookies"; : > "$JAR"; chmod 600 "$JAR"
. "${SEED_REPO:-/work/agent/seed-lab}/tools/vault-env.sh"   # the site vault (SEED_VAULT=hosted: break-glass)
BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null); export BW_SESSION
unset BW_PASSWORD BW_CLIENTSECRET
item=$(bw get item 'infra root user' 2>/dev/null)
user=$(jq -r .login.username <<<"$item")
code=$(jq -j .login.password <<<"$item" | curl -s -o /dev/null -w '%{http_code}' -c "$JAR" -b "$JAR" \
  --data-urlencode "username=$user" --data-urlencode "password@-" http://192.168.1.10/login)
unset item; bw lock >/dev/null
# Success is judged by the UI itself: an authenticated GET of /Main must not bounce to /login.
main=$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' -b "$JAR" http://192.168.1.10/Main)
echo "login POST $code; GET /Main -> $main"
[[ "$main" == 200* ]]
