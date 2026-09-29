# The watcher (index › Rung 2: "a watcher the size of a cron job that pings DNS, backups and
# the web front door and sends one line when any of them fails"). It runs on the agent box and
# reaches ntfy directly, never through infra (an alert about infra must not pass through it):
# from rung 3 core's own ntfy, and the hosted topic when core's does not take the line.
# It also probes Unraid's own web page on :80, which answers from the RAM root even when the
# array is stopped, so a message can tell "infra up, array or services down" from "infra
# unreachable" (proposal of F-ARRAY-AUTOSTART). One line per change of state, not per run.
{ config, lib, pkgs, ... }:
let
  state = "/var/lib/seed-watcher";
  textfile = "/var/lib/prometheus-node-exporter-text";
  script = pkgs.writeShellScript "seed-watcher" ''
    set -uo pipefail
    export PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.curl pkgs.dnsutils pkgs.restic pkgs.jq pkgs.gnugrep ]}   # coreutils: timeout, date
    fails=()
    # 1. DNS: Technitium, ns1 (core's second address, the primary) and ns2 (a container on infra's br0,
    #    which infra itself can't reach, so this is its only probe) answer the site's names and filter (a
    #    known ad domain -> 0.0.0.0). AdGuard on .12 and .10 retired 20260929 (rung 5 › F). dig 9.20
    #    writes ";; communications error ... timed out" to stdout for a lost try even when the retry
    #    answers, so its comment lines are dropped before comparing (F-UPS-DNS, 20260927)
    for ns in 192.168.1.15:ns1 192.168.1.16:ns2; do
      [ "$(dig +short +time=3 +tries=2 @''${ns%%:*} infra.seed.example.com | grep -v '^;')" = 192.168.1.10 ] || fails+=("DNS on ''${ns#*:}")
      [ "$(dig +short +time=3 +tries=2 @''${ns%%:*} doubleclick.net | grep -v '^;')" = 0.0.0.0 ] || fails+=("filtering on ''${ns#*:}")
    done
    # 2. the web front door (needs the array, Docker and Caddy)
    [ "$(curl -s -m 10 -o /dev/null -w '%{http_code}' https://infra.seed.example.com/healthz)" = 200 ] || fails+=("front door")
    # 3. Unraid itself (RAM root: up even with the array stopped)
    code=$(curl -s -m 10 -o /dev/null -w '%{http_code}' http://192.168.1.10/)
    case "$code" in 200|301|302) unraid=up;; *) unraid=down; fails+=("Unraid web UI");; esac
    # 4. backups: this box's own newest snapshot on the rest-server, under 3 hours
    # (timeout: restic retries for minutes when the rest-server is unreachable; that counts as
    # "unreadable", it must not hang the watcher. Ages via date -d: restic's times carry
    # nanoseconds and offsets that jq's strptime mishandled, 20260924.)
    newest=0
    for t in $(RESTIC_REPOSITORY_FILE=${config.sops.secrets.restic_repository.path} RESTIC_PASSWORD_FILE=${config.sops.secrets.restic_password.path} \
      timeout 60 restic snapshots --no-lock --json --latest 1 2>/dev/null | jq -r '.[].time' 2>/dev/null); do
      e=$(date -d "$t" +%s 2>/dev/null || echo 0); [ "$e" -gt "$newest" ] && newest=$e
    done
    [ $(( $(date +%s) - newest )) -lt 10800 ] || fails+=("backups (agent's newest snapshot over 3 h old or unreadable)")
    if [ ''${#fails[@]} -eq 0 ]; then now=ok
    elif [ "$unraid" = up ]; then now="infra up, but failing: $(IFS=,; echo "''${fails[*]}") (array or services down?)"
    else now="infra unreachable (Unraid web UI down too): $(IFS=,; echo "''${fails[*]}")"; fi
    mkdir -p ${state}; prev=$(cat ${state}/last 2>/dev/null || echo ok)
    if [ "$now" != "$prev" ]; then
      if [ "$now" = ok ]; then msg="recovered: DNS (ns1, ns2), front door, Unraid and backups all fine"; title="seed watcher: OK"; prio=default
      else msg="$now"; title="seed watcher: FAILING"; prio=high; fi
      # core's ntfy first (token on curl's stdin, never its argv), the hosted topic as the fallback
      if printf 'header = "Authorization: Bearer %s"\n' "$(cat ${config.sops.secrets.ntfy_core_token.path})" \
           | curl -sf -m 15 -K - -H "Title: $title" -H "Priority: $prio" -H "Tags: seed,watcher" -d "$msg" https://ntfy.seed.example.com/seed >/dev/null \
         || curl -sf -m 15 -H "Title: $title" -H "Priority: $prio" -H "Tags: seed,watcher,fallback" -d "$msg" "$(cat ${config.sops.secrets.ntfy_url.path})" >/dev/null; then
        echo "$now" > ${state}/last
      else echo "seed-watcher: could not reach either ntfy" >&2; fi
    fi
    echo "seed-watcher: $now"
    mkdir -p ${textfile}
    { echo "# HELP seed_watcher_last_run_timestamp_seconds Last run of the watcher on the agent box."
      echo "# TYPE seed_watcher_last_run_timestamp_seconds gauge"
      echo "seed_watcher_last_run_timestamp_seconds $(date +%s)"
      echo "# HELP seed_watcher_ok 1 if every watched thing was fine on the last run."
      echo "# TYPE seed_watcher_ok gauge"
      echo "seed_watcher_ok $([ "$now" = ok ] && echo 1 || echo 0)"; } > ${textfile}/seed-watcher.prom.tmp && mv ${textfile}/seed-watcher.prom.tmp ${textfile}/seed-watcher.prom
  '';
in {
  systemd.tmpfiles.rules = [ "d ${state} 0700 root root -" ];
  systemd.services.seed-watcher = {
    description = "Watch DNS, the front door, Unraid and backups; one ntfy line per change";
    after = [ "network-online.target" ]; wants = [ "network-online.target" ];
    serviceConfig = { Type = "oneshot"; ExecStart = script; TimeoutStartSec = "4min"; };   # never outlive its 5-minute cycle
  };
  systemd.timers.seed-watcher = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnBootSec = "3min"; OnUnitActiveSec = "5min"; };
  };
}
