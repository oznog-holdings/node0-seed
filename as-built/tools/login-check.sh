#!/usr/bin/env bash
# login-check.sh [run|create-checks|list]: every login the site depends on, checked with its cheapest real use, hourly
# (the agent box, user agent: ~/.config/systemd/user/login-check.timer). The orchestrator's brief, 20261024.
#   run             each login used once; each service's Healthchecks check pinged (success) or its fail endpoint hit
#                   with the failing logins' NAMES (never a value); a known expiry within 30 days fails it too
#   create-checks   the Healthchecks checks login-<service> (idempotent by slug; timeout 1 h, grace 30 min); their ping
#                   URLs into ~/.config/seed/login-check.pings (0600, never in git)
#   list            the logins and their service, no values
# Values: fetched from the vault by item name into variables, handed to curl on stdin (-K -) or a header from a
# pipe, never on an argv, never printed; unset after use. One check per service, not per login: Healthchecks' plan
# allows 20 checks (6 were in use), so a service's check names which of its logins failed.
# Proof: LOGIN_CHECK_BREAK=<login> uses a wrong copy of that one credential (the real one untouched);
# LOGIN_CHECK_ONLY=<service> runs one service; LOGIN_CHECK_DRY=1 pings nothing (prints only).
set -uo pipefail
cd "$(dirname "$0")/.."
PINGS=$HOME/.config/seed/login-check.pings; HCAPI=https://healthchecks.io/api/v3/checks
TENDER_TOKEN_EXPIRES=2027-09-29   # made 20260929 by `claude setup-token` (about a year; site/runbooks/hermes-sonnet-on-off.md)
WARN_DAYS=30
SERVICES=(claude-keel claude-tender vault forge healthchecks gateway zai ntfy backup netbox dns-net bots)
declare -A FAILS NOTES
fail() { FAILS[$1]+="${FAILS[$1]:+; }$2"; }
note() { NOTES[$1]+="${NOTES[$1]:+; }$2"; }
days_left() { echo $(( ( $(date -u -d "$1" +%s) - $(date -u +%s) ) / 86400 )); }

# --- the vault: one unlock per run; items by name, as JSON in an associative array, then wiped ---
declare -A ITEM
vault_open() { . tools/vault-env.sh
  BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null); unset BW_PASSWORD BW_CLIENTSECRET; export BW_SESSION
  [ -n "$BW_SESSION" ]; }
# by its exact name (bw get item matches prefixes: "gateway key agent" is ambiguous with "gateway key agentvm-*")
item() { [ -n "${ITEM[$1]+x}" ] || ITEM[$1]=$(bw list items --search "$1" 2>/dev/null | jq -c --arg n "$1" '[.[] | select(.name == $n)] | if length == 1 then .[0] else empty end'); printf '%s' "${ITEM[$1]}"; }
# the stored part, and what the vault's notes say to put before it
prefix() { case $1 in "litellm master key"|"gateway key "*|"tender gateway key") echo sk- ;; "ntfy core power"|"ntfy core watcher"|"ntfy orchestrator read"|"tender ntfy token") echo tk_ ;; esac; }
field() {   # field <item> <password|username>: the value, or a failure (no such item, an empty field); a wrong copy when
  local j v   # LOGIN_CHECK_BREAK names the item
  j=$(item "$1") && [ -n "$j" ] || return 1
  v=$(printf '%s' "$j" | jq -er ".login.$2 // empty") && [ -n "$v" ] || return 1
  if [ "$2" = password ]; then local p; p=$(prefix "$1"); case $v in "$p"*) ;; *) v="$p$v" ;; esac; fi
  if [ "${LOGIN_CHECK_BREAK:-}" = "$1" ] && [ "$2" = password ]; then v="${v:0:4}wrong-copy-for-the-login-check"; fi
  printf '%s' "$v"; }
