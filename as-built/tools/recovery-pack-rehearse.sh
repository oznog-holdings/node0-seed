#!/usr/bin/env bash
# recovery-pack-rehearse.sh: the rehearsal after a recovery stick is written (20261006): from the stick alone, take the
# master key out of the newest pack and decrypt one of the site's sops files with it. Run on the agent box as the
# builder, the stick plugged into STICK_HOST (default infra's root), one stick at a time, read-only on the stick.
#   1. the stick found by its serial (copy A or B), mounted read-only
#   2. the newest seed-recovery-*.tar.gpg decrypted as a stream (the passphrase from the vault, by file), only
#      secrets/master-key.txt extracted, into RAM (/dev/shm, 0700)
#   3. its public key compared with .sops.yaml's &master recipient
#   4. nixos/secrets/site2.yaml decrypted with it: prints how many keys opened, never a value
# Prints names, the public key and counts only; everything in RAM is shredded on exit.
set -euo pipefail
cd "$(dirname "$0")/.."
STICKS="SERIAL-PLACEHOLDER SERIAL-PLACEHOLDER"; copy_of() { case $1 in SERIAL-PLACEHOLDER) echo A;; SERIAL-PLACEHOLDER) echo B;; esac; }
STICK_HOST=${STICK_HOST:-root@192.168.1.10}
SUDO=; [ "${STICK_HOST%%@*}" = root ] || SUDO="sudo -n"
X() { ssh -o BatchMode=yes "$STICK_HOST" "$SUDO sh -c $(printf '%q' "$1")"; }
log() { echo "$(date -u +%FT%TZ) $*"; }
dev=""; sn_found=""
for sn in $STICKS; do
  d=$(X "readlink -f /dev/disk/by-id/usb-*_${sn}-0:0" 2>/dev/null || true)
  if [[ $d == /dev/sd? ]]; then [ -z "$dev" ] || { echo "two recovery sticks on $STICK_HOST; plug in one" >&2; exit 1; }; dev=$d; sn_found=$sn; fi
done
[ -n "$dev" ] || { echo "no recovery stick on $STICK_HOST" >&2; exit 1; }
M=/mnt/seedrecov-rehearse.$$; W=$(mktemp -d /dev/shm/rehearse.XXXXXX); chmod 700 $W
cleanup() { X "umount $M 2>/dev/null; rmdir $M 2>/dev/null" || true; find $W -type f -exec shred -u {} + 2>/dev/null; rm -rf $W; }
trap cleanup EXIT
X "mkdir -p $M && mount -o ro ${dev}1 $M"
pack=$(X "ls -1 $M/seed-recovery-*.tar.gpg" | sort | tail -1); [ -n "$pack" ] || { echo "no pack on the stick" >&2; exit 1; }
log "copy $(copy_of $sn_found) (serial $sn_found): the newest pack $(basename $pack)"
. "${SEED_REPO:-/work/agent/seed-lab}/tools/vault-env.sh"
BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null); export BW_SESSION; unset BW_PASSWORD BW_CLIENTSECRET
bw list items | N='recovery pack passphrase' jq -r '[.[] | select(.name==env.N)] | if length==1 then .[0].login.password else error("missing") end' > $W/pass
bw lock >/dev/null; unset BW_SESSION
X "cat $pack" | nix-shell -p gnupg --run "gpg --batch --quiet --pinentry-mode loopback --passphrase-file $W/pass --decrypt" 2>/dev/null \
  | tar -C $W -xf - ./secrets/master-key.txt
grep '^AGE-SECRET-KEY-' $W/secrets/master-key.txt > $W/key
pub=$(nix-shell -p age --run "age-keygen -y $W/key"); want=$(grep -o '&master age1[a-z0-9]*' .sops.yaml | cut -d' ' -f2)
[ "$pub" = "$want" ] && log "the stick's master key is the current one ($pub)" || { log "MISMATCH: the stick's key is $pub, .sops.yaml wants $want"; exit 1; }
n=$(SOPS_AGE_KEY_FILE=$W/key nix-shell -p sops yq-go --run "sops -d nixos/secrets/site2.yaml | yq 'keys | length'")
log "nixos/secrets/site2.yaml decrypted with the stick's key: $n keys (no value shown)"
log "REHEARSAL PASS (copy $(copy_of $sn_found))"
