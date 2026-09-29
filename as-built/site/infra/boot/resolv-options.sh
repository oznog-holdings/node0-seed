#!/bin/bash
# infra's resolver options (the owner's decision, 20260929): with ns2 (192.168.1.16, the first resolver) down, glibc
# waited its default 5 s per try before asking ns1; `timeout:1 attempts:2` cuts that to about 1 s. Unraid's rc.inet1
# rewrites /etc/resolv.conf from network.cfg at boot (and when the network settings are applied), so /boot/config/go
# runs this at every boot before emhttp starts the array and Docker (containers copy the host's file at start).
# Idempotent; installed as /boot/config/seed/resolv-options.sh (site/infra/boot/). check-after-reboot checks the line.
f=/etc/resolv.conf; want='options timeout:1 attempts:2'
grep -qx "$want" "$f" || { grep -v '^options ' "$f" > "$f.seed" && echo "$want" >> "$f.seed" && cat "$f.seed" > "$f"; rm -f "$f.seed"; }
logger -t seed-resolv "resolv.conf: $(grep -c '^nameserver' "$f") nameservers, $(grep '^options' "$f")"
