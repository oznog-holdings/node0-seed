#!/usr/bin/env bash
# Make core's encrypted secrets file, site/core/secrets.age, from the vault (design › Secrets:
# "machine secrets are encrypted to three recipients: the laptop's key, the host's key, and
# an offline master key"). core is Debian and has no sops, so this is one age file (armoured)
# to the same recipients: core's ssh host key (age reads it directly), the master key and
# every laptop key in .sops.yaml. Values go vault -> pipe -> age; nothing is printed or written in
# the clear. core decrypts with its host key at every deploy (site/core/apply).
# Run again after changing any of these vault items, then commit, promote and let core deploy.
set -euo pipefail
cd "$(dirname "$0")/.."
out=site/core/secrets.age
core=$(ssh-keygen -F 192.168.1.12 | awk '$2=="ssh-ed25519"{print $2" "$3; exit}')
master=$(awk '/&master /{print $3}' .sops.yaml)
# every laptop in .sops.yaml (anchors laptop_*), one -r each
# (an age1 key, or an ssh-ed25519 public key: two words)
laptops=$(awk '/&laptop_[a-z0-9]+ age1/{printf " -r %s", $3} /&laptop_[a-z0-9]+ ssh-ed25519 /{printf " -r \"%s %s\"", $3, $4}' .sops.yaml)
[[ $core == ssh-ed25519* && $master == age1* && $laptops == " -r "* ]] || { echo "recipient lookup failed" >&2; exit 1; }
. "${SEED_REPO:-/work/agent/seed-lab}/tools/vault-env.sh"   # the site vault (SEED_VAULT=hosted: break-glass)
BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null); export BW_SESSION; unset BW_PASSWORD BW_CLIENTSECRET
trap 'bw lock >/dev/null 2>&1' EXIT
bw sync >/dev/null
items=$(bw list items)
v() {  # exact item name, field (password|username)
  local x; x=$(N="$1" F="$2" jq -r '[.[] | select(.name==env.N)] | if length==1 then .[0].login[env.F] else empty end' <<<"$items")
  [[ -n $x ]] || { echo "vault item '$1' missing or not unique" >&2; return 1; }; printf '%s' "$x"; }
bcrypt() { nix-shell -p apacheHttpd --run 'htpasswd -niB -C 10 x' 2>/dev/null | cut -d: -f2- | tr -d '\n' | sed 's/^\$2y\$/$2a$/'; }
line() {  # NAME value: single-quoted for `. file`; refuse a value that would break the quoting
  [[ -n $2 && $2 != *"'"* && $2 != *$'\n'* ]] || { echo "unusable value for $1" >&2; return 1; }; printf "%s='%s'\n" "$1" "$2"; }
{
  line NTFY_PHONE_HASH "$(v 'ntfy core phone' password | bcrypt)"
  for u in alertmanager watcher power; do
    line "NTFY_TOKEN_${u^^}" "tk_$(v "ntfy core $u" password)"
    # these users sign in by token only: their password is random and never kept
    line "NTFY_HASH_${u^^}" "$(head -c 32 /dev/urandom | base64 -w0 | bcrypt)"
  done
  # Technitium on core (ns1, rung 5): its admin password, read only at its first start
  line TECHNITIUM_ADMIN_PASSWORD "$(v 'technitium core admin' password)"
  line DNSIMPLE_OAUTH_TOKEN "$(v 'dnsimple example.com' password)"
  # the restore rehearsal only reads: the read-only key (20260927; it could write with b2 seed-writer)
  line AWS_ACCESS_KEY_ID "$(v 'b2 seed-restore-reader' username)"
  line AWS_SECRET_ACCESS_KEY "$(v 'b2 seed-restore-reader' password)"
  line RESTIC_PASSWORD "$(v 'restic seed infra' password)"
  line NTFY_HOSTED_URL "https://ntfy.sh/$(v 'ntfy seed topic' password)"
} | nix-shell -p age --run "age -a -r '$core' -r '$master'$laptops -o $out.tmp" && mv $out.tmp $out
echo "wrote $out ($(grep -c . $out) lines, to core, master and the laptops:$laptops)"
