# site2: the second site (rung 5 › E; rung-5 › "a second site that receives an hourly, one-way,
# encrypted replica of the datasets that matter"). A NixOS VM at another place, reached only over the
# internet through the seed's tailnet, as a relative's house would be. It accepts no subnet routes
# (hosts never do). Where it runs isn't the site's business: its LAN settings are a local file,
# /etc/systemd/network/10-lan.network, kept on the box and deliberately not in this repository (a
# plain file, which NixOS leaves alone; site/runbooks/site2.md).
#
# What it does: syncoid pulls data/{documents,finance,photos,appdata} from infra every hour over the
# tailnet (root@100.64.0.10, a key whose only command is infra's zfs-send-guard.sh) into
# site2/seed, a natively encrypted parent (aes-256-gcm, keyformat hex; the key from sops, the same
# value as the vault item "zfs site2 replica key"). sanoid prunes what arrives (48 hourly, 30 daily).
# node_exporter reports the newest replicated snapshot per dataset to infra's Prometheus
# (ReplicaStale: older than 2 h).
#
# The pool: a single file vdev (/var/lib/site2-pool/vdev0) on the VM's one disk: the bench has no
# second disk for it (F-SITE2-POOL). It is created once by hand (site/runbooks/site2.md) and
# imported by site2-pool.service at every boot.
#
# Deployed by tools/site2-deploy.sh: the repo's nixos/ tree copied to site2, built there.
{ config, lib, pkgs, modulesPath, ... }:
let
  keys = import ../../keys.nix;
  infraTs = "100.64.0.10";     # infra's tailnet address (its sshd listens there: site/infra/sshd-tailnet.sh)
  datasets = [ "documents" "finance" "photos" "appdata" ];
  zfs = config.boot.zfs.package;
  syncKey = "/var/lib/syncoid/infra_ed25519";
