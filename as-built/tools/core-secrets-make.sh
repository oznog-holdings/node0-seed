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
  # duplicates are accepted only when every copy holds the same value (said, so the owner can remove one)
  local x n; n=$(N="$1" jq '[.[] | select(.name==env.N)] | length' <<<"$items")
  x=$(N="$1" F="$2" jq -r '[.[] | select(.name==env.N) | .login[env.F]] | unique | if length==1 then .[0] // empty else empty end' <<<"$items")
  [[ -n $x ]] || { echo "vault item '$1' missing, or duplicated with different values" >&2; return 1; }
  [[ $n = 1 ]] || echo "vault item '$1': $n identical copies (one could go, with the owner's approval)" >&2
  printf '%s' "$x"; }
bcrypt() { nix-shell -p apacheHttpd --run 'htpasswd -niB -C 10 x' 2>/dev/null | cut -d: -f2- | tr -d '\n' | sed 's/^\$2y\$/$2a$/'; }
line() {  # NAME value: single-quoted for `. file`; refuse a value that would break the quoting
  [[ -n $2 && $2 != *"'"* && $2 != *$'\n'* ]] || { echo "unusable value for $1" >&2; return 1; }; printf "%s='%s'\n" "$1" "$2"; }
gen() {  # every line, or nothing: a failed value stops here, before age writes anything
  local x   # each lookup checked on its own: a failed one inside "tk_$(…)" would still look like a value
  x=$(v 'ntfy core phone' password) || return 1; line NTFY_PHONE_HASH "$(printf '%s' "$x" | bcrypt)" || return 1
  for u in alertmanager watcher power tender orchestrator; do   # tender: the site agents; orchestrator: read-only (20260930)
    item="ntfy core $u"; [ $u = tender ] && item="tender ntfy token"; [ $u = orchestrator ] && item="ntfy orchestrator read"
    # Alertmanager has no token since 20261003 (it signs in by password, below)
    [ $u = alertmanager ] || { x=$(v "$item" password) || return 1; line "NTFY_TOKEN_${u^^}" "tk_$x" || return 1; }
    if [ $u = alertmanager ]; then   # Alertmanager signs in by password (20261003: ntfy's token path fails some
      # concurrent publishes with 403; tools/ntfy-alertmanager-password.sh): the hash of its vault item
      x=$(v 'ntfy core alertmanager password' password) || return 1; line NTFY_HASH_ALERTMANAGER "$(printf '%s' "$x" | bcrypt)" || return 1
    else   # the others sign in by token only: their password is random and never kept
      line "NTFY_HASH_${u^^}" "$(head -c 32 /dev/urandom | base64 -w0 | bcrypt)" || return 1
    fi
  done
  # during a rotation only (tools/rotate-ntfy-tokens.sh): the previous tokens, so a consumer still on one isn't cut
  # off before its host has the new one. NTFY_PREV names a file of "<user> tk_<value>" lines (a process
  # substitution: the values never on an argument)
  if [ -n "${NTFY_PREV:-}" ]; then while read -r pu pv; do line "NTFY_PREV_${pu^^}" "$pv" || return 1; done < "$NTFY_PREV"; fi
  # Technitium on core (ns1, rung 5): its admin password, read only at its first start
  line TECHNITIUM_ADMIN_PASSWORD "$(v 'technitium core admin' password)" || return 1
  line DNSIMPLE_OAUTH_TOKEN "$(v 'dnsimple example.com' password)" || return 1
  # the restore rehearsal only reads: the read-only key (20260927; it could write with b2 seed-writer)
  line AWS_ACCESS_KEY_ID "$(v 'b2 seed-restore-reader' username)" || return 1
  line AWS_SECRET_ACCESS_KEY "$(v 'b2 seed-restore-reader' password)" || return 1
  line RESTIC_PASSWORD "$(v 'restic seed infra' password)" || return 1
  x=$(v 'ntfy seed topic' password) || return 1; line NTFY_HOSTED_URL "https://ntfy.sh/$x" || return 1
  unset x
}
plain=$(gen) || { echo "a value failed: $out left as it was" >&2; exit 1; }
printf '%s\n' "$plain" | nix-shell -p age --run "age -a -r '$core' -r '$master'$laptops -o $out.tmp" && mv $out.tmp $out \
  || { unset plain; echo "encryption failed: $out left as it was" >&2; exit 1; }
unset plain
echo "wrote $out ($(grep -c . $out) lines, to core, master and the laptops:$laptops)"
