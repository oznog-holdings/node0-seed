# seed-selfcheck (20260930): a small periodic check on the agent box that core's status page says "ok" at /selfcheck
# (site/core/files/etc/systemd/system/seed-statuspage.service). It fails, and shows in `systemctl --failed`, when
# the page says anything else or doesn't answer.
{ pkgs, ... }:
{
  systemd.services.seed-selfcheck = {
    description = "seed self-check: core's status page";
    serviceConfig = { Type = "oneshot"; DynamicUser = true; };
    path = [ pkgs.curl pkgs.gnugrep ];
    script = "curl -fsS -m 10 http://192.168.1.12:8099/selfcheck | grep -qx ok";
  };
  systemd.timers.seed-selfcheck = { wantedBy = [ "timers.target" ]; timerConfig = { OnCalendar = "*:0/5"; Persistent = false; }; };
}
