#!/bin/bash
# Build core on its USB SSD from the repo, from the running SD system, as root (README.md here).
# Usage: build.sh <image.img.xz>, with core's identity tarball already at /run/seed-core-identity.tar
# (streamed from infra's identity store by the builder). The SD card is only read (the admin account's
# authorized_keys and sudoers file, the NetworkManager connection, the repo's forge host key).
set -euo pipefail
SER=SERIAL-PLACEHOLDER; VIDPID=0dd8:2320
IMG=${1:?usage: build.sh <image.img.xz>}; IMGSHA=cdf4f3bfac35ae947b46e4e767f935453810549779ac3290e05a6754aee627e5   # 2026-09-15-raspios-trixie-arm64-lite.img.xz, published .sha256
IDT=/run/seed-core-identity.tar; M=/mnt/seed-ssd
dev=$(readlink -f /dev/disk/by-id/usb-NetacPortableSSD_NetacPortableSSD_${SER}-0:0); B=${dev}1; R=${dev}2
log() { echo "$(date -u +%T) build: $*"; }
[[ $dev == /dev/sd? ]] && [ -z "$(lsblk -nro MOUNTPOINT "$dev" | tr -d '[:space:]')" ] && [ "$(findmnt -n -o SOURCE /)" = /dev/mmcblk0p2 ] \
  || { echo "guard: SSD $SER missing or mounted, or root not on the SD card"; exit 1; }
[ "$(cat /sys/module/usb_storage/parameters/quirks)" = "$VIDPID:u" ] || { echo "guard: the no-UAS quirk is not set"; exit 1; }
[ -s "$IDT" ] && ! tar -tvf "$IDT" --numeric-owner | awk '{print $2}' | grep -vqx '0/0' || { echo "guard: $IDT missing or not root-owned"; exit 1; }
echo "$IMGSHA  $IMG" | sha256sum -c --quiet || { echo "image sha256 mismatch"; exit 1; }

# 1. the image, with its own ids (the SD card's image has the same filesystem UUIDs)
wipefs -q -a "$dev"; xz -dc "$IMG" | dd of="$dev" bs=4M conv=fsync iflag=fullblock status=none; partprobe "$dev"; udevadm settle
sfdisk -q --disk-id "$dev" "0x$(openssl rand -hex 4)"; echo ", +" | sfdisk -q -N 2 --no-reread "$dev"; partprobe "$dev"; udevadm settle
e2fsck -pf "$R" >/dev/null; resize2fs "$R" 2>&1 | tail -1; tune2fs -U random "$R" >/dev/null; fatlabel -i "$B" "$(openssl rand -hex 4 | tr a-f A-F)"
pu=$(blkid -s PTUUID -o value "$dev"); log "written; disk id $pu; $(blkid "$B" "$R" | tr -s ' ' | tr '\n' ';')"
mkdir -p $M; mount "$R" $M; mount "$B" $M/boot/firmware
cleanup() { rm -f $M/usr/sbin/policy-rc.d; for d in dev/pts dev proc sys; do umount $M/$d 2>/dev/null || true; done; umount $M/boot/firmware $M 2>/dev/null || true; }
trap cleanup EXIT

# 2. boot: root and fstab on the SSD's own partitions; the no-UAS quirk; no cloud-init
c=$M/boot/firmware/cmdline.txt
sed -i "s/root=PARTUUID=[^ ]*/root=PARTUUID=${pu}-02/; s/ ds=nocloud[^ ]*//; s/ resize\( \|\$\)/\1/" $c   # resize: the image's first-boot grow, already done
grep -q "usb-storage.quirks=" $c || sed -i "1s/\$/ usb-storage.quirks=$VIDPID:u/" $c
sed -i "s/^PARTUUID=[0-9a-f]*-01/PARTUUID=${pu}-01/; s/^PARTUUID=[0-9a-f]*-02/PARTUUID=${pu}-02/" $M/etc/fstab
touch $M/etc/cloud/cloud-init.disabled
log "cmdline: $(cat $c)"; log "fstab: $(grep PARTUUID $M/etc/fstab | awk '{print $1, $2}' | tr '\n' ';')"

