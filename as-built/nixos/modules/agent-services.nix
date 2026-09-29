# Rung 2 on the agent box (index › Rung 2; design › Backups, Deploying, Monitoring, Secrets).
{ config, lib, pkgs, ... }:
let
  textfile = "/var/lib/prometheus-node-exporter-text";
  stamp = name: pkgs.writeShellScript "stamp-${name}" ''
    mkdir -p ${textfile}
    printf '# HELP seed_job_last_success_timestamp_seconds Last successful completion of a site job.\n# TYPE seed_job_last_success_timestamp_seconds gauge\nseed_job_last_success_timestamp_seconds{task="${name}"} %s\n' "$(date +%s)" \
      > ${textfile}/${name}.prom.tmp && mv ${textfile}/${name}.prom.tmp ${textfile}/${name}.prom
  '';
in {
  # --- secrets: encrypted in the repo (nixos/secrets/agent.yaml, three recipients), decrypted at
  # activation with this host's ssh key, root-only files under /run/secrets (design › Secrets)
  sops = {
    defaultSopsFile = ../secrets/agent.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets = {
      tailscale_authkey = { };
      restic_repository = { };
      restic_password = { };
      ntfy_url = { };
      ntfy_core_token = { };   # core's ntfy (rung 3), user watcher, write-only on topic seed
    };
  };

  # --- the agent account: sudo for named commands only (design › three boundaries, R2.23).
  # Each only runs one of this box's own declared jobs now: the pull-deploy (which applies only
  # what is already on the forge's `deploy` ref), the /work backup, the watcher, the build check.
  security.sudo.extraRules = [ {
    users = [ "agent" ];
    commands = map (u: { command = "/run/current-system/sw/bin/systemctl start ${u}.service"; options = [ "NOPASSWD" ]; })
      [ "seed-deploy" "restic-backups-work" "seed-watcher" "seed-build-check" "seed-pr-check" ];
  } ];

  # --- Tailscale: the second subnet router for the site's range; never accepts routes (a host
  # inside the site must prefer the LAN beside it). Route approval is a person's, in the admin console.
  services.tailscale = {
    enable = true;
    authKeyFile = config.sops.secrets.tailscale_authkey.path;
    useRoutingFeatures = "server";
    openFirewall = true;
    extraUpFlags = [ "--advertise-routes=192.168.1.0/24" "--accept-routes=false" "--accept-dns=false" "--hostname=agent" ];
  };

  # --- flow 2: /work to infra's append-only rest-server every two hours (design › Backups;
  # Development: source trees backed up, stores and build output not). As root, so both users'
  # trees are covered. :45 past odd hours: clear of agentvm's :15 and the 02:00 prune.
  services.restic.backups.work = {
    repositoryFile = config.sops.secrets.restic_repository.path;
    passwordFile = config.sops.secrets.restic_password.path;
    paths = [ "/work" ];
    exclude = [ "node_modules" ".pnpm-store" "target" "dist" ".cache" ];
    extraBackupArgs = [ "--host=agent" "--tag=work" "--retry-lock=10m" ];
    initialize = true;
    # fail closed at the source (design › Backups; R0.19): an unmounted /work is an empty
    # directory on the root filesystem and would back up "successfully", protecting nothing
    backupPrepareCommand = ''
      ${pkgs.util-linux}/bin/mountpoint -q /work || { echo "/work is not mounted: no backup" >&2; exit 1; }
      [ -n "$(ls -A /work/agent 2>/dev/null)" ] || { echo "/work/agent is empty: no backup" >&2; exit 1; }
    '';
    pruneOpts = [ ];                           # the server is the one writer (forget and prune on infra)
    timerConfig = { OnCalendar = "01/2:45"; Persistent = true; RandomizedDelaySec = "5m"; };
  };
  systemd.services.restic-backups-work.serviceConfig.ExecStartPost = [ "${stamp "backup-work"}" ];

  # --- monitoring OF this box: node_exporter (with the textfile metrics of deploy, watcher,
  # backups and builds), reachable from infra's Prometheus only
  services.prometheus.exporters.node = {
    enable = true;
    listenAddress = "192.168.1.11";
    port = 9100;
    enabledCollectors = [ "systemd" "textfile" ];
    extraFlags = [ "--collector.textfile.directory=${textfile}" ];
  };
  # It binds 192.168.1.11 itself, which doesn't exist until networkd has configured the port: at the
  # rebuild of 20260927 it failed 5 times in 2 s and hit the start limit (F-REBUILD-EXPORTER). Wait for
  # the network, and keep retrying rather than give up.
  systemd.services.prometheus-node-exporter = {
    after = [ "network-online.target" ]; wants = [ "network-online.target" ];
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig = { Restart = lib.mkForce "always"; RestartSec = lib.mkForce "5s"; };
  };
  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -p tcp -s 192.168.1.10 --dport 9100 -j nixos-fw-accept
  '';
  networking.firewall.extraStopCommands = ''
    iptables -D nixos-fw -p tcp -s 192.168.1.10 --dport 9100 -j nixos-fw-accept || true
  '';

  # --- the nightly build check (design › Deploying: "build every host's closure nightly from
  # deploy, so a failed build is an alert before it is a broken deploy"). It fetches the deploy
  # ref with the same read-only key (fails closed like the deploy) and builds every host.
  systemd.services.seed-build-check = {
    description = "Build every host's closure from the forge's deploy ref";
    after = [ "network-online.target" ]; wants = [ "network-online.target" ];
    path = [ pkgs.git pkgs.openssh pkgs.nix pkgs.coreutils ];
    environment.GIT_SSH_COMMAND = "ssh -i /var/lib/seed-deploy/deploy_key -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes";
    script = ''
      set -uo pipefail
      r=/var/lib/seed-build/repo; mkdir -p /var/lib/seed-build ${textfile}; ok=1
      if [ ! -d $r/.git ]; then git clone --no-checkout --branch deploy --single-branch ${config.seed.pullDeploy.url} $r || ok=0; fi
      if [ $ok = 1 ]; then git -C $r fetch --prune origin +refs/heads/deploy:refs/remotes/origin/deploy && git -C $r checkout --force --detach origin/deploy || ok=0; fi
      if [ $ok = 1 ]; then
        for h in $(nix --extra-experimental-features 'nix-command flakes' eval --json "$r/nixos#nixosConfigurations" --apply builtins.attrNames | tr -d '[]"' | tr , ' '); do
          echo "building $h"
          nix --extra-experimental-features 'nix-command flakes' build --no-link "$r/nixos#nixosConfigurations.$h.config.system.build.toplevel" || { echo "build of $h FAILED"; ok=0; }
        done
      fi
      { echo "# HELP seed_build_check_last_result 1 if every host's closure built from deploy."
        echo "# TYPE seed_build_check_last_result gauge"
        echo "seed_build_check_last_result $ok"
        echo "# HELP seed_build_check_last_attempt_timestamp_seconds Last nightly build check."
        echo "# TYPE seed_build_check_last_attempt_timestamp_seconds gauge"
        echo "seed_build_check_last_attempt_timestamp_seconds $(date +%s)"; } > ${textfile}/seed-build.prom.tmp && mv ${textfile}/seed-build.prom.tmp ${textfile}/seed-build.prom
      [ $ok = 1 ] && ${stamp "build-check"}
      [ $ok = 1 ]
    '';
    serviceConfig = { Type = "oneshot"; TimeoutStartSec = "2h"; };
  };
  systemd.timers.seed-build-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "*-*-* 03:30:00"; Persistent = true; RandomizedDelaySec = "10m"; };
  };
}
