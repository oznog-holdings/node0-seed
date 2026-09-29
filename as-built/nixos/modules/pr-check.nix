# The build check as a required status on `deploy` (owner, 20260924: "deploy takes merges only,
# with your build check as a required status"; design › Deploying: "build every host's closure
# ... so a failed build is an alert before it is a broken deploy"). Every 5 minutes it lists
# the open pull requests into `deploy`; for each head commit without a finished
# `seed/build-check` status it posts "pending", builds every host's closure from that commit,
# checks core's Debian tree (shell syntax), and posts success or
# failure. The forge refuses a merge into `deploy` without success on the exact commit.
# It fetches with the box's read-only deploy key (pull refs included) and posts as the forge
# user seed-buildcheck, whose token (scope write:repository) comes from sops.
{ config, lib, pkgs, ... }:
let
  state = "/var/lib/seed-pr-check";
  api = "https://git.seed.example.com/api/v1/repos/seed/seed-lab";
  ctx = "seed/build-check";
  py = pkgs.python3.withPackages (p: [ p.pyyaml ]);
  script = pkgs.writeShellScript "seed-pr-check" ''
    set -uo pipefail
    export PATH=${lib.makeBinPath [ pkgs.git pkgs.openssh pkgs.nix pkgs.coreutils pkgs.curl pkgs.jq pkgs.bash py pkgs.findutils pkgs.gnugrep ]}
    export GIT_SSH_COMMAND="ssh -i /var/lib/seed-deploy/deploy_key -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes"
    tokf=${config.sops.secrets.forge_status_token.path}
    A() { printf 'header = "Authorization: token %s"\n' "$(cat $tokf)" | curl -sf -m 30 -K - -H 'Content-Type: application/json' "$@"; }
    status() {  # sha state description
      jq -n --arg s "$2" --arg d "$3" --arg c "${ctx}" '{state: $s, context: $c, description: $d}' > ${state}/status.json
      A -X POST "${api}/statuses/$1" -d @${state}/status.json >/dev/null || echo "could not post $2 for $1" >&2
    }
    mkdir -p ${state}; r=${state}/repo
    [ -d $r/.git ] || git clone --no-checkout ${config.seed.pullDeploy.url} $r || exit 1
    prs=$(A "${api}/pulls?state=open&limit=50") || { echo "cannot list pull requests" >&2; exit 1; }
    for pr in $(jq -r '.[] | select(.base.ref == "deploy") | "\(.number):\(.head.sha)"' <<<"$prs"); do
      n=''${pr%%:*}; sha=''${pr#*:}
      done_state=$(A "${api}/commits/$sha/status" | jq -r --arg c "${ctx}" '[.statuses[]? | select(.context == $c) | .status] | first // ""')
      # success and failure are verdicts on the commit; error (the fetch failed, e.g. a push the
      # forge hadn't published under refs/pull yet) is retried on the next run
      case "$done_state" in success|failure) continue ;; esac
      echo "PR #$n: checking $sha"
      status $sha pending "building every host from this commit"
      if ! git -C $r fetch --prune origin "+refs/pull/$n/head:refs/pr/$n" || ! git -C $r checkout --force --detach "$sha" \
         || [ "$(git -C $r rev-parse HEAD)" != "$sha" ]; then status $sha error "could not fetch this commit"; continue; fi
      fail=""
      for h in $(nix --extra-experimental-features 'nix-command flakes' eval --json "$r/nixos#nixosConfigurations" --apply builtins.attrNames | tr -d '[]"' | tr , ' '); do
        nix --extra-experimental-features 'nix-command flakes' build --no-link "$r/nixos#nixosConfigurations.$h.config.system.build.toplevel" \
          || { fail="build of $h failed"; break; }
      done
      # core (Debian): the scripts parse (AdGuard's renders retired with it, rung 5 › F, 20260929)
      if [ -z "$fail" ]; then
        for f in $r/site/core/apply $r/site/core/seed-deploy $(find $r/site/core/files/usr/local/sbin -type f); do
          bash -n "$f" || { fail="core: $(basename $f) does not parse"; break; }; done
      fi
      if [ -z "$fail" ]; then status $sha success "every host built; core's tree checked"; echo "PR #$n $sha: success"
      else status $sha failure "$fail"; echo "PR #$n $sha: $fail"; fi
    done
  '';
in {
  sops.secrets.forge_status_token = { };
  systemd.services.seed-pr-check = {
    description = "Build check for pull requests into deploy (the required status seed/build-check)";
    after = [ "network-online.target" ]; wants = [ "network-online.target" ];
    serviceConfig = { Type = "oneshot"; ExecStart = script; TimeoutStartSec = "2h"; };
  };
  systemd.timers.seed-pr-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnBootSec = "5min"; OnUnitInactiveSec = "5min"; };
  };
}
