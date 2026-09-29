#!/usr/bin/env bash
# recovery-pack.sh: build the site's recovery pack (design › Secrets › recovery pack) and write it to
# a SEEDRECOV stick (copy A or copy B), wherever it is plugged in: STICK_HOST=user@host (default infra's
# root). PREPARE=1 first prepares a new stick of the two (see below). Run on the agent box as the builder.
#   1. guards on infra: the stick is found by its serial, it's not /boot's device, it's labelled
#      SEEDRECOV, nothing is mounted from it; the Unraid boot flash (by serial) is never touched
#   2. the plaintext is assembled in the agent box's RAM (/dev/shm, 0700): the repo bundle, vault
#      items, the master key, the builder's vault login, the order page; plus infra's flash and the
#      host identity tarballs, streamed over ssh
#   3. tar | gpg AES256 (the passphrase from vault item "recovery pack passphrase", by file
#      descriptor) | ssh | the stick, hashed while writing; only ciphertext leaves the agent box
#   4. read back after dropping infra's caches: the same sha256; then decrypted as a stream into
#      RAM and every file checked against MANIFEST.txt
#   5. an older pack on the stick is deleted only after the new one is verified
# Prints names, sizes and hashes only. The plaintext is shredded on exit.
set -euo pipefail
cd "$(dirname "$0")/.."
# the recovery sticks: copy A and copy B (the owner's storage rule: one fully off site, one on site in a
# separate place). The one plugged into STICK_HOST is written; exactly one of them may be present.
STICKS="SERIAL-PLACEHOLDER SERIAL-PLACEHOLDER"; LABEL=SEEDRECOV
copy_of() { case $1 in SERIAL-PLACEHOLDER) echo A;; SERIAL-PLACEHOLDER) echo B;; esac; }
# PREPARE=1: first make a new stick (one of STICKS, not yet SEEDRECOV) the way copy A was made: a fresh
# GPT, one partition named SEEDRECOV, FAT32 labelled SEEDRECOV. Then the pack is written as usual.
# never written, whatever else matches: infra's Unraid boot flash, Larkbox one's live-installer stick and
# its internal disk (serials recorded 20260924 and 20260927)
NEVER="SERIAL-PLACEHOLDER SERIAL-PLACEHOLDER SERIAL-PLACEHOLDER"
D=$(date +%Y%m%d); NAME=seed-recovery-$(date -u +%Y%m%dT%H%MZ).tar.gpg   # never the name of the pack it replaces
I="ssh -o BatchMode=yes root@192.168.1.10"                  # infra: the flash and the identity tarballs
STICK_HOST=${STICK_HOST:-root@192.168.1.10}                   # where the stick is plugged in (20260927: nixos@192.168.1.128)
SUDO=; [ "${STICK_HOST%%@*}" = root ] || SUDO="sudo -n"
X() { ssh -o BatchMode=yes "$STICK_HOST" "$SUDO sh -c $(printf '%q' "$1")"; }   # a command as root on the stick's host
log() { echo "$(date -u +%FT%TZ) $*"; }

# 1. guards, on the stick's host
dev=""; STICK_SERIAL=""
for sn in $STICKS; do
  d=$(X "readlink -f /dev/disk/by-id/usb-*_${sn}-0:0" 2>/dev/null || true)
  if [[ $d == /dev/sd? ]]; then [ -z "$dev" ] || { echo "guard: two recovery sticks on $STICK_HOST; plug in one" >&2; exit 1; }; dev=$d; STICK_SERIAL=$sn; fi
