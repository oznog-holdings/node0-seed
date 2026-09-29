#!/usr/bin/env bash
# Re-encrypt the site's secrets files to the recipients now in .sops.yaml, without changing a value:
# nixos/secrets/agent.yaml by `sops updatekeys`, site/core/secrets.age by decrypt | encrypt (so
# no hash is re-salted and nothing restarts on core, unlike core-secrets-make.sh). Decrypts with
# the offline master key from the vault, held in a 0600 tmpfs file for the run and shredded.
# Prints each file's plaintext hash (first 12) before and after; they must be equal.
# Use it after adding or removing a laptop (or any recipient) in .sops.yaml.
set -euo pipefail
cd "$(dirname "$0")/.."
. "${SEED_REPO:-/work/agent/seed-lab}/tools/vault-env.sh"   # the site vault (SEED_VAULT=hosted: break-glass)
BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null); export BW_SESSION; unset BW_PASSWORD BW_CLIENTSECRET
umask 077; kd=$(mktemp -d /dev/shm/seed.XXXXXX)
trap 'bw lock >/dev/null 2>&1; shred -u $kd/k 2>/dev/null; rmdir $kd' EXIT
bw list items --search 'sops master age key' | jq -r '[.[] | select(.name=="sops master age key")] | if length==1 then .[0].notes else empty end' | grep '^AGE-SECRET-KEY-' > $kd/k
bw lock >/dev/null 2>&1
[ -s $kd/k ] || { echo "master key not found" >&2; exit 1; }
h() { sha256sum | cut -c1-12; }

f=nixos/secrets/agent.yaml
b=$(SOPS_AGE_KEY_FILE=$kd/k nix-shell -p sops --run "sops -d --output-type json $f" 2>/dev/null | h)
SOPS_AGE_KEY_FILE=$kd/k nix-shell -p sops --run "sops updatekeys -y $f" 2>&1 | grep -E '^\+\+\+|^---|synced|no changes' || true
a=$(SOPS_AGE_KEY_FILE=$kd/k nix-shell -p sops --run "sops -d --output-type json $f" 2>/dev/null | h)
echo "$f: plaintext $b -> $a $([ "$b" = "$a" ] && echo same || echo DIFFERENT)"; [ "$b" = "$a" ]

f=site/core/secrets.age
core=$(ssh-keygen -F 192.168.1.12 | awk '$2=="ssh-ed25519"{print $2" "$3; exit}'); master=$(awk '/&master /{print $3}' .sops.yaml)
laptops=$(awk '/&laptop_[a-z0-9]+ age1/{printf " -r %s", $3} /&laptop_[a-z0-9]+ ssh-ed25519 /{printf " -r \"%s %s\"", $3, $4}' .sops.yaml)
[[ $core == ssh-ed25519* && $master == age1* && $laptops == " -r "* ]] || { echo "recipient lookup failed" >&2; exit 1; }
b=$(nix-shell -p age --run "age -d -i $kd/k $f" 2>/dev/null | h)
nix-shell -p age --run "age -d -i $kd/k $f | age -a -r '$core' -r '$master'$laptops -o $f.tmp" 2>/dev/null && mv $f.tmp $f
a=$(nix-shell -p age --run "age -d -i $kd/k $f" 2>/dev/null | h)
echo "$f: plaintext $b -> $a $([ "$b" = "$a" ] && echo same || echo DIFFERENT), to core, master and the laptops:$laptops"; [ "$b" = "$a" ]
