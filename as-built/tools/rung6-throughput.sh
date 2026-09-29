#!/usr/bin/env bash
# rung6-throughput.sh: the owner's throughput test for rung 6 (20260929). Can the configuration carry 1 Gbit/s through
# the access point and the firewall (no deep inspection), and at what load? iperf3 (and curl for the internet), both
# directions, 1 and 4 streams, 30 s each, with the load recorded on the access point (192.168.1.4: /proc/stat,
# /proc/softirqs, /proc/interrupts every 2 s; `top` mid-test) and on the firewall (192.168.1.1: vmstat every second,
# `vmstat -i` per test for re0/re1, `top -SH` mid-test).
#   tools/rung6-throughput.sh a <outdir>   the wired LAN (this box) -> the access point's bridge -> the firewall itself
#                                          (iperf3 -s on the firewall, bound to 192.168.1.1; started and removed by the caller)
#   tools/rung6-throughput.sh b <outdir>   the wired LAN -> the firewall (routed) -> VLAN 30 -> the access point -> this box's
#                                          wifi on seed-iot (seed-wifi-test@iperf; the radio on for the test only)
#   tools/rung6-throughput.sh c <outdir>   downloads and uploads through the firewall to the internet (speed.cloudflare.com)
# Writes <outdir>/<path>-raw/ (the samplers and snapshots) and appends <outdir>/<path>.txt (one line per test).
set -uo pipefail
cd "$(dirname "$0")/.."
P=${1:?a|b|c}; OUT=${2:?outdir}; mkdir -p "$OUT/$P-raw"; RAW=$OUT/$P-raw; SUM=$OUT/$P.txt
AP="ssh -o BatchMode=yes -o LogLevel=ERROR root@192.168.1.4"
FW="ssh -o BatchMode=yes -o LogLevel=ERROR -o HostKeyAlias=192.168.1.2 root@192.168.1.1"
IPERF=$(nix-shell -p iperf3 --run 'command -v iperf3' 2>/dev/null | tail -1)   # a store path for this run only

samplers_start() { # $1: seconds
  $AP "n=\$(( $1 / 2 + 2 )); while [ \$n -gt 0 ]; do echo \"T \$(date +%s) \$(grep -E '^cpu' /proc/stat | sed 's/  */,/g' | tr '\n' '|') NET_RX \$(awk '/NET_RX/{\$1=\"\"; print}' /proc/softirqs) NET_TX \$(awk '/NET_TX/{\$1=\"\"; print}' /proc/softirqs) IRQ \$(awk '/ethernet/{s=0; for(i=2;i<=NF-3;i++) s+=\$i; printf \"%s \", s}' /proc/interrupts)\"; n=\$((n-1)); sleep 2; done" > $RAW/ap-samples.txt 2>&1 &
  echo $! > $RAW/.ap.pid
  $FW "sh -c 'n=$1; while [ \$n -gt 0 ]; do echo \"T \$(date +%s) \$(vmstat -c 2 -w 1 | tail -1)\"; n=\$((n-1)); done'" > $RAW/fw-vmstat.txt 2>&1 &
  echo $! > $RAW/.fw.pid; }
samplers_stop() { kill $(cat $RAW/.ap.pid $RAW/.fw.pid) 2>/dev/null; rm -f $RAW/.ap.pid $RAW/.fw.pid; }
fw_irq() { $FW "vmstat -i | grep -E 're[01]'" | awk '{print $(NF-1)}' | paste -sd' '; }   # re0/re1 interrupt totals (MSI lines)
snap() { # $1: label; mid-test snapshots
  $AP 'top -b -n 1 | head -14' > $RAW/ap-top-$1.txt 2>&1
  $FW 'top -SHbz -d 2 -s 3 -o cpu 14' 2>&1 | awk '/^last pid/{n++} n==2' > $RAW/fw-top-$1.txt; }