done
[ -n "$dev" ] || { echo "guard: no recovery stick ($STICKS) on $STICK_HOST" >&2; exit 1; }
part=${dev}1
ser=$(X "lsblk -dno SERIAL $dev"); tran=$(X "lsblk -dno TRAN $dev")
[[ $dev == /dev/sd? && $ser == "$STICK_SERIAL" && $tran == usb ]] || { echo "guard: $dev serial '$ser' transport '$tran'" >&2; exit 1; }
for n in $NEVER; do [ "$ser" != "$n" ] || { echo "guard: $dev is a never-write device ($n)" >&2; exit 1; }; done
[ -z "$(X "lsblk -nro MOUNTPOINT $dev" | tr -d '[:space:]')" ] || { echo "guard: something on $dev is mounted (a boot device?)" >&2; exit 1; }
if [ "${PREPARE:-}" = 1 ]; then
  [ "$(X "blkid -s LABEL -o value $part" 2>/dev/null)" != "$LABEL" ] || { echo "guard: $part is already $LABEL: PREPARE never wipes a recovery copy" >&2; exit 1; }
  # separate steps: one combined sgdisk call left a GPT with no partition, and mkfs ran before the
  # kernel had the partition's node (20260928); so create, re-read, wait for the node, then format
  X "wipefs -q -a $part 2>/dev/null; wipefs -q -a $dev && sgdisk -q -o $dev && sgdisk -q -n 1:0:0 -t 1:0700 -c 1:$LABEL $dev && partprobe $dev && for i in \$(seq 1 20); do [ -b $part ] && break; sleep 0.5; done; mkfs.vfat -F 32 -n $LABEL $part >/dev/null"
  log "prepared copy $(copy_of $ser) ($ser): $(X "sgdisk -p $dev | grep -E '^ +1 |Disk identifier'" | tr -s ' ' | tr '\n' ';') $(X "blkid $part")"
fi
[ "$(X "blkid -s LABEL -o value $part")" = "$LABEL" ] || { echo "guard: $part is not labelled $LABEL" >&2; exit 1; }
log "guards on $STICK_HOST: stick $dev (copy $(copy_of $ser), serial $ser, usb, $LABEL, nothing mounted); never-write serials absent: $NEVER; $(X "lsblk -dno NAME,SERIAL,MOUNTPOINTS" | tr '\n' ';')"

