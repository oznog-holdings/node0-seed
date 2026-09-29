#!/usr/bin/env sh
# acme.sh DNS-01 hook for DNSimple with the zone fixed to example.com (used by seed-cert).
# acme.sh's own dns_dnsimple finds the zone by asking for each parent name and expects "not
# found" for the wrong ones. The site's token is limited to one zone, so DNSimple answers 403
# instead, and the plugin takes ntfy.seed.example.com for the zone and fails. It also saves the
# token into acme.sh's account.conf; this hook saves nothing: the token comes from
# /etc/seed/acme.env at every run and reaches curl on stdin, never on its command line.
SEED_ZONE=example.com
SEED_API=https://api.dnsimple.com/v2

_seed_api() {  # method path [json]
  printf 'header = "Authorization: Bearer %s"\n' "$DNSimple_OAUTH_TOKEN" |
    curl -sf -m 30 -K - -X "$1" -H 'Content-Type: application/json' ${3:+-d "$3"} "$SEED_API/$_seed_account$2"
}
_seed_init() {
  [ -n "${DNSimple_OAUTH_TOKEN:-}" ] || { _err "DNSimple_OAUTH_TOKEN not set"; return 1; }
  _seed_account=""; _seed_account=$(_seed_api GET /whoami | jq -r '.data.account.id // empty')
  [ -n "$_seed_account" ] || { _err "DNSimple whoami failed"; return 1; }
  _seed_account="/$_seed_account"
}
dns_seed_dnsimple_add() {
  _seed_init || return 1
  sub=${1%."$SEED_ZONE"}
  _seed_api POST "/zones/$SEED_ZONE/records" "{\"type\":\"TXT\",\"name\":\"$sub\",\"content\":\"$2\",\"ttl\":120}" | jq -e '.data.id' >/dev/null \
    || { _err "adding TXT $sub.$SEED_ZONE failed"; return 1; }
  _info "TXT record added: $sub.$SEED_ZONE"
}
dns_seed_dnsimple_rm() {
  _seed_init || return 1
  sub=${1%."$SEED_ZONE"}
  for id in $(_seed_api GET "/zones/$SEED_ZONE/records?name=$sub&type=TXT" | V="\"$2\"" jq -r '.data[] | select(.content==env.V) | .id'); do
    _seed_api DELETE "/zones/$SEED_ZONE/records/$id" >/dev/null && _info "TXT record removed: $sub.$SEED_ZONE ($id)"
  done
}
