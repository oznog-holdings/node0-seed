#!/bin/bash
# D.05 memory measurement on infra (deviation: "Rung 1 first runs with Unraid limited to
# 16 GB (mem=18G on this model), measures, then removes the limit and measures again").
# Read-only: the load step is a restic backup --dry-run of the site-data paths (reads and
# hashes everything, uploads nothing, adds no snapshot) plus a 1/26 verify sweep of b2-infra.
# Limits, seen in the 16 GB baseline (20260924): the load step is light (the dry-run covers
# 1.26 GiB in about 9 s), so memory barely moves; the comparison that matters is at rest
# (MemAvailable, ARC size against c_max, per-container RSS). The Unraid kernel has no PSI.
# Usage on infra: d05-measure.sh <label>   (label: 16g or 48g). Output to stdout; save it as
# evidence/<date>-d05-<label>.txt. Run it at least 30 minutes after boot, containers settled.
set -uo pipefail
label=${1:?label}
sec() { echo; echo "## $*"; }
snap() {
  echo "time $(date -u +%FT%TZ)"
  free -m | sed -n '1,3p'
  awk '/^(MemTotal|MemAvailable|Cached|SwapTotal|SwapFree|Shmem):/' /proc/meminfo
  # hits and misses are counts, the rest bytes (until 20260924 the counts were divided by 2^20 too)
  awk '/^(size|c|c_min|c_max|arc_meta_used) /{printf "arc %s %.0f MiB\n", $1, $3/1048576} /^(hits|misses) /{print "arc " $1 " " $3}' /proc/spl/kstat/zfs/arcstats
  [ -r /proc/pressure/memory ] && sed 's/^/psi memory /' /proc/pressure/memory || echo "psi memory: not in this kernel"
  docker stats --no-stream --format '{{.Name}} {{.MemUsage}}' | sort
  virsh dommemstat agentvm 2>/dev/null | awk '/^(actual|rss|swap_in|major_fault)/{print "agentvm " $0}'
}
sec "D.05 $label: identity"
cat /etc/unraid-version; uptime; cat /proc/cmdline
echo "fitted: $(dmidecode -t memory 2>/dev/null | awk '/^\tSize: [0-9]+ (GB|GiB)/{s+=$2} END{print s " GiB"}')"
echo "zfs_arc_max param: $(cat /sys/module/zfs/parameters/zfs_arc_max) ($(grep -h arc /boot/config/modprobe.d/* 2>/dev/null))"
sec "at rest"; snap
sec "under load: restic backup --dry-run of the site-data paths and a 1/26 check of b2-infra, sampled every 20 s"
/mnt/data/system/seed-bin/restic.sh check --read-data-subset=1/26 >/dev/null 2>&1 &
chk=$!
docker run --rm --env-file /mnt/data/system/secrets/restic-infra.env --hostname infra -v /mnt/data:/mnt/data:ro -v /boot:/boot:ro restic/restic:0.19.1@sha256:136600b6ff6843d61d355f7f71f460a166429f35de6fd11b568fece3c9a4d510 backup --dry-run --no-cache --host infra --exclude /mnt/data/system/docker --exclude /mnt/data/domains --exclude /mnt/data/backups /mnt/data/documents /mnt/data/finance /mnt/data/photos /mnt/data/appdata /mnt/data/system/identity /boot >/dev/null 2>&1 &
bk=$!
for i in 1 2 3 4 5 6; do sleep 20; echo "--- sample $i"; free -m | sed -n 2p; awk '/^size /{printf "arc size %.0f MiB\n", $3/1048576}' /proc/spl/kstat/zfs/arcstats; head -1 /proc/pressure/memory 2>/dev/null; done
wait $chk $bk 2>/dev/null
sec "after load"; snap
