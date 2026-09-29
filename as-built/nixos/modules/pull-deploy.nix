# Pull-deploy from the site's forge (index › Rung 2: "NixOS from the start, deployed from the
# site's own git forge"; design › Deploying):
#  - track a `deploy` ref, not `main`: promotion is a pull request from `main` into `deploy`,
#    merged fast-forward once the required status seed/build-check passes (the forge refuses
#    direct pushes to `deploy`, owner 20260924); a revert is a pull request too;
#  - FAIL CLOSED: if the fetch fails, exit non-zero and do not build the cached tree ("Ours did
#    not, and every successful deploy was old");
#  - every attempt leaves a metric for the monitoring (last success, last attempt, result, rev).
# The deploy key is read-only on the forge repo; it lives on the box (root, 0600) and never in
# the repo. The forge's ssh host key is pinned (forge-hostkey.pub).
{ config, lib, pkgs, ... }:
let
  cfg = config.seed.pullDeploy;
  dir = "/var/lib/seed-deploy";
  textfile = "/var/lib/prometheus-node-exporter-text";
  script = pkgs.writeShellScript "seed-deploy" ''
    set -uo pipefail
    export PATH=${lib.makeBinPath [ pkgs.git pkgs.openssh pkgs.coreutils pkgs.nix config.system.build.nixos-rebuild ]}:/run/current-system/sw/bin
    url=''${SEED_DEPLOY_URL:-${cfg.url}}; ref=${cfg.ref}; repo=${dir}/repo
    export GIT_SSH_COMMAND="ssh -i ${dir}/deploy_key -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=20"
    now=$(date +%s)
    metric() {  # result: 1 success, 0 failure
      mkdir -p ${textfile}
      { echo "# HELP seed_deploy_last_attempt_timestamp_seconds Last pull-deploy attempt."
        echo "# TYPE seed_deploy_last_attempt_timestamp_seconds gauge"
        echo "seed_deploy_last_attempt_timestamp_seconds $now"
        echo "# HELP seed_deploy_last_result 1 if the last pull-deploy succeeded."
        echo "# TYPE seed_deploy_last_result gauge"
        echo "seed_deploy_last_result{stage=\"$2\"} $1"
        if [ -s ${dir}/last-success ]; then
          echo "# HELP seed_deploy_last_success_timestamp_seconds Last successful pull-deploy."
          echo "# TYPE seed_deploy_last_success_timestamp_seconds gauge"
          echo "seed_deploy_last_success_timestamp_seconds $(cut -d' ' -f1 ${dir}/last-success)"
          echo "seed_deploy_info{rev=\"$(cut -d' ' -f2 ${dir}/last-success | cut -c1-12)\"} 1"
        fi; } > ${textfile}/seed-deploy.prom.tmp && mv ${textfile}/seed-deploy.prom.tmp ${textfile}/seed-deploy.prom
    }
    fail() { echo "seed-deploy: FAILED at $1 (fail closed: nothing built)" >&2; metric 0 "$1"; exit 1; }
    if [ ! -d $repo/.git ]; then
      git clone --no-checkout --branch "$ref" --single-branch "$url" $repo || fail clone
    fi
    git -C $repo remote set-url origin "$url"
    # the fetch must succeed; a cached tree is never deployed
    git -C $repo fetch --prune origin "+refs/heads/$ref:refs/remotes/origin/$ref" || fail fetch
    git -C $repo checkout --force --detach "origin/$ref" || fail checkout
    rev=$(git -C $repo rev-parse HEAD)
    echo "seed-deploy: deploying $ref at $rev"
    nixos-rebuild switch --flake "$repo/nixos#${cfg.host}" || fail switch
    echo "$(date +%s) $rev" > ${dir}/last-success
    metric 1 done
    echo "seed-deploy: done, $rev"
  '';
in {
  options.seed.pullDeploy = {
    enable = lib.mkEnableOption "pull-deploy from the site's forge";
    url = lib.mkOption { type = lib.types.str; default = "ssh://git@git.seed.example.com:2222/seed/seed-lab.git"; };
    ref = lib.mkOption { type = lib.types.str; default = "deploy"; };
    host = lib.mkOption { type = lib.types.str; description = "nixosConfigurations name"; };
    interval = lib.mkOption { type = lib.types.str; default = "*:0/15"; };
  };
  config = lib.mkIf cfg.enable {
    programs.ssh.knownHosts.forge = {
      hostNames = [ "[git.seed.example.com]:2222" "[192.168.1.10]:2222" ];
      publicKeyFile = ../forge-hostkey.pub;
    };
    systemd.tmpfiles.rules = [ "d ${dir} 0700 root root -" "d ${textfile} 0755 root root -" ];
    systemd.services.seed-deploy = {
      description = "Pull-deploy this host from the forge's ${cfg.ref} ref (fails closed)";
      after = [ "network-online.target" ]; wants = [ "network-online.target" ];
      restartIfChanged = false;              # a deploy must not restart the deploy mid-switch
      serviceConfig = { Type = "oneshot"; ExecStart = script; TimeoutStartSec = "1h"; };
    };
    systemd.timers.seed-deploy = {
      wantedBy = [ "timers.target" ];
      timerConfig = { OnCalendar = cfg.interval; Persistent = true; RandomizedDelaySec = "2m"; OnBootSec = "5min"; };
    };
  };
}
