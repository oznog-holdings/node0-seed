#!/bin/bash
# Stress core's USB SSD before core moves onto it (F-CORE-SSD-UAS), from the running SD system, as root.
# DESTROYS everything on the SSD (it is rewritten by build.sh afterwards). Fails on the first sign of
# the fault seen on 20260928: a UAS abort, a reset, the device offline, an I/O error.
#  0. guards: the SSD by serial, nothing on it mounted, root on the SD card; the no-UAS quirk active
#     (the device bound to usb-storage, not uas); link speed recorded
#  1. mixed writes: four 8 GiB sequential regions spread over the disk (a reproducible AES-CTR stream
#     each), with random 4 KiB direct writes in a fifth region at the same time
#  2. full read-back of the four regions (direct I/O, caches dropped), compared by sha256
#  3. a metadata-heavy pass like the resize2fs that failed: mkfs.ext4 over the whole disk with the
#     inode tables written now (lazy init off), then e2fsck -fn
# After every phase the kernel log since the start is checked.
set -euo pipefail
SER=SERIAL-PLACEHOLDER; VIDPID=0dd8:2320
dev=$(readlink -f /dev/disk/by-id/usb-NetacPortableSSD_NetacPortableSSD_${SER}-0:0)
t0=$(date '+%Y-%m-%d %H:%M:%S'); log() { echo "$(date -u +%T) $*"; }
[[ $dev == /dev/sd? ]] || { echo "guard: no SSD with serial $SER"; exit 1; }
[ -z "$(lsblk -nro MOUNTPOINT "$dev" | tr -d '[:space:]')" ] || { echo "guard: something on $dev is mounted"; exit 1; }
[ "$(findmnt -n -o SOURCE /)" = /dev/mmcblk0p2 ] || { echo "guard: root is not on the SD card"; exit 1; }
[ "$(cat /sys/module/usb_storage/parameters/quirks)" = "$VIDPID:u" ] || { echo "guard: the no-UAS quirk is not set"; exit 1; }
usbdev=$(basename "$(readlink -f /sys/block/${dev#/dev/}/device/../../../..)")
ls /sys/bus/usb/drivers/uas 2>/dev/null | grep -q "^$usbdev:" && { echo "guard: $usbdev is bound to uas (replug after setting the quirk)"; exit 1; }
ls /sys/bus/usb/drivers/usb-storage | grep -q "^$usbdev:" || { echo "guard: $usbdev is not bound to usb-storage"; exit 1; }
log "guards ok: $dev (serial $SER), usb $usbdev on usb-storage (quirk $VIDPID:u), speed $(cat /sys/bus/usb/devices/$usbdev/speed) Mb/s"
log "kernel: $(journalctl -k --since "$t0" --no-pager -q | grep -c . || true) lines so far; $(dmesg | grep -E 'UAS is ignored|Quirks match' | tail -2 | tr -s ' ' | tr '\n' ';')"
check() { if journalctl -k --since "$t0" --no-pager -q | grep -Ei 'uas_eh|reset (high|super)speed|device offline|I/O error|error -71|not accepting address|Synchronize Cache'; then log "FAIL in $1: the kernel log above"; exit 1; fi; log "$1: kernel log clean"; }
# openssl exits 1 when head closes the pipe; under pipefail and set -e that ended the first run
# (20260928) after one region, so the stream's own status is ignored (head's byte count is what matters)
gen() { { openssl enc -aes-128-ctr -nosalt -K "$(printf '%032x' "$1")" -iv 0 < /dev/zero 2>/dev/null || true; } | head -c $((8<<30)); }
G=$((1<<30)); regions="0 150 300 460"                                  # GiB offsets; each 8 GiB
log "phase 1: 4 x 8 GiB sequential writes and random 4 KiB writes (region 200-210 GiB), together"
( end=$((SECONDS+600)); n=0; while [ $SECONDS -lt $end ] && [ ! -e /run/seed-stress.done ]; do
    dd if=/dev/urandom of="$dev" bs=4k count=1 seek=$(( (200<<18) + (RANDOM*32768+RANDOM) % (10<<18) )) oflag=direct conv=notrunc status=none; n=$((n+1)); done
  echo "$n random 4 KiB writes" > /run/seed-stress.random ) &
rnd=$!; s=$SECONDS
for r in $regions; do gen $r | dd of="$dev" bs=4M seek=$(( r*G/(4<<20) )) oflag=direct conv=notrunc iflag=fullblock status=none; done
touch /run/seed-stress.done; wait $rnd; rm -f /run/seed-stress.done
log "phase 1: 32 GiB in $((SECONDS-s)) s ($(( 32*1024/(SECONDS-s+1) )) MiB/s), $(cat /run/seed-stress.random)"; rm -f /run/seed-stress.random
check "phase 1"
log "phase 2: read-back"; sync; echo 3 > /proc/sys/vm/drop_caches; s=$SECONDS
for r in $regions; do
  a=$(gen $r | sha256sum | cut -c1-16); b=$(dd if="$dev" bs=4M skip=$(( r*G/(4<<20) )) count=2048 iflag=direct status=none | sha256sum | cut -c1-16)
  [ "$a" = "$b" ] && log "  region ${r} GiB: $b equal" || { log "FAIL: region ${r} GiB read back $b, written $a"; exit 1; }
done
log "phase 2: 32 GiB read in $((SECONDS-s)) s"; check "phase 2"
log "phase 3: mkfs.ext4 over the whole disk, inode tables and journal written now, then e2fsck -fn"; s=$SECONDS
wipefs -q -a "$dev"; mkfs.ext4 -q -F -E lazy_itable_init=0,lazy_journal_init=0 "$dev"; sync
e2fsck -fn "$dev" | tail -1; log "phase 3: $((SECONDS-s)) s"; check "phase 3"; wipefs -q -a "$dev"
log "PASS: the SSD held through mixed writes, a full read-back and a whole-disk mkfs (started $t0)"
