#!/bin/bash
# Producer for the rung-1 monitoring floor (design › Monitoring): writes Prometheus textfile
# metrics for node_exporter's textfile collector. Runs every 5 minutes (User Scripts).
# Only ages, counts, states and completion times: no financial or personal data (R1.87).
# Written to a temp file and renamed, so node_exporter never reads half a file.
set -uo pipefail
umask 022
OUT=/mnt/data/system/metrics; mkdir -p $OUT; tmp=$(mktemp $OUT/.seed.prom.XXXXXX)
state=/mnt/data/system/seed-state
{
# 1. job completion timestamps (R1.79): every job writes <name>.last on success only
echo '# HELP seed_job_last_success_timestamp_seconds Last successful completion of a site job.'
echo '# TYPE seed_job_last_success_timestamp_seconds gauge'
for f in $state/*.last; do
  n=$(basename "$f" .last); v=$(cat "$f" 2>/dev/null); [[ $v =~ ^[0-9]+$ ]] || continue
  echo "seed_job_last_success_timestamp_seconds{task=\"$n\"} $v"
done

# 2. backup age per repository, read from the repositories' side
echo '# HELP seed_backup_last_snapshot_timestamp_seconds Newest snapshot written to the repository.'
echo '# TYPE seed_backup_last_snapshot_timestamp_seconds gauge'
v=$(cat $state/backrest-site-data.last 2>/dev/null) && echo "seed_backup_last_snapshot_timestamp_seconds{repo=\"b2-infra\",flow=\"site-data\"} $v"
# DORMANT: rest-server repositories whose machine no longer writes on purpose, kept for their
# snapshots. Their age is reported as flow="dormant", which no freshness rule expects to be new.
# agentvm from 20260928: its /work was retired and emptied, its backup plan stopped (the owner's
# decision; hosts/agentvm/configuration.nix). The same list is in weekly-verify.sh.
DORMANT="agentvm"
for d in /mnt/data/backups/rest/*/snapshots; do
  m=$(basename "$(dirname "$d")"); v=$(find "$d" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1 | cut -d. -f1)
  fl=machines; case " $DORMANT " in *" $m "*) fl=dormant ;; esac
  [ -n "$v" ] && echo "seed_backup_last_snapshot_timestamp_seconds{repo=\"rest-$m\",flow=\"$fl\"} $v"
done

# 2b. the router's configuration against the repository (device-config.sh's drift check; rung 5)
echo '# HELP seed_router_config_drift_lines Lines of the router config differing from the repository (-1: no expected copy).'
echo '# TYPE seed_router_config_drift_lines gauge'
v=$(cat $state/router-drift.lines 2>/dev/null) && [[ $v =~ ^-?[0-9]+$ ]] && echo "seed_router_config_drift_lines $v"

# 2c. the firewall's configuration against the repository (device-config.sh; rung 6): -1 no expected copy, -2 no export
echo '# HELP seed_firewall_config_drift_lines Lines of the firewall config export differing from the repository (-1: no expected copy, -2: no export).'
echo '# TYPE seed_firewall_config_drift_lines gauge'
v=$(cat $state/firewall-drift.lines 2>/dev/null) && [[ $v =~ ^-?[0-9]+$ ]] && echo "seed_firewall_config_drift_lines $v"

