#!/bin/sh
# dns-compare.sh: every name on stdin ("name type" per line), asked of each server in $SERVERS (default
# AdGuard core .12, AdGuard infra .10, Technitium ns1 .15, ns2 .16), answers sorted; one row per name with
# "same" when every server gave the same answer (rung 5 › B: the migration verified from a third machine;
# the default was AdGuard core .12, infra .10, ns1 .15, ns2 .16 until AdGuard retired).
# POSIX sh and dig only, so it runs as is on the agent box (dig from nixpkgs) and on macOS (compute).
# Usage: tools/dns-compare.sh < names   (prints rows, then "N names, M differ"; exit 1 if any differ)
SERVERS=${SERVERS:-"192.168.1.15 192.168.1.16"}   # Technitium ns1, ns2 (AdGuard .12/.10 retired 20260929; set SERVERS to compare others)
n=0; bad=0
while read -r name type; do
  [ -z "$name" ] && continue; n=$((n+1)); row=""; first=""; same=same
  for s in $SERVERS; do
    a=$(dig +short +time=3 +tries=2 "@$s" "$name" "${type:-A}" | grep -v '^;' | sort | tr '\n' ' ' | sed 's/ $//')
    [ -z "$a" ] && a='(none)'
    row="$row | $a"; [ -z "$first" ] && first=$a; [ "$a" = "$first" ] || same=DIFFER
  done
  [ $same = same ] || bad=$((bad+1))
  printf '%s %s%s | %s\n' "$name" "${type:-A}" "$row" "$same"
done
echo "$n names, $bad differ (servers: $SERVERS)"
[ $bad = 0 ]