# the load in a window [t0, t1]: the access point's busy and softirq %, per CPU the highest busy %, NET_RX/s, eth IRQs/s;
# the firewall's average us/sy/id and interrupts/s over the vmstat samples
load() { local t0=$1 t1=$2
  awk -v a=$t0 -v b=$t1 '$1=="T" && $2>=a && $2<=b {print}' $RAW/ap-samples.txt | awk '
    { n = split($3, c, "|"); for (i = 1; i <= n; i++) { split(c[i], f, ","); if (f[1] == "") continue
        tot = 0; for (j = 2; j <= 9; j++) tot += f[j]; idle = f[5] + f[6]
        if (!(f[1] in T0)) { T0[f[1]] = tot; I0[f[1]] = idle; S0[f[1]] = f[8] } T1[f[1]] = tot; I1[f[1]] = idle; S1[f[1]] = f[8] }
      for (k = 4; k <= NF; k++) if ($k == "NET_RX") { rx = 0; for (m = k + 1; $m != "NET_TX"; m++) rx += $m; if (!have) rx0 = rx; rx1 = rx }
      for (k = 4; k <= NF; k++) if ($k == "IRQ") { q = 0; for (m = k + 1; m <= NF; m++) q += $m; if (!have) q0 = q; q1 = q }
      if (!have) { s0 = $2; have = 1 } s1 = $2 }
    END { d = s1 - s0; if (d <= 0) { print "AP: no samples"; exit }
      dt = T1["cpu"] - T0["cpu"]; busy = 100 * (1 - (I1["cpu"] - I0["cpu"]) / dt); sirq = 100 * (S1["cpu"] - S0["cpu"]) / dt
      mx = 0; for (u in T0) if (u != "cpu") { x = T1[u] - T0[u]; if (x > 0) { b = 100 * (1 - (I1[u] - I0[u]) / x); if (b > mx) { mx = b; mc = u } } }
      printf "AP busy %.0f%% (softirq %.0f%%; busiest %s %.0f%%), NET_RX %.0f/s, eth IRQ %.0f/s", busy, sirq, mc, mx, (rx1 - rx0) / d, (q1 - q0) / d }'
  printf "; "
  awk -v a=$t0 -v b=$t1 '$1=="T" && $2>=a+1 && $2<=b {n++; us+=$(NF-2); sy+=$(NF-1); id+=$NF; inn+=$(NF-5)} END {if (n) printf "FW us %.0f%% sy %.0f%% idle %.0f%%, interrupts %.0f/s", us/n, sy/n, id/n, inn/n; else printf "FW: no samples"}' $RAW/fw-vmstat.txt; }

case $P in
a) # iperf3 server on the firewall at 192.168.1.1:5201 (the caller starts and removes it)
  echo "# path (a) $(date -u +%FT%TZ): this box (wired, 2.5 GbE) -> the switch -> the access point's eth1 (1 GbE) -> br-lan -> eth0 (2.5 GbE trunk) -> the firewall's re1 (2.5 GbE); iperf3 server on the firewall" >> $SUM
  samplers_start 20; sleep 18; echo "idle: $(load $(( $(date +%s) - 16 )) $(date +%s))" >> $SUM; samplers_stop; snap idle
  samplers_start 200
  for t in "1 fwd" "4 fwd" "1 rev" "4 rev"; do set -- $t; flag=""; [ $2 = rev ] && flag=-R
    i0=$(fw_irq); t0=$(date +%s)
    $IPERF -c 192.168.1.1 -p 5201 -t 30 -P $1 $flag -f m > $RAW/iperf-P$1-$2.txt 2>&1 &
    ip=$!; sleep 15; snap P$1-$2; wait $ip; t1=$(date +%s); i1=$(fw_irq)
    r=$(grep -E 'receiver' $RAW/iperf-P$1-$2.txt | tail -1 | grep -oE '[0-9.]+ Mbits/sec'); s=$(grep -E 'sender' $RAW/iperf-P$1-$2.txt | tail -1 | awk '{for (i = 1; i <= NF; i++) if ($i == "sender") print $(i-1)}')
    echo "P=$1 $2 ($( [ $2 = fwd ] && echo 'LAN -> firewall' || echo 'firewall -> LAN')): ${r:-FAIL} (retransmits ${s:-?}) | $(load $((t0+3)) $((t1-2))) | FW re0 re1 IRQs: $i0 -> $i1 in $((t1-t0)) s" >> $SUM
    sleep 5; done
  samplers_stop ;;