# cq <value>: quoted for a curl config line (backslash and double quote escaped); a value with CR, LF or another
# control character is refused (Codex, 20261024: it could have injected curl options)
cq() { case $1 in *[[:cntrl:]]*) return 1 ;; esac; local v=${1//\\/\\\\}; v=${v//\"/\\\"}; printf '%s' "$v"; }
vault_close() { for k in "${!ITEM[@]}"; do ITEM[$k]=; done; unset ITEM; bw lock >/dev/null 2>&1; unset BW_SESSION; }

# http <expect> <url> <auth: bearer|token|ntoken|basic|header:NAME> <item> [method]: an authenticated read; 0 only when
# the credential was found, curl ran without error and the status is <expect>. The credential reaches curl in its
# config on stdin, quoted.
http() { local exp=$1 url=$2 auth=$3 it=$4 m=${5:-GET} pw us cfg code
  pw=$(field "$it" password) && pw=$(cq "$pw") || { echo "credential missing or malformed"; return 1; }
  if [ "$auth" = basic ]; then us=$(field "$it" username) && us=$(cq "$us") || { unset pw; echo "username missing or malformed"; return 1; }; fi
  case $auth in
    bearer) cfg="header = \"Authorization: Bearer $pw\"" ;;
    token)  cfg="header = \"Authorization: token $pw\"" ;;
    ntoken) cfg="header = \"Authorization: Token $pw\"" ;;
    basic)  cfg="user = \"$us:$pw\"" ;;
    header:*) cfg="header = \"${auth#header:}: $pw\"" ;;
  esac; unset pw us
  code=$(printf 'url = "%s"\n%s\n' "$url" "$cfg" | curl -s -m 30 ${INSECURE:+--insecure} -o /dev/null -w '%{http_code}' $([ "$m" = HEAD ] && echo --head || echo "-X $m") -K - 2>/dev/null) \
    || { unset cfg; echo "curl failed"; return 1; }
  unset cfg
  [ "$code" = "$exp" ] || { echo "HTTP ${code:-none}"; return 1; }; }
# (INSECURE=1 adds curl's --insecure: only the firewall's self-signed LAN cert)
use() { local svc=$1 login=$2; shift 2; local r; r=$("$@") || fail "$svc" "$login (${r:-failed})"; }

# --- the checks ---
check_claude_keel() {   # Keel's own Claude login (this account): auth status, then a one-word claude -p
  local d; d=$(mktemp -d); local out
  out=$(cd "$d" && timeout 120 claude auth status 2>&1) || { fail claude-keel "auth status failed"; rm -rf "$d"; return; }
  printf '%s' "$out" | grep -q -i -E '"loggedIn": *true|logged in' || fail claude-keel "auth status: not logged in"
  out=$(cd "$d" && timeout 180 claude -p 'Reply with exactly one word: ok' --max-turns 1 --no-session-persistence 2>&1 </dev/null)
  printf '%s' "$out" | grep -q -i '\bok\b' || fail claude-keel "claude -p gave no answer"
  rmdir "$d" 2>/dev/null || true
  local e; e=$(jq -r '.claudeAiOauth.refreshTokenExpiresAt // empty' ~/.claude/.credentials.json 2>/dev/null)
  if [ -n "$e" ] && [ "$e" != null ]; then local dl=$(( (e / 1000 - $(date +%s)) / 86400 ))
    # a refreshing login (about 30 days at a fresh sign-in), not a long-lived token: 7 days' warning, not 30
    [ "$dl" -gt 7 ] || fail claude-keel "the login's refresh token expires in $dl days: the owner signs Keel in again"; note claude-keel "refresh token: $dl days"; fi; }
check_claude_tender() {   # Tender's setup token, through the model client's wrapper (its own HOME: nothing of the agents')
  local out
  out=$(ssh -o BatchMode=yes -o LogLevel=ERROR -o ConnectTimeout=20 tender@localhost \
        'timeout 120 ~/.local/share/seed/claude-model auth status 2>&1; echo "rc=$?"; timeout 180 ~/.local/share/seed/claude-model -p "Reply with exactly one word: ok" --max-turns 1 --no-session-persistence 2>&1 </dev/null' 2>&1)
  printf '%s' "$out" | grep -q '^rc=0' || fail claude-tender "auth status failed"
  printf '%s' "$out" | sed -n '/^rc=/,$p' | grep -q -i '\bok\b' || fail claude-tender "claude -p gave no answer"
  local dl; dl=$(days_left "$TENDER_TOKEN_EXPIRES")
  [ "$dl" -gt "$WARN_DAYS" ] || fail claude-tender "the token expires in $dl days ($TENDER_TOKEN_EXPIRES): renew it (hermes-sonnet-on-off.md)"
  note claude-tender "token: $dl days"; }
