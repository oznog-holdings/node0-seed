#!/usr/bin/env bash
# After the orchestrator's core cold boot (N20: plug4 off ~6 min, then on). Read-only. Answers:
#  R1.33 / R3.02: core booted without a clock; how long until it served synced time, and did it
#                 ever offer unsynced time as good (a stratum-10 answer before its first sync)?
#  R3.14:         did the alarm about core reach a person without core's ntfy (the hosted topic)?
# Sources: the agent box's NTP watch (tools/ntp-watch.py, evidence/.../core-coldboot-ntp.log),
# core's own journal for this boot, Prometheus (ALERTS over the window), the hosted ntfy topic.
set -uo pipefail
cd "$(dirname "$0")/.."
L=evidence/20260924-closeout/core-coldboot-ntp.log
off=$(grep -m1 'no answer' $L | cut -d' ' -f1); back=$(awk '/no answer/{seen=1; next} seen && /answer stratum/{print $1; exit}' $L)
echo "## NTP from the agent box: first silence $off, first answer after it $back"
[ -n "$off" ] || { echo "no silence in the watch: the cold boot hasn't happened (or the watch ended)"; exit 1; }
awk -v b="$back" '$1>=b && /answer stratum/' $L | head -30 | awk '{print $1, $4, $6, "ref", $8, $10, $11}'
first_sync=$(awk -v b="$back" '$1>=b && /answer stratum/ && $4<=5 && $6==0 {print $1; exit}' $L)
bad=$(awk -v b="$back" -v f="$first_sync" '$1>=b && (f=="" || $1<f) && /answer stratum 10 leap 0/' $L | wc -l)
echo "first synced answer (stratum <= 5, leap 0): ${first_sync:-none yet}; stratum-10 answers offered before it: $bad"

echo "## core, this boot"
ssh -o BatchMode=yes admin@192.168.1.12 'echo "booted $(uptime -s) (up $(uptime -p))"
  sudo -n journalctl -b -u chrony --no-pager -o short-iso | grep -E "Selected source|System clock|stepped|wrong|Can.t synchronise|Received KoD|chronyd version" | head -8
  chronyc -n tracking | egrep "Reference|Stratum|System time|Leap"
  for u in chrony technitium ntfy seed-deploy.timer seed-power-watch.timer; do printf "%s=%s " $u "$(systemctl is-active $u)"; done; echo'
site/bin/check-dns 2>&1 | tail -2
curl -s -o /dev/null -w "ntfy on core: %{http_code}\n" https://ntfy.seed.example.com/v1/health

echo "## alerts about core over the window (Prometheus)"
s=$(date -d "$off - 2 min" +%s); e=$(date +%s)
ssh -o BatchMode=yes root@192.168.1.10 "curl -s --get http://127.0.0.1:9090/api/v1/query_range --data-urlencode 'query=ALERTS{alertstate=\"firing\",host=\"core\"}' --data-urlencode start=$s --data-urlencode end=$e --data-urlencode step=30" \
  | jq -r '.data.result[] | "\(.metric.alertname) \(.metric.instance // "") firing \(.values[0][0]|todate) .. \(.values[-1][0]|todate)"'

echo "## the hosted topic (the path that doesn't use core's ntfy), messages since the silence"
. "${SEED_REPO:-/work/agent/seed-lab}/tools/vault-env.sh"   # the site vault (SEED_VAULT=hosted: break-glass)
S=$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null); unset BW_PASSWORD BW_CLIENTSECRET
T=$(BW_SESSION=$S bw get password 'ntfy seed topic' 2>/dev/null); BW_SESSION=$S bw lock >/dev/null 2>&1
curl -s "https://ntfy.sh/$T/json?poll=1&since=$(date -d "$off" +%s)" | jq -r 'select(.event=="message") | "\(.time|todate) \(.title // "") | \(.message | .[0:90] | gsub("\n";" "))"'
unset T
