#!/usr/bin/env bash
# zfs-demos.sh: the rung-1 storage demonstrations (R1.05; D.10), run on infra as root:
#   cat tools/zfs-demos.sh | ssh root@192.168.1.10 bash -s <special|raidz|all>
# Every command is printed before its output ("$ ..."), so the log reads as a transcript
# (site/runbooks/zfs-demos.md explains it for a reader).
#   special  a throwaway pool: data on the spare 1 TB (SERIAL-PLACEHOLDER), a special vdev on the empty
#            Optane (SERIAL-PLACEHOLDER). Where metadata and small blocks land; why a special vdev must
#            be as redundant as the pool; that it can be removed from a pool without raidz and not from
#            one with raidz (shown on file vdevs). Destroyed afterwards, and both drives wiped
#   mirror   the proper form (20260928): data on the 1 TB, the special vdev a MIRROR of both Optanes
#            (SERIAL-PLACEHOLDER, SERIAL-PLACEHOLDER). Where metadata and small blocks land; one Optane
#            offlined: the pool stays up (DEGRADED), reads and writes go on, same hashes; online again,
#            resilvered. Destroyed afterwards, all three drives wiped
#   raidz    raidz expansion on file vdevs in RAM: raidz1 3 wide -> 4 wide with the data online and
#            the same hash; old blocks keep the old data-to-parity ratio until rewritten (zfs rewrite);
#            and a mirror only ever becomes a wider mirror
# Guards: the data pool and SERIAL-PLACEHOLDER (an older server's pool, the owner's call) are never
# named; the two drives are found by serial, must be unassigned in Unraid, unmounted, and not in any
# imported pool.
set -uo pipefail
run() { echo "\$ $*"; "$@" 2>&1; echo; }
note() { echo "# $*"; }
BIG=SERIAL-PLACEHOLDER; SMALL=SERIAL-PLACEHOLDER; SMALL2=SERIAL-PLACEHOLDER
NEVER=   # SERIAL-PLACEHOLDER was never used until the owner freed it (20260928: its old pool not needed)
dev() { readlink -f "$(ls /dev/disk/by-id/nvme-*_"$1" | head -1)"; }
guard() {
  local d; d=$(dev "$1"); [[ $d == /dev/nvme*n1 ]] || { echo "guard: no device for serial $1"; exit 1; }
  [ "$(lsblk -dno SERIAL "$d")" = "$1" ] || { echo "guard: $d serial mismatch"; exit 1; }
  lsblk -no MOUNTPOINT "$d" | grep -q . && { echo "guard: something on $d is mounted"; exit 1; }
  grep -q "$1" /boot/config/disk.cfg /boot/config/pools/*.cfg 2>/dev/null && { echo "guard: $1 is assigned in Unraid"; exit 1; }
  zpool status -P 2>/dev/null | grep -q "$(basename "$d")" && { echo "guard: $d is in an imported pool"; exit 1; }
  [ -z "$NEVER" ] || [ "$1" != "$NEVER" ] || { echo "guard: $NEVER is never used"; exit 1; }
  echo "$d"
}
special() {
  note "== the special vdev: a throwaway pool on the spare 1 TB, with the empty Optane as its special vdev"
  B=$(guard $BIG) || { echo "$B"; exit 1; }; S=$(guard $SMALL) || { echo "$S"; exit 1; }
  BI=/dev/disk/by-id/$(ls /dev/disk/by-id | grep -E "_${BIG}\$" | head -1); SI=/dev/disk/by-id/$(ls /dev/disk/by-id | grep -E "_${SMALL}\$" | head -1)
  note "guards passed: $BIG = $B, $SMALL = $S; unassigned, unmounted, in no pool. The data pool:"
  run zpool list -o name,size,alloc,health data
  run wipefs -a "$BI"; run wipefs -a "$SI"
  run zpool create -f -o ashift=12 -O compression=lz4 -O atime=off -R /tmp/zdemo demo "$BI" special "$SI"
  run zpool list -v -o name,size,alloc,free demo
  note "two datasets: 'big' keeps the default (only metadata goes to the special vdev), 'small' also sends every block of 32K or less there"
  run zfs create demo/big; run zfs create -o recordsize=128K -o special_small_blocks=32K demo/small
  note "write 2 GiB of large files (random, so compression can't hide them) and 20,000 files of 4 KiB"
  run sh -c 'for i in 1 2 3 4; do head -c 512M /dev/urandom > /tmp/zdemo/demo/big/f$i; done; sync'
  run zpool list -v -o name,size,alloc,free demo
  run sh -c 'mkdir -p /tmp/zdemo/demo/small/d; for i in $(seq 1 20000); do head -c 4096 /dev/urandom > /tmp/zdemo/demo/small/d/s$i; done; sync'
  run zpool list -v -o name,size,alloc,free demo
  run zfs list -o name,used,recordsize,special_small_blocks -r demo
  note "a metadata walk: 20,000 files listed with the pool freshly imported (no cache), metadata on the Optane"
  run zpool export demo; run zpool import -d /dev/disk/by-id -R /tmp/zdemo demo
  run sh -c 'time (find /tmp/zdemo/demo/small -type f | wc -l)'
  note "removing the special vdev: allowed here (no raidz in the pool); its blocks move to the 1 TB"
  run zpool remove demo "$SI"; run zpool wait -t remove demo; run zpool list -v -o name,size,alloc,free demo
  run sh -c 'sha256sum /tmp/zdemo/demo/big/f1 | cut -c1-16'
  run zpool destroy demo; run wipefs -a "$BI"; run wipefs -a "$SI"
  note "the same move where the data vdev is raidz (as in the data pool): not allowed. File vdevs in RAM"
  mkdir -p /tmp/zfiles; for f in r1 r2 r3 s1 s2; do truncate -s 256M /tmp/zfiles/$f; done
  run zpool create -o ashift=12 rzs raidz1 /tmp/zfiles/r1 /tmp/zfiles/r2 /tmp/zfiles/r3 special mirror /tmp/zfiles/s1 /tmp/zfiles/s2
  run zpool remove rzs mirror-1
  note "and a special vdev less redundant than the pool is refused unless forced: losing it loses the pool"
  truncate -s 256M /tmp/zfiles/s3; run zpool add rzs special /tmp/zfiles/s3
  run zpool destroy rzs; rm -f /tmp/zfiles/r? /tmp/zfiles/s?
  run lsblk -o NAME,SERIAL,FSTYPE,PARTUUID "$B" "$S"
  run zpool list -o name,size,alloc,health
}
mirror() {
  note "== a mirrored special vdev: data on the spare 1 TB, the special vdev a mirror of both Optanes"
  B=$(guard $BIG) || { echo "$B"; exit 1; }; S=$(guard $SMALL) || { echo "$S"; exit 1; }; S2=$(guard $SMALL2) || { echo "$S2"; exit 1; }
  id() { echo /dev/disk/by-id/$(ls /dev/disk/by-id | grep -E "_${1}\$" | head -1); }
  BI=$(id $BIG); SI=$(id $SMALL); SI2=$(id $SMALL2)
  note "guards passed: $BIG = $B, $SMALL = $S, $SMALL2 = $S2; unassigned, unmounted, in no pool. The data pool:"
  run zpool list -o name,size,alloc,health data
  run wipefs -a "$BI"; run wipefs -a "$SI"; run wipefs -a "$SI2"
  run zpool create -f -o ashift=12 -O compression=lz4 -O atime=off -R /tmp/zdemo demo "$BI" special mirror "$SI" "$SI2"
  run zpool status demo
  run zfs create demo/big; run zfs create -o special_small_blocks=32K demo/small
  note "2 GiB of large files (their data to the 1 TB, their metadata to the mirror) and 20,000 files of 4 KiB (to the mirror)"
  run sh -c 'for i in 1 2 3 4; do head -c 512M /dev/urandom > /tmp/zdemo/demo/big/f$i; done; mkdir -p /tmp/zdemo/demo/small/d; for i in $(seq 1 20000); do head -c 4096 /dev/urandom > /tmp/zdemo/demo/small/d/s$i; done; sync'
  run zpool list -v -o name,size,alloc,free demo
  run zfs list -o name,used,special_small_blocks -r demo
  run sh -c 'cd /tmp/zdemo/demo; sha256sum big/f1 | cut -c1-16; cat small/d/s* | sha256sum | cut -c1-16'
  note "one Optane of the mirror offlined: the pool stays up, DEGRADED; reads and writes go on"
  run zpool offline demo "$SI2"
  run sh -c "zpool status demo | sed -n '/state:/p;/config:/,/errors/p'"
  run sh -c 'zpool export demo && zpool import -d /dev/disk/by-id -R /tmp/zdemo demo && echo "exported and imported again with one Optane offline: the metadata comes from the other"'
  run sh -c 'cd /tmp/zdemo/demo; sha256sum big/f1 | cut -c1-16; cat small/d/s* | sha256sum | cut -c1-16; ls small/d | wc -l'
  run sh -c 'head -c 4096 /dev/urandom > /tmp/zdemo/demo/small/d/while-degraded; sync; ls -la /tmp/zdemo/demo/small/d/while-degraded | cut -c1-60'
  note "online again: the mirror resilvers what it missed"
  run zpool online demo "$SI2"; run zpool wait -t resilver demo
  run sh -c "zpool status demo | sed -n '/state:/p;/scan:/p;/config:/,/errors/p'"
  run zpool scrub -w demo
  run sh -c "zpool status demo | sed -n '/scan:/p;/errors:/p'"
  run zpool destroy demo; run wipefs -a "$BI"; run wipefs -a "$SI"; run wipefs -a "$SI2"
  run lsblk -o NAME,SERIAL,FSTYPE,PARTUUID "$B" "$S" "$S2"
  run zpool list -o name,size,alloc,health
}
raidz() {
  note "== raidz expansion on file vdevs (in RAM; the data pool untouched)"
  mkdir -p /tmp/zfiles; for f in f1 f2 f3 f4 m1 m2 m3; do truncate -s 512M /tmp/zfiles/$f; done
  run zpool create -o ashift=12 -O compression=off -R /tmp/zr rz raidz1 /tmp/zfiles/f1 /tmp/zfiles/f2 /tmp/zfiles/f3
  run zpool get -H feature@raidz_expansion rz
  run sh -c 'head -c 600M /dev/urandom > /tmp/zr/rz/data; sync; sha256sum /tmp/zr/rz/data | cut -c1-16'
  run zpool list -o name,size,alloc,free rz; run zfs list -o name,used,avail rz
  note "attach a fourth disk to the raidz1 vdev: it stays online while the vdev is reflowed"
  run zpool attach rz raidz1-0 /tmp/zfiles/f4
  run zpool wait -t raidz_expand rz
  run sh -c "zpool status rz | sed -n '/expand/p;/raidz1-0/,/f4/p'"
  run zpool list -o name,size,alloc,free rz; run zfs list -o name,used,avail rz
  run sh -c 'sha256sum /tmp/zr/rz/data | cut -c1-16'
  note "the blocks written before keep the 2 data + 1 parity layout; rewriting them uses 3 + 1"
  run zfs rewrite -v /tmp/zr/rz/data
  run sh -c 'sync; sleep 2; sha256sum /tmp/zr/rz/data | cut -c1-16'
  run zpool list -o name,size,alloc,free rz; run zfs list -o name,used,avail rz
  run zpool destroy rz
  note "a mirror never becomes raidz: attaching to a mirror makes a wider mirror"
  run zpool create -o ashift=12 mz mirror /tmp/zfiles/m1 /tmp/zfiles/m2
  run zpool attach mz /tmp/zfiles/m1 /tmp/zfiles/m3
  run sh -c "zpool status mz | sed -n '/config:/,/errors/p'"
  run zpool destroy mz; rm -rf /tmp/zfiles /tmp/zr
  run zpool list -o name,size,alloc,health
}
echo "# $(date -u +%FT%TZ) on $(hostname), $(zfs version | head -1)"
case ${1:-all} in special) special ;; mirror) mirror ;; raidz) raidz ;; all) special; raidz ;; *) echo "usage: special|mirror|raidz|all"; exit 2 ;; esac