b) # the unit runs the four tests; the load is cut out of the samples by its start/end lines
  echo "# path (b) $(date -u +%FT%TZ): this box (wired) -> the switch -> the access point -> the firewall (routes LAN <-> VLAN 30) -> the trunk -> the access point -> wifi seed-iot (5 GHz) -> this box's card (network namespace); bounded by the wifi link" >> $SUM
  samplers_start 300; tools/router-wifi.sh on >/dev/null 2>&1
  systemctl start seed-wifi-test@iperf.service; rc=$?
  tools/router-wifi.sh off >/dev/null 2>&1; samplers_stop
  f=$(readlink -f /var/lib/seed-wifi-test/iperf-latest.txt); cp "$f" $RAW/; echo "unit rc $rc; $(basename "$f")" >> $SUM
  grep -E '^# the wifi link' "$f" >> $SUM
  for t in "1 fwd" "4 fwd" "1 rev" "4 rev"; do set -- $t
    t0=$(date -d "$(awk -v k="# test P=$1 $2 start" 'index($0,k)==1 {print $NF}' "$f")" +%s); t1=$(date -d "$(awk -v k="# test P=$1 $2 end" 'index($0,k)==1 {print $NF}' "$f")" +%s)
    r=$(grep -F "# P=$1 $2:" "$f" | grep receiver | grep -oE '[0-9.]+ Mbits/sec')
    echo "P=$1 $2 ($( [ $2 = fwd ] && echo 'LAN -> wifi' || echo 'wifi -> LAN')): ${r:-FAIL} | $(load $((t0+3)) $((t1-2)))" >> $SUM; done ;;
c) # the internet through the firewall: Cloudflare's speed endpoints, 30 s each, 1 and 4 parallel transfers
  echo "# path (c) $(date -u +%FT%TZ): this box -> the access point -> the firewall (NAT) -> the upstream -> hil-speed.hetzner.com (downloads), speed.cloudflare.com (uploads); bounded by the provider and the far end" >> $SUM
  samplers_start 300
  # downloads: Hetzner's public test file in Hillsboro (Cloudflare's __down refused large and then all requests after
  # repeated runs, 20260929), one 10 GB file per transfer, cut at 30 s
  dl() { curl -s -o /dev/null --max-time 30 -w '%{size_download} %{time_total}\n' https://hil-speed.hetzner.com/10GB.bin; }
  ul() { head -c 25000000000 /dev/zero | curl -s -o /dev/null --max-time 30 -X POST -T - -w '%{size_upload} %{time_total}\n' https://speed.cloudflare.com/__up; }
  for t in "1 down" "4 down" "1 up" "4 up"; do set -- $t; t0=$(date +%s)
    ( for i in $(seq 1 $1); do if [ $2 = down ]; then dl; else ul; fi & done; wait ) > $RAW/curl-P$1-$2.txt 2>&1 &
    cp=$!; sleep 15; snap P$1-$2; wait $cp; t1=$(date +%s)
    r=$(awk '{b+=$1; if ($2>t) t=$2} END {if (t>0) printf "%.0f Mbits/sec", b*8/t/1e6; else print "FAIL"}' $RAW/curl-P$1-$2.txt)
    echo "P=$1 $2: $r | $(load $((t0+3)) $((t1-2)))" >> $SUM; sleep 5; done
  samplers_stop ;;
esac
cat $SUM
