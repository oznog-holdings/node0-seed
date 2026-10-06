# seed_reboot_required for a NixOS host (20261004: no rule watched for a host needing a reboot; the nixpkgs upgrade of 20261004 left new kernels installed and not running). Every 15 minutes: 1 when
# the running (booted) kernel, initrd or kernel modules differ from the installed system's, else 0. The textfile
# collector reads it; the rule RebootRequired (rules/agent.yml) alerts after a while. A reboot stays ask-first.
{ pkgs, lib, ... }:
let textfile = "/var/lib/prometheus-node-exporter-text"; in {
  systemd.services.seed-reboot-required = {
    description = "Whether this host needs a reboot to run its installed system (seed_reboot_required)";
    serviceConfig.Type = "oneshot";
    path = [ pkgs.coreutils ];
    script = ''
      mkdir -p ${textfile}; n=0; why=none
      for p in kernel initrd kernel-modules; do
        [ "$(readlink -f /run/booted-system/$p)" = "$(readlink -f /run/current-system/$p)" ] || { n=1; why=$p; }
      done
      { echo "# HELP seed_reboot_required 1 if the running kernel, initrd or modules differ from the installed system's."
        echo "# TYPE seed_reboot_required gauge"
        echo "seed_reboot_required{reason=\"$why\"} $n"; } > ${textfile}/seed-reboot.prom.tmp && mv ${textfile}/seed-reboot.prom.tmp ${textfile}/seed-reboot.prom
    '';
  };
  systemd.timers.seed-reboot-required = { wantedBy = [ "timers.target" ]; timerConfig = { OnBootSec = "2min"; OnUnitActiveSec = "15min"; }; };
}
