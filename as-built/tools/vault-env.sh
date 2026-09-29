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
  *) echo "SEED_VAULT is site or hosted, not '$SEED_VAULT'" >&2; return 1 2>/dev/null || exit 1 ;;
esac