# 2. plaintext in RAM
umask 077; W=$(mktemp -d /dev/shm/pack.XXXXXX); V=$(mktemp -d /dev/shm/verify.XXXXXX)
M=/mnt/seedrecov.$$
cleanup() { find "$W" "$V" -type f -exec shred -u {} + 2>/dev/null; rm -rf "$W" "$V"; X "umount $M 2>/dev/null; rmdir $M 2>/dev/null" || true; bw lock >/dev/null 2>&1 || true; }
trap cleanup EXIT
P=$W/p; mkdir -p $P/repo $P/secrets $P/flash $P/identity
git fetch -q forge   # the bundle carries remote-tracking refs: without this, deploy was stale (rehearsal 20260927)
git bundle create $P/repo/seed-lab.bundle --all 2>/dev/null; git bundle verify $P/repo/seed-lab.bundle >/dev/null 2>&1
. "${SEED_REPO:-/work/agent/seed-lab}/tools/vault-env.sh"   # the site vault (SEED_VAULT=hosted: break-glass)
BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null); export BW_SESSION; unset BW_PASSWORD BW_CLIENTSECRET
bw sync >/dev/null; items=$(bw list items)
item() { N="$1" jq -r '[.[] | select(.name==env.N)] | if length==1 then .[0] else error("missing or not unique: " + env.N) end' <<<"$items"; }
{ echo "# Seed recovery pack $D: restic repository passwords, rest-server logins, B2 keys and site2's replica key (vault copies)"
  # "zfs site2 replica key": the key of site2/seed, the second site's encrypted replica (rung 5 › E)
  for n in $(jq -r '.[].name | select(test("^(restic seed|rest-server|b2 seed-|zfs site2 replica key$)"))' <<<"$items" | tr ' ' '~' | sort); do
    n=${n//\~/ }; item "$n" | jq -r '"\n[" + .name + "]\nusername = " + (.login.username // "") + "\npassword = " + (.login.password // "") + (if .notes then "\nnotes = " + (.notes|gsub("\n"; " ")) else "" end)'
  done; } > $P/secrets/restic.txt
# the key line only: age and sops reject the vault notes' prose line (rehearsal 20260927)
{ echo "# the site's sops/age master key (vault item 'sops master age key'); use with age -i or SOPS_AGE_KEY_FILE"
  item 'sops master age key' | jq -r .notes | grep '^AGE-SECRET-KEY-'; } > $P/secrets/master-key.txt
[ "$(grep -c '^AGE-SECRET-KEY-' $P/secrets/master-key.txt)" = 1 ] || { echo "master key missing" >&2; exit 1; }
cp "$HOME/.config/seed/bw.env" $P/secrets/builder-vault-login.env; cp "$HOME/.config/seed/bw-local.env" $P/secrets/builder-site-vault-login.env
item 'recovery pack passphrase' | jq -r .login.password > $W/pass; bw lock >/dev/null
[ -s $W/pass ] || { echo "passphrase missing" >&2; exit 1; }
cp site/runbooks/recovery-order.md $P/README-RECOVERY.md
$I "tar -C /boot -cf - ." > $P/flash/boot.tar
$I "tar -C /mnt/data/system/identity -cf - ." | tar -C $P/identity -xf -
(cd $P && find . -type f ! -name MANIFEST.txt | LC_ALL=C sort | xargs sha256sum > MANIFEST.txt)
log "assembled in RAM: $(find $P -type f | wc -l) files, $(du -sh $P | cut -f1): $(cd $P && find . -type f | LC_ALL=C sort | tr '\n' ' ')"

# 3. encrypt as a stream onto the stick
X "mkdir -p $M && mount -o rw,sync $part $M"
sum_w=$(tar -C $P -cf - . | nix-shell -p gnupg --run "gpg --batch --quiet --pinentry-mode loopback --passphrase-file $W/pass --symmetric --cipher-algo AES256 --s2k-digest-algo SHA512 --s2k-count 65011712 --output -" 2>/dev/null \
  | tee >(sha256sum | cut -d' ' -f1 > $W/sum) | X "cat > $M/$NAME.part && mv $M/$NAME.part $M/$NAME && sync"; sleep 1; cat $W/sum)
cp $P/MANIFEST.txt $W/MANIFEST.txt; cat $W/MANIFEST.txt | X "cat > $M/MANIFEST.txt"
cat $P/README-RECOVERY.md | X "cat > $M/README-RECOVERY.md; sync; umount $M"
log "written: $NAME, sha256 $sum_w (hashed while writing)"

# 4. read back and verify
X "sync; echo 3 > /proc/sys/vm/drop_caches; mount -o ro $part $M"
sum_r=$(X "sha256sum $M/$NAME" | cut -d' ' -f1)
[ "$sum_w" = "$sum_r" ] || { echo "READ-BACK MISMATCH: $sum_r" >&2; exit 1; }
log "read back after dropping caches: sha256 $sum_r (the same)"
X "cat $M/$NAME" | nix-shell -p gnupg --run "gpg --batch --quiet --pinentry-mode loopback --passphrase-file $W/pass --decrypt" 2>/dev/null | tar -C $V -xf -
(cd $V && sha256sum --quiet -c MANIFEST.txt) && log "decrypted as a stream: $(grep -c . $V/MANIFEST.txt)/$(grep -c . $W/MANIFEST.txt) files match MANIFEST.txt"
cmp -s $V/MANIFEST.txt $W/MANIFEST.txt || { echo "manifest differs" >&2; exit 1; }
git bundle verify $V/repo/seed-lab.bundle >/dev/null 2>&1 && log "the bundle verifies ($(git bundle list-heads $V/repo/seed-lab.bundle | wc -l) refs)"

# 5. the older pack goes only now
X "umount $M; mount -o rw,sync $part $M; for f in $M/seed-recovery-*.tar.gpg; do [ \"\$f\" = $M/$NAME ] || { rm -f \"\$f\"; echo \"removed older \$(basename \$f)\"; }; done; sync; ls -la $M | tail -n +4; umount $M"
log "done"