check_vault() { bw sync >/dev/null 2>&1 || fail vault "bw sync (the API login) failed"; }
check_forge() { local F=https://git.seed.example.com/api/v1/user
  use forge "forgejo seed-builder" http 200 "$F" basic "forgejo seed-builder"
  use forge "tender forge token" http 200 "$F" token "tender forge token"
  # scope write:repository: /user is forbidden to it, the repository it checks is not
  use forge "forgejo seed-buildcheck token" http 200 https://git.seed.example.com/api/v1/repos/seed/seed-lab token "forgejo seed-buildcheck token"; }
check_healthchecks() { use healthchecks "healthchecks api key" http 200 "$HCAPI/" header:X-Api-Key "healthchecks api key"; }
check_gateway() { local G=https://gw.seed.example.com/v1/models
  for k in "tender gateway key" "gateway key agent" "gateway key monitoring-probe" "litellm master key"; do use gateway "$k" http 200 "$G" bearer "$k"; done
  use gateway "compute llama api key" http 200 http://compute.seed.example.com:8080/v1/models bearer "compute llama api key"; }
check_zai() { use zai "zai api key" http 200 https://api.z.ai/api/coding/paas/v4/models bearer "zai api key"; }
check_ntfy() {   # /v1/account answers anonymous callers too: the account it names must be a real user
  # tokens (tk_) by Bearer; Alertmanager (by password since 20261003) and the phone by user and password
  local k c u
  for k in "ntfy core power" "ntfy core watcher" "tender ntfy token" "ntfy orchestrator read" "ntfy core alertmanager password" "ntfy core phone"; do
    case $k in
      *password|*phone) c=$(field "$k" username) && c=$(cq "$c") && u=$(field "$k" password) && u=$(cq "$u") && c="user = \"$c:$u\"" ;;
      *) u=$(field "$k" password) && u=$(cq "$u") && c="header = \"Authorization: Bearer $u\"" ;;
    esac || { unset c u; fail ntfy "$k (credential missing or malformed)"; continue; }
    u=$(printf 'url = "https://ntfy.seed.example.com/v1/account"\n%s\n' "$c" | curl -sf -m 30 -K - 2>/dev/null | jq -r '.username // empty') || u=
    unset c
    [ -n "$u" ] && [ "$u" != "*" ] || fail ntfy "$k (not signed in)"; done; }
check_backup() {
  for k in "b2 seed-writer" "b2 seed-machines-writer" "b2 seed-restore-reader"; do
    use backup "$k" http 200 https://api.backblazeb2.com/b2api/v4/b2_authorize_account basic "$k"; done
  for k in agent agentvm compute; do use backup "rest-server $k" http 200 "https://rest.seed.example.com/$k/config" basic "rest-server $k" HEAD; done; }
check_netbox() { use netbox "netbox api token builder" http 200 'https://netbox.seed.example.com/api/dcim/sites/?limit=1' ntoken "netbox api token builder"; }
check_dns_net() {
  use dns-net "dnsimple example.com" http 200 https://api.dnsimple.com/v2/whoami bearer "dnsimple example.com"
  INSECURE=1 use dns-net "opnsense api root" http 200 https://192.168.1.1/api/core/firmware/status basic "opnsense api root"   # the fw's own self-signed cert, LAN only
  # the tailnet's node keys (no secret): any node whose key expires within WARN_DAYS
  local exp; exp=$(tailscale status --json 2>/dev/null | jq -r --argjson w "$WARN_DAYS" '[.Self] + [.Peer[]?] | .[] | select(.KeyExpiry != null) | select((.KeyExpiry | sub("\\.[0-9]+";"") | fromdateiso8601) - now < ($w * 86400)) | .HostName' | paste -sd, -)
  [ -z "$exp" ] || fail dns-net "tailnet node keys expiring within $WARN_DAYS days: $exp"; }
check_bots() {
  local t r; t=$(field "telegram tender bot" password) && t=$(cq "$t") || { fail bots "telegram tender bot (credential missing or malformed)"; t=; }
  if [ -n "$t" ]; then r=$(printf 'url = "https://api.telegram.org/bot%s/getMe"\n' "$t" | curl -sf -m 30 -K - 2>/dev/null | jq -r '.ok // false') || r=false
    [ "$r" = true ] || fail bots "telegram tender bot (getMe: not ok)"; fi; unset t
  use bots "huggingface read token" http 200 https://huggingface.co/api/whoami-v2 bearer "huggingface read token"; }

run() {
  local only=${LOGIN_CHECK_ONLY:-} s
  local dry=${LOGIN_CHECK_DRY:-}
  [ -n "$dry" ] || [ -r "$PINGS" ] || { echo "no $PINGS: run create-checks first"; exit 1; }
  declare -A PING; [ -n "$dry" ] || while read -r s u; do PING[$s]=$u; done < "$PINGS"
  if ! vault_open; then FAILS[vault]="the vault won't unlock (the API login or the password)"
    for s in "${SERVICES[@]}"; do [ "$s" = vault ] || [ "$s" = claude-keel ] || [ "$s" = claude-tender ] || NOTES[$s]="not checked: the vault is shut"; done
  fi
  for s in "${SERVICES[@]}"; do
    [ -z "$only" ] || [ "$only" = "$s" ] || continue
    if [ -z "${NOTES[$s]+x}" ] || [ "${NOTES[$s]}" != "not checked: the vault is shut" ]; then "check_${s//-/_}"; fi
  done
  [ -z "${BW_SESSION:-}" ] || vault_close
  for s in "${SERVICES[@]}"; do
    [ -z "$only" ] || [ "$only" = "$s" ] || continue
    if [ -n "$dry" ]; then if [ -n "${FAILS[$s]:-}" ]; then echo "$s: FAILED: ${FAILS[$s]} [dry]"; else echo "$s: ok${NOTES[$s]:+ (${NOTES[$s]})} [dry]"; fi; continue; fi
    local u=${PING[$s]:-}; [ -n "$u" ] || { echo "$s: no ping URL"; continue; }
    if [ -n "${FAILS[$s]:-}" ]; then
      printf '%s' "login-check $(date -u +%FT%TZ): FAILED: ${FAILS[$s]}" | curl -s -m 20 --data-binary @- -K <(printf 'url = "%s/fail"\n' "$u") >/dev/null
      echo "$s: FAILED: ${FAILS[$s]}"
    elif [ "${NOTES[$s]:-}" = "not checked: the vault is shut" ]; then echo "$s: not checked (the vault is shut; its check will miss this ping)"
    else
      printf '%s' "login-check $(date -u +%FT%TZ): ok${NOTES[$s]:+ (${NOTES[$s]})}" | curl -s -m 20 --data-binary @- -K <(printf 'url = "%s"\n' "$u") >/dev/null
      echo "$s: ok${NOTES[$s]:+ (${NOTES[$s]})}"
    fi; done; }

create_checks() {
  vault_open || { echo "the vault won't unlock"; exit 1; }
  local K; K=$(item 'healthchecks api key' | jq -r '.login.password'); vault_close
  umask 077; mkdir -p "$(dirname "$PINGS")"; : > "$PINGS.new"
  for s in "${SERVICES[@]}"; do
    local body; body=$(jq -n --arg n "login-$s" --arg d "The login check ($s): every hour, each of its logins used once (tools/login-check.sh). A fail ping names the failed login; silence = the checker itself stopped." \
      '{name:$n, slug:$n, desc:$d, timeout:3600, grace:1800, unique:["slug"], channels:"*", tags:"seed login-check"}')
    local u; u=$(printf '%s' "$body" | curl -s -m 20 -X POST -H @<(printf 'X-Api-Key: %s\n' "$K") -H 'Content-Type: application/json' --data-binary @- "$HCAPI/" | jq -r '.ping_url // empty')
    [ -n "$u" ] || { echo "login-$s: not created"; continue; }
    echo "$s $u" >> "$PINGS.new"; echo "login-$s: ready"; done
  mv "$PINGS.new" "$PINGS"; unset K; }

case ${1:-run} in
  run) run ;;
  create-checks) create_checks ;;
  list) grep -oE '(use|fail) [a-z-]+ "[^"]+"' "$0" | sort -u ;;
  *) sed -n '2,16p' "$0"; exit 64 ;;
esac