in {
  imports = [ "${modulesPath}/profiles/qemu-guest.nix" ../../modules/reboot-required.nix ];

  # --- the VM as it was handed over (qcow2 image, 20260927): grub on vda, ext4 root labelled nixos ---
  boot.loader.grub.device = "/dev/vda";
  boot.kernelParams = [ "console=ttyS0,115200" ];
  fileSystems."/" = { device = "/dev/disk/by-label/nixos"; fsType = "ext4"; };
  services.qemuGuest.enable = true;
  networking.hostName = "site2";
  time.timeZone = "UTC";
  system.stateVersion = "26.05";
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # --- network: systemd-networkd; the LAN file is local (above), tailscale0 left to tailscaled ---
  networking.useNetworkd = true;
  networking.useDHCP = false;
  systemd.network.enable = true;
  systemd.network.networks."50-tailscale" = {
    matchConfig.Name = "tailscale0";
    linkConfig = { Unmanaged = true; ActivationPolicy = "manual"; };
  };
  services.resolved.enable = true;
  services.tailscale.enable = true;   # its state (the node, --accept-routes=false) is in /var/lib/tailscale
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
    # node_exporter for infra's Prometheus only, and only over the tailnet
    extraCommands = "iptables -A nixos-fw -i tailscale0 -s ${infraTs} -p tcp --dport 9100 -j nixos-fw-accept";
    extraStopCommands = "iptables -D nixos-fw -i tailscale0 -s ${infraTs} -p tcp --dport 9100 -j nixos-fw-accept || true";
  };

  # --- access: admin by key only (the builder on the agent box, and the orchestrator's lab fixture) ---
  services.openssh = {
    enable = true;
    settings = { PasswordAuthentication = false; KbdInteractiveAuthentication = false; PermitRootLogin = "no"; };
  };
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    # tender (the site agents) too, by its own key (Christoph, 20261004: site2 joins Tender's scope, so a site-wide
    # change can be completed by the agent; the same account and rights the agents have on the other boxes, revoked by
    # tools/site-agents-revoke.sh like the rest); deploys only through tools/site2-deploy.sh (a self-reverting timer)
    openssh.authorizedKeys.keys = [ keys.builderAgent keys.orchestrator keys.tender ];
  };
  security.sudo.wheelNeedsPassword = false;
  # infra's host key, pinned (SHA256:HOST-KEY-FINGERPRINT-PLACEHOLDER, as on the agent box)
  programs.ssh.knownHosts.infra = {
    hostNames = [ infraTs ];
    publicKey = "ssh-ed25519 AAAA...REPLACE-WITH-YOUR-PUBLIC-KEY";
  };

  # --- ZFS: the replica pool and its encrypted parent ---
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;
  networking.hostId = "00000000";  # generate your own: head -c4 /dev/urandom | od -An -tx4 | tr -d " "
  environment.systemPackages = [ pkgs.sanoid ];
  sops.defaultSopsFile = ../../secrets/site2.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.secrets.zfs_key = { };      # /run/secrets/zfs_key: site2/seed's keylocation
  systemd.services.site2-pool = {
    description = "Import the replica pool (a file vdev) and load site2/seed's key";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" "zfs-import.target" ];
    path = [ zfs ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = ''
      if [ ! -e /var/lib/site2-pool/vdev0 ]; then echo "no vdev yet (site/runbooks/site2.md, step 3)"; exit 0; fi
      zpool list site2 >/dev/null 2>&1 || zpool import -d /var/lib/site2-pool site2
      if zfs list site2/seed >/dev/null 2>&1; then
        [ "$(zfs get -H -o value keystatus site2/seed)" = available ] || zfs load-key site2/seed
        zfs mount -a
      fi
    '';
  };

  # --- the pull: syncoid, hourly, one service per dataset ---
  systemd.services.site2-syncoid-key = {
    description = "syncoid's key for infra (made here once; its public half goes to infra)";
    wantedBy = [ "multi-user.target" ];
    before = map (d: "syncoid-${d}.service") datasets;
    path = [ pkgs.openssh ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = ''
      install -d -m 0700 -o syncoid -g syncoid /var/lib/syncoid
      [ -s ${syncKey} ] || ssh-keygen -q -t ed25519 -N "" -C "syncoid@site2 seed" -f ${syncKey}
      chown syncoid:syncoid ${syncKey} ${syncKey}.pub; chmod 0600 ${syncKey}
    '';
  };
  services.syncoid = {
    enable = true;
    # at :15, after infra's snapshots at :05 (replica-snap.sh): the replica is at most ~70 min old
    interval = "*:15";
    sshKey = syncKey;
    # infra's snapshots are made by infra (replica-snap.sh): syncoid makes none on the source, holds the
    # newest common one on both sides, doesn't resume (a resume token could name any dataset, and
    # infra's guard refuses them), doesn't compress (the tailnet already encrypts; the guard allows
    # mbuffer only)
    commonArgs = [ "--no-sync-snap" "--use-hold" "--no-resume" "--compress=none" "--no-clone-handling" ];
    localTargetAllow = [ "change-key" "compression" "create" "mount" "mountpoint" "receive" "rollback" "hold" "release" ];
    service = { after = [ "site2-pool.service" "site2-syncoid-key.service" ]; requires = [ "site2-pool.service" ]; };
    # -u: receive without mounting (the unprivileged syncoid user can't mount; site2-pool mounts at boot)
    commands = lib.genAttrs datasets (d: { source = "root@${infraTs}:data/${d}"; target = "site2/seed/${d}"; recvOptions = "u"; });
  };
  # prune what arrives: infra names its snapshots as sanoid does (autosnap_…_hourly/_daily)
  services.sanoid = {
    enable = true;
    interval = "hourly";
    datasets."site2/seed" = {
      recursive = true; process_children_only = true;
      autosnap = false; autoprune = true;
      hourly = 48; daily = 30; monthly = 0; yearly = 0;
    };
  };

  # --- freshness: the newest replicated snapshot per dataset, for ReplicaStale on infra ---
  services.prometheus.exporters.node = {
    enable = true;
    enabledCollectors = [ "textfile" ];
    extraFlags = [ "--collector.textfile.directory=/var/lib/prometheus-node-exporter-text" ];
  };
  systemd.tmpfiles.rules = [ "d /var/lib/prometheus-node-exporter-text 0755 root root -" ];
  systemd.services.site2-replica-metrics = {
    description = "Newest replicated snapshot per dataset, as a metric";
    path = [ zfs pkgs.coreutils ];
    serviceConfig.Type = "oneshot";
    script = ''
      o=/var/lib/prometheus-node-exporter-text/site2-replica.prom
      {
        echo "# HELP seed_replica_newest_snapshot_timestamp_seconds Creation time (on infra) of the newest snapshot replicated to site2."
        echo "# TYPE seed_replica_newest_snapshot_timestamp_seconds gauge"
        for d in ${lib.concatStringsSep " " datasets}; do
          t=$(zfs list -Hp -t snapshot -o creation -s creation -d 1 site2/seed/$d 2>/dev/null | tail -1)
          echo "seed_replica_newest_snapshot_timestamp_seconds{dataset=\"$d\"} ''${t:-0}"
        done
        echo "# HELP seed_replica_key_loaded 1 if site2/seed's key is loaded (the replica is readable here)."
        echo "# TYPE seed_replica_key_loaded gauge"
        echo "seed_replica_key_loaded $([ "$(zfs get -H -o value keystatus site2/seed 2>/dev/null)" = available ] && echo 1 || echo 0)"
      } > $o.tmp && mv $o.tmp $o
    '';
  };
  systemd.timers.site2-replica-metrics = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnBootSec = "2min"; OnUnitActiveSec = "5min"; };
  };
}