# 3. restore test and verify sweep (weekly-verify.sh): result as a state, skipped is its own value
echo '# HELP seed_restore_test_result Last weekly restore test per repository (1 for the current result).'
echo '# TYPE seed_restore_test_result gauge'
for f in $state/*.restore.result; do
  r=$(basename "$f" .restore.result); res=$(cat "$f")
  for s in ok fail skipped; do echo "seed_restore_test_result{repo=\"$r\",result=\"$s\"} $([ "$res" = $s ] && echo 1 || echo 0)"; done
done

# 4. ZFS: pool state, last scrub result and end time
echo '# HELP seed_zpool_healthy 1 if the pool is ONLINE.'
echo '# TYPE seed_zpool_healthy gauge'
echo '# HELP seed_zpool_scrub_errors Errors reported by the last completed scrub.'
echo '# TYPE seed_zpool_scrub_errors gauge'
echo '# HELP seed_zpool_scrub_repaired_bytes Bytes repaired by the last completed scrub.'
echo '# TYPE seed_zpool_scrub_repaired_bytes gauge'
echo '# HELP seed_zpool_scrub_end_timestamp_seconds End of the last completed scrub.'
echo '# TYPE seed_zpool_scrub_end_timestamp_seconds gauge'
for p in $(zpool list -H -o name); do
  h=$(zpool list -H -o health "$p"); echo "seed_zpool_healthy{pool=\"$p\"} $([ "$h" = ONLINE ] && echo 1 || echo 0)"
  line=$(zpool status "$p" | grep -E '^\s*scan: scrub repaired')
  if [[ $line =~ repaired\ ([0-9.]+)([BKMGT]?)\ in\ .*\ with\ ([0-9]+)\ errors\ on\ (.*)$ ]]; then
    num=${BASH_REMATCH[1]}; unit=${BASH_REMATCH[2]}; err=${BASH_REMATCH[3]}; when=${BASH_REMATCH[4]}
    case $unit in K) mul=1024;; M) mul=1048576;; G) mul=1073741824;; T) mul=1099511627776;; *) mul=1;; esac
    echo "seed_zpool_scrub_repaired_bytes{pool=\"$p\"} $(awk "BEGIN{printf \"%d\", $num*$mul}")"
    echo "seed_zpool_scrub_errors{pool=\"$p\"} $err"
    echo "seed_zpool_scrub_end_timestamp_seconds{pool=\"$p\"} $(date -d "$when" +%s)"
  fi
done

# 5. SMART, per serial (the counts belong on a dashboard with the serial; the rule is on growth)
echo '# HELP seed_smart_media_errors NVMe media and data integrity errors (count; alert on growth).'
echo '# TYPE seed_smart_media_errors counter'
echo '# HELP seed_smart_error_log_entries NVMe error information log entries (count; alert on growth).'
echo '# TYPE seed_smart_error_log_entries counter'
echo '# HELP seed_smart_critical_warning NVMe critical warning bits (0 is healthy).'
echo '# TYPE seed_smart_critical_warning gauge'
echo '# HELP seed_smart_percentage_used NVMe endurance used, percent.'
echo '# TYPE seed_smart_percentage_used gauge'
echo '# HELP seed_smart_temperature_celsius Drive temperature.'
echo '# TYPE seed_smart_temperature_celsius gauge'
for dev in /dev/nvme[0-9]n1; do
  j=$(smartctl -j -a "$dev" 2>/dev/null) || true
  s=$(jq -r '.serial_number // empty' <<<"$j"); [ -n "$s" ] || continue
  m=$(jq -r '.model_name // "?"' <<<"$j" | tr -d '"'); l="serial=\"$s\",model=\"$m\""
  jq -r --arg l "$l" '.nvme_smart_health_information_log // {} |
    "seed_smart_media_errors{\($l)} \(.media_errors // 0)",
    "seed_smart_error_log_entries{\($l)} \(.num_err_log_entries // 0)",
    "seed_smart_critical_warning{\($l)} \(.critical_warning // 0)",
    "seed_smart_percentage_used{\($l)} \(.percentage_used // 0)",
    "seed_smart_temperature_celsius{\($l)} \(.temperature // 0)"' <<<"$j"
done

# 6. UPS: moved to seed-ups-metrics.sh (every 10 s; 20260928), so the power alert can fire inside a
#    fast shutdown. Not written here: two files with the same series would break the textfile collector.

# 8. the model gateway and the rung-4 backend (R4.11): real requests through the gateway on infra's loopback with
#    the monitoring-probe key (secrets/monitoring-probe.env, from the vault): the gateway's own self-test, then one
#    request per route on compute, labelled route=: local-embed only from 20261002 (the utility tier: the two chat models,
#    local-text and local-chat, load on demand and swap; a probe of either would load it beside the other; a short
#    completion with thinking off) and local-embed (an embedding). A success writes its time to a state file per
#    route, so the age survives failed runs. Counts and times only; no content kept.
echo '# HELP seed_gateway_selftest_success 1 if the gateway answered its self-test model.'
echo '# TYPE seed_gateway_selftest_success gauge'
echo '# HELP seed_inference_probe_success 1 if the route on compute answered through the gateway.'
echo '# TYPE seed_inference_probe_success gauge'
echo '# HELP seed_inference_probe_duration_seconds Time the probe request took.'
echo '# TYPE seed_inference_probe_duration_seconds gauge'
echo '# HELP seed_inference_last_success_timestamp_seconds When a probe request to the route last succeeded.'
echo '# TYPE seed_inference_last_success_timestamp_seconds gauge'
GWK=$(sed -n 's/^GATEWAY_PROBE_KEY=//p' /mnt/data/system/secrets/monitoring-probe.env 2>/dev/null)
gw() { curl -s -m "$1" -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $GWK" -H 'Content-Type: application/json' \
  --data-binary @- "http://127.0.0.1:4000/v1/${2:-chat/completions}"; }
st=$(printf '{"model":"seed-selftest","messages":[{"role":"user","content":"probe"}]}' | gw 15)
echo "seed_gateway_selftest_success $([ "$st" = 200 ] && echo 1 || echo 0)"
mkdir -p $OUT/.state
probe() { # route endpoint timeout body
  local t0 code dur; t0=$(date +%s%N); code=$(printf '%s' "$4" | gw "$3" "$2")
  dur=$(awk -v a="$t0" -v b="$(date +%s%N)" 'BEGIN {printf "%.3f", (b - a) / 1e9}')
  if [ "$code" = 200 ]; then echo "seed_inference_probe_success{route=\"$1\"} 1"; date +%s > $OUT/.state/inference.$1.last
  else echo "seed_inference_probe_success{route=\"$1\"} 0"; fi
  echo "seed_inference_probe_duration_seconds{route=\"$1\"} $dur"
  [ -s $OUT/.state/inference.$1.last ] && echo "seed_inference_last_success_timestamp_seconds{route=\"$1\"} $(cat $OUT/.state/inference.$1.last)"; }
# the smallest real request (20260930): a 1-token prompt, 1 token out, identical to the site agents' route check so
# both share one cached slot; about a second, and never an agent's slot (the preset has a third)
probe local-embed embeddings 120 '{"model":"local-embed","input":"ok"}'
unset GWK

# 6b. datasets with a quota: used against it (20261004: no rule watched
# for it)
echo '# HELP seed_zfs_dataset_used_bytes Bytes used by a dataset that has a quota.'
echo '# TYPE seed_zfs_dataset_used_bytes gauge'
echo '# HELP seed_zfs_dataset_quota_bytes The dataset quota.'
echo '# TYPE seed_zfs_dataset_quota_bytes gauge'
zfs get -Hp -o name,value -t filesystem quota 2>/dev/null | while read -r ds q; do
  [ "$q" -gt 0 ] 2>/dev/null || continue
  echo "seed_zfs_dataset_quota_bytes{dataset=\"$ds\"} $q"
  echo "seed_zfs_dataset_used_bytes{dataset=\"$ds\"} $(zfs get -Hp -o value used "$ds")"
done

# 7. this producer's own heartbeat
echo '# HELP seed_metrics_last_run_timestamp_seconds When seed-metrics.sh last completed.'
echo '# TYPE seed_metrics_last_run_timestamp_seconds gauge'
echo "seed_metrics_last_run_timestamp_seconds $(date +%s)"
} > "$tmp" && chmod 644 "$tmp" && mv "$tmp" $OUT/seed.prom