# 3. identity: the host keys and the deploy key, as they were (so ssh stays strict and secrets.age opens)
tar -xpf "$IDT" -C $M --numeric-owner; log "identity: $(ssh-keygen -lf $M/etc/ssh/ssh_host_ed25519_key.pub | cut -d' ' -f2)"

# 4. names and access (the README's bootstrap step 1, and the person's account as on the card)
echo core > $M/etc/hostname; sed -i 's/^127\.0\.1\.1.*/127.0.1.1\tcore/' $M/etc/hosts
grep -q ' git.seed.example.com$' $M/etc/hosts || echo '192.168.1.10 git.seed.example.com' >> $M/etc/hosts
ln -sf /usr/share/zoneinfo/America/Denver $M/etc/localtime; echo America/Denver > $M/etc/timezone
install -m 0600 -o root -g root "/etc/NetworkManager/system-connections/Wired connection 1.nmconnection" "$M/etc/NetworkManager/system-connections/"
for d in dev dev/pts proc sys; do mount --bind /$d $M/$d; done
mv $M/etc/resolv.conf $M/etc/resolv.conf.seed-build 2>/dev/null || true; cp /etc/resolv.conf $M/etc/resolv.conf; printf '#!/bin/sh\nexit 101\n' > $M/usr/sbin/policy-rc.d; chmod 0755 $M/usr/sbin/policy-rc.d   # no service starts in the chroot
CH() { chroot $M /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root LANG=C.UTF-8 "$@"; }
CH usermod -l admin -d /home/admin -m -s /bin/bash pi; CH groupmod -n admin pi; CH passwd -l admin >/dev/null   # the image's pi has nologin until userconfig (masked)
install -d -m 0700 -o 1000 -g 1000 $M/home/admin/.ssh; install -m 0600 -o 1000 -g 1000 /home/admin/.ssh/authorized_keys $M/home/admin/.ssh/
install -m 0440 -o root -g root /etc/sudoers.d/010-admin-nopasswd $M/etc/sudoers.d/; rm -f $M/etc/sudoers.d/010_pi-nopasswd
rm -f $M/etc/ssh/sshd_config.d/rename_user.conf   # the image's "set up a valid user" banner (userconfig's, masked)
CH systemctl enable -q ssh; for u in regenerate_ssh_host_keys.service userconfig.service rpi-resize.service sshswitch.service; do CH systemctl mask -q "$u"; done
log "admin: $(CH id admin); ssh enabled; first-boot units masked"

# 5. the repo and the offline stage of apply (README bootstrap steps 2-3, then apply)
CH apt-get update -qq; CH env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends git age python3-yaml >/dev/null
install -d -m 0700 $M/var/lib/seed-deploy
k=$(cat /var/lib/seed-deploy/repo/nixos/forge-hostkey.pub); echo "[git.seed.example.com]:2222,[192.168.1.10]:2222 $k" > $M/var/lib/seed-deploy/known_hosts
CH env GIT_SSH_COMMAND="ssh -i /var/lib/seed-deploy/deploy_key -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/var/lib/seed-deploy/known_hosts" \
  git clone -q --no-checkout --branch deploy --single-branch ssh://git@git.seed.example.com:2222/seed/seed-lab.git /var/lib/seed-deploy/repo
CH git -C /var/lib/seed-deploy/repo checkout -q --detach origin/deploy 2>/dev/null || CH git -C /var/lib/seed-deploy/repo checkout -q --detach deploy
log "repo at $(CH git -C /var/lib/seed-deploy/repo rev-parse --short HEAD)"
CH env SEED_APPLY_OFFLINE=1 bash /var/lib/seed-deploy/repo/site/core/apply /var/lib/seed-deploy/repo
rm -f $M/usr/sbin/policy-rc.d $M/etc/resolv.conf; mv $M/etc/resolv.conf.seed-build $M/etc/resolv.conf 2>/dev/null || true   # the image's own
log "enabled at boot: $(for u in technitium chrony ntfy nftables prometheus-node-exporter seed-deploy.timer seed-power-watch.timer ssh; do printf '%s=%s ' $u "$(CH systemctl is-enabled $u 2>/dev/null)"; done)"
shred -u "$IDT"; rm -f "$IMG"; log "identity tarball shredded, image removed from core"
log "done: the SSD is built; the SD card is untouched. Next: the EEPROM boot order (README step 4)"
