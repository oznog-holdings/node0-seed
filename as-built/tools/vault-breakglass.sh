#!/usr/bin/env bash
# The two vaults after the D.01d flip (20260928): the site's Vaultwarden is the source for every item;
# the hosted Bitwarden org "Seed" keeps only the break-glass set (tools/vault-breakglass.txt).
#   check  (default)  every break-glass item is in both vaults with the same value (by the sha256 of a
#                     canonical form: name, notes, username, password, totp, uris, fields); `vaultwarden
#                     seed-builder` is hosted only by design. Every other hosted item is listed as "to
#                     delete", with its site counterpart checked the same way. Exit 1 on any fault.
#   sync              copy the break-glass items from the site vault to the hosted org where missing or
#                     different (never the other way; never an item outside the list)
#   trim --delete     delete from the hosted org every item outside the list whose site counterpart
#                     MATCHes; refuses if any of them doesn't. The owner's approval first (D.01d).
# Prints names, counts and MATCH/DIFF/MISSING only; never a value.
set -euo pipefail
cd "$(dirname "$0")"
mode=${1:-check}; [ "$mode" = trim ] && [ "${2:-}" != --delete ] && { echo "trim needs --delete (and the owner's approval)"; exit 2; }
HOSTED_ONLY="vaultwarden seed-builder"
mapfile -t KEEP < <(grep -v '^#' vault-breakglass.txt | cut -f1 | sed '/^$/d')
# the hosted org (bw.env) and the site vault (bw-local profile, bw-local.env), each in its own subshell env
H=$(set -a; . "$HOME/.config/seed/bw.env"; set +a; bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null </dev/null)
L=$(export BITWARDENCLI_APPDATA_DIR="$HOME/.config/seed/bw-local"; set -a; . "$HOME/.config/seed/bw-local.env"; set +a; bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null </dev/null)
HB() { BW_SESSION=$H bw --nointeraction "$@"; }; LB() { BITWARDENCLI_APPDATA_DIR="$HOME/.config/seed/bw-local" BW_SESSION=$L bw --nointeraction "$@"; }
trap 'HB lock >/dev/null 2>&1; LB lock >/dev/null 2>&1' EXIT
[ -n "$H" ] && [ -n "$L" ] || { echo "could not unlock both vaults"; exit 1; }
HB sync >/dev/null; LB sync >/dev/null
horg=$(HB list organizations | jq -r '.[]|select(.name=="Seed").id'); hcol=$(HB list collections --organizationid "$horg" | jq -r '.[]|select(.name=="routine").id')
lorg=$(LB list organizations | jq -r '.[]|select(.name=="Seed").id'); lcol=$(LB list collections --organizationid "$lorg" | jq -r '.[]|select(.name=="routine").id')
hitems=$(HB list items --organizationid "$horg"); litems=$(LB list items --organizationid "$lorg")
canon='{name, notes, u: .login.username, p: .login.password, t: .login.totp, uris: ([(.login.uris // [])[].uri] | sort), f: ([(.fields // [])[] | {name, value, type}] | sort_by(.name))}'
dig() { N="$2" jq -r --arg c "$canon" '[.[] | select(.name==env.N)] | if length==1 then .[0] | '"$canon"' | tojson else (length|tostring) + " items" end' <<<"$1" | sha256sum | cut -c1-16; }
count() { N="$2" jq '[.[] | select(.name==env.N)] | length' <<<"$1"; }
state() {  # hosted-json site-json name -> MATCH | DIFF | MISSING(site) | MISSING(hosted) | DUPLICATE
  local nh nl; nh=$(count "$1" "$3"); nl=$(count "$2" "$3")
  if [ "$nh" -gt 1 ] || [ "$nl" -gt 1 ]; then echo DUPLICATE; elif [ "$nl" = 0 ]; then echo "MISSING(site)"; elif [ "$nh" = 0 ]; then echo "MISSING(hosted)";
  elif [ "$(dig "$1" "$3")" = "$(dig "$2" "$3")" ]; then echo MATCH; else echo DIFF; fi; }
bad=0; in_keep() { local k; for k in "${KEEP[@]}"; do [ "$k" = "$1" ] && return 0; done; return 1; }

case $mode in
check|trim)
  echo "KEEP in the hosted org (the break-glass set, ${#KEEP[@]} items):"
  for n in "${KEEP[@]}"; do
    if [ "$n" = "$HOSTED_ONLY" ]; then s=$([ "$(count "$hitems" "$n")" = 1 ] && echo "present (hosted only, by design)" || echo "MISSING(hosted)")
    else s=$(state "$hitems" "$litems" "$n"); fi
    case $s in MATCH|present*) ;; *) bad=1 ;; esac
    printf '  %-26s %s\n' "$n" "$s"
  done
  echo "DELETE from the hosted org (the site vault is the source), each checked against its site copy:"
  mapfile -t del < <(jq -r '.[].name' <<<"$hitems" | sort | while read -r n; do in_keep "$n" || echo "$n"; done)
  todo=()
  for n in "${del[@]}"; do
    s=$(state "$hitems" "$litems" "$n"); printf '  %-32s %s\n' "$n" "$s"
    [ "$s" = MATCH ] && todo+=("$n") || bad=1
  done
  echo "summary: keep ${#KEEP[@]}; delete ${#del[@]} (${#todo[@]} MATCH their site copy); hosted items $(jq length <<<"$hitems"), site items $(jq length <<<"$litems")"
  if [ "$mode" = trim ]; then
    [ $bad = 0 ] || { echo "REFUSED: not every item is in order (above); nothing deleted"; exit 1; }
    for n in "${todo[@]}"; do id=$(N="$n" jq -r '[.[] | select(.name==env.N)][0].id' <<<"$hitems"); HB delete item "$id" >/dev/null && echo "  deleted from the hosted org: $n"; done
    HB sync >/dev/null; echo "the hosted org now holds $(HB list items --organizationid "$horg" | jq length) items"
  fi ;;
sync)
  for n in "${KEEP[@]}"; do
    [ "$n" = "$HOSTED_ONLY" ] && continue
    s=$(state "$hitems" "$litems" "$n")
    case $s in
      MATCH) echo "  same: $n" ;;
      "MISSING(hosted)") LB get item "$(N="$n" jq -r '[.[] | select(.name==env.N)][0].id' <<<"$litems")" | O=$horg C=$hcol jq '{type, name, notes, favorite, fields, login, secureNote, reprompt} | with_entries(select(.value != null)) | .organizationId=env.O | .collectionIds=[env.C] | .folderId=null | (if .login then .login |= {username, password, totp, uris: [(.uris // [])[] | {match, uri}]} else . end)' | HB encode | HB create item >/dev/null && echo "  copied to the hosted org: $n" ;;
      DIFF) hid=$(N="$n" jq -r '[.[] | select(.name==env.N)][0].id' <<<"$hitems"); LB get item "$(N="$n" jq -r '[.[] | select(.name==env.N)][0].id' <<<"$litems")" | jq '{notes, fields, login: (.login | {username, password, totp, uris: [(.uris // [])[] | {match, uri}]})}' | jq -s --argjson h "$(HB get item "$hid")" '$h + .[0]' | HB encode | HB edit item "$hid" >/dev/null && echo "  refreshed in the hosted org: $n" ;;
      *) echo "  $s: $n (not synced)"; bad=1 ;;
    esac
  done ;;
*) echo "usage: vault-breakglass.sh [check | sync | trim --delete]"; exit 2 ;;
esac
exit $bad
