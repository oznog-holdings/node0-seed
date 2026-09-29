#!/bin/bash
# The fast UPS producer (R1.88's UPS state; 20260928): apcupsd's state every 10 s, so infra's
# UpsOnBattery can fire inside a fast shutdown (the UPS test of 20260927 shut infra down 97 s after the
# cut, before the 5-minute seed-metrics.sh ran). Run every minute by User Scripts; each run reads six
# times, 10 s apart, under a lock. Writes seed-ups.prom for node_exporter's textfile collector (temp
# file and rename). seed-metrics.sh no longer writes these series.
set -uo pipefail
umask 022
OUT=/mnt/data/system/metrics; mkdir -p $OUT
exec 9>/var/run/seed-ups-metrics.lock; flock -n 9 || exit 0
for i in 1 2 3 4 5 6; do
  t0=$(date +%s); tmp=$(mktemp $OUT/.seed-ups.prom.XXXXXX)
  {
  echo '# HELP seed_ups_on_battery 1 while the UPS reports anything but mains (ONBATT, SHUTTING DOWN, LOWBATT, ...).'
  echo '# TYPE seed_ups_on_battery gauge'
  echo '# HELP seed_ups_battery_charge_percent Battery charge.'
  echo '# TYPE seed_ups_battery_charge_percent gauge'
  echo '# HELP seed_ups_timeleft_minutes Estimated runtime left.'
  echo '# TYPE seed_ups_timeleft_minutes gauge'
  echo '# HELP seed_ups_up 1 if apcupsd answered.'
  echo '# TYPE seed_ups_up gauge'
  if a=$(timeout 5 apcaccess 2>/dev/null) && [ -n "$a" ]; then
    st=$(awk -F': ' '/^STATUS/{print $2}' <<<"$a")
    echo "seed_ups_up 1"
    # anything but mains (ONLINE, alone or with TRIM/BOOST) counts: ONBATT, LOWBATT, SHUTTING DOWN, ...
    # (only *ONBATT* counted until 20260927, and the UPS test's SHUTTING DOWN read as mains: F-UPS-WATCH)
    rest=$(awk '{for (i = 1; i <= NF; i++) if ($i != "ONLINE" && $i != "TRIM" && $i != "BOOST") printf "%s ", $i}' <<<"$st")
    echo "seed_ups_on_battery $([[ " $st " == *" ONLINE "* && -z $rest ]] && echo 0 || echo 1)"
    echo "seed_ups_battery_charge_percent $(awk -F': ' '/^BCHARGE/{print $2+0}' <<<"$a")"
    echo "seed_ups_timeleft_minutes $(awk -F': ' '/^TIMELEFT/{print $2+0}' <<<"$a")"
  else echo "seed_ups_up 0"; fi
  echo '# HELP seed_ups_metrics_last_run_timestamp_seconds When this producer last wrote.'
  echo '# TYPE seed_ups_metrics_last_run_timestamp_seconds gauge'
  echo "seed_ups_metrics_last_run_timestamp_seconds $(date +%s)"
  } > "$tmp" && chmod 644 "$tmp" && mv "$tmp" $OUT/seed-ups.prom
  [ $i -lt 6 ] && sleep $(( 10 - ($(date +%s) - t0) > 0 ? 10 - ($(date +%s) - t0) : 0 ))
done
exit 0
