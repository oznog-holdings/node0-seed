# Sourced by every script that reads the vault, just before its `bw unlock --passwordenv BW_PASSWORD`:
# it chooses which vault that unlock opens (the D.01d flip, 20260928).
#  - site (the default): the site's Vaultwarden, the source for every item. The bw CLI profile is
#    ~/.config/seed/bw-local (logged in as builder@seed.example.com); its master password is in
#    ~/.config/seed/bw-local.env (0600, on /work: F-REBUILD-BW).
#  - SEED_VAULT=hosted: the hosted Bitwarden org, which keeps only the break-glass set
#    (tools/vault-breakglass.txt); for those items when the site vault is down.
case ${SEED_VAULT:-site} in
  site)   export BITWARDENCLI_APPDATA_DIR="$HOME/.config/seed/bw-local"; set -a; . "$HOME/.config/seed/bw-local.env"; set +a ;;
  hosted) unset BITWARDENCLI_APPDATA_DIR; set -a; . "$HOME/.config/seed/bw.env"; set +a ;;
  # SEED_VAULT=bundle: the site agents (tender) have no vault login. They get the few items the site's tools need to
  # fix things (site/agents/vault-bundle.txt), read-only, in /run/secrets/tender-vault-items (sops, tmpfs, 0400
  # tender). This `bw` answers the calls those tools make (unlock, sync, lock, list items, get item) from it.
  bundle) SEED_VAULT_ITEMS=${SEED_VAULT_ITEMS:-/run/secrets/tender-vault-items}
          [ -r "$SEED_VAULT_ITEMS" ] || { echo "no vault bundle at $SEED_VAULT_ITEMS" >&2; return 1 2>/dev/null || exit 1; }
          bw() { case "$1 ${2:-}" in
                   "unlock "*) echo bundle ;; "sync "*|"lock "*) : ;;
                   "list items") cat "$SEED_VAULT_ITEMS" ;;
                   "get item") N="$3" jq -e '[.[] | select(.name==env.N)] | if length==1 then .[0] else error("not in the bundle") end' "$SEED_VAULT_ITEMS" ;;
                   *) echo "bw $1 ${2:-}: not available to the site agents" >&2; return 1 ;; esac; }
          export -f bw 2>/dev/null; export SEED_VAULT_ITEMS ;;
  *) echo "SEED_VAULT is site, hosted or bundle, not '$SEED_VAULT'" >&2; return 1 2>/dev/null || exit 1 ;;
esac
