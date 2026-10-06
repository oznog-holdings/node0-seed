#!/usr/bin/env bash
# Deploy site2 (rung 5 › E) from a ref of this repository, by default the promoted `deploy` branch
# (site/runbooks/promote.md; its build check builds site2 like every host). The nixos/ tree is copied to site2 and built
# there: site2's admin isn't a nix trusted user, so a closure pushed from here would be refused, and site2 substitutes
# from cache.nixos.org itself. site2 is remote-only (no console within reach), so a change never lands without a way
# back that needs nothing from us (20261004, Christoph: site2 in Tender's scope, the agents run this too):
#   tools/site2-deploy.sh dry-run [ref]   copy and build; show what would change (dry-activate); nothing activated
#   tools/site2-deploy.sh test [ref]      copy and BUILD first (the closure recorded in /var/lib/seed-tested); then ARM a
#                                         self-reverting timer (absolute UTC deadline, REVERT_MIN minutes, default 15:
#                                         back to the boot default's system); then activate THAT closure with `test`
#                                         (not the boot default, so a reboot also returns), only while the deadline is
#                                         still ahead and under the lock the revert takes too
#   tools/site2-deploy.sh confirm         after checking site2 healthy: stop the timer and make the TESTED closure (the
#                                         recorded one, nothing rebuilt) the boot default; without it the timer reverts
#   tools/site2-deploy.sh status          what runs, what boots, what was tested, and the timer
# Health before confirm (what the builder checked on 20261004): ssh over the tailnet answers, no failed units,
# tailscaled, sshd, node-exporter, networkd active, the pool ONLINE, Prometheus up=1, no new alerts.
set -euo pipefail
cd "$(dirname "$0")/.."
mode=${1:?dry-run, test, confirm or status}
remote=$(git remote | grep -x forge || git remote | grep -x origin)
ref=${2:-$remote/deploy}; M=${REVERT_MIN:-15}
S="ssh -o BatchMode=yes -o StrictHostKeyChecking=yes admin@100.64.0.12"
R() { $S "set -euo pipefail; $1"; }   # every remote command fails on any failed stage (a | tail hides nothing)
LOCK=/run/seed-upgrade.lock
copy() {
  git fetch -q "$remote"; rev=$(git rev-parse --verify "$ref^{commit}"); echo "site2: $mode from $ref ($rev)"
  git archive --format=tar "$rev" nixos | R "sudo rm -rf /var/lib/seed-src.new; sudo mkdir -p /var/lib/seed-src.new
    sudo tar -x -C /var/lib/seed-src.new; echo $rev | sudo tee /var/lib/seed-src.new/REV >/dev/null
    sudo rm -rf /var/lib/seed-src; sudo mv /var/lib/seed-src.new /var/lib/seed-src"
  new=$(R "sudo nix --extra-experimental-features 'nix-command flakes' build --no-link --print-out-paths path:/var/lib/seed-src/nixos#nixosConfigurations.site2.config.system.build.toplevel")
  [[ $new == /nix/store/*-nixos-system-site2-* ]] || { echo "the build gave no system ($new)"; exit 1; }
  echo "built: $new"; }
status() { R 'echo "runs:   $(readlink -f /run/current-system)"; echo "boots:  $(readlink -f /nix/var/nix/profiles/system)"
  echo "tested: $(cat /var/lib/seed-tested 2>/dev/null || echo -)"
  echo "revert timer: $(systemctl show seed-upgrade-revert.timer -p NextElapseUSecRealtime --value 2>/dev/null) ($(systemctl is-active seed-upgrade-revert.timer 2>/dev/null || true))"
  echo "failed units: $(systemctl --failed --no-legend | wc -l)"'; }
case $mode in
  dry-run) copy; R "sudo $new/bin/switch-to-configuration dry-activate 2>&1 | tail -25"; status ;;
  test)
    ! R 'systemctl is-active -q seed-upgrade-revert.timer' || { echo "a revert timer is already armed: confirm or let it revert first"; exit 1; }
    copy
    # the way back first: a transient timer on an absolute deadline (a reload doesn't re-base it), to the boot default,
    # under the lock; then the activation of the built closure, under the same lock, only if the deadline is ahead
    R "dl=\$(date -u -d '+$M min' '+%Y-%m-%d %H:%M:%S UTC'); old=\$(readlink -f /nix/var/nix/profiles/system)
      sudo systemd-run -q --unit seed-upgrade-revert --on-calendar=\"\$dl\" --timer-property=AccuracySec=1s \
        /bin/sh -c \"flock $LOCK \$old/bin/switch-to-configuration switch; echo reverted to \$old at \\\$(date -u +%FT%TZ) >> /var/log/seed-upgrade-revert.log\"
      echo $new | sudo tee /var/lib/seed-tested >/dev/null
      echo \"revert armed: to \$old at \$dl\""
    R "sudo flock $LOCK sh -c 'set -o pipefail; nx=\$(systemctl show seed-upgrade-revert.timer -p NextElapseUSecRealtime --value)
        [ -n \"\$nx\" ] && [ \$(date -d \"\$nx\" +%s) -gt \$(( \$(date +%s) + 60 )) ] || { echo \"the revert deadline is not a minute ahead: NOT activated\"; exit 1; }
        $new/bin/switch-to-configuration test 2>&1 | tail -8'"
    status; echo "CHECK site2's health now; then: tools/site2-deploy.sh confirm (within $M minutes), or let it revert" ;;
  confirm)
    R 'systemctl is-active -q seed-upgrade-revert.timer' || { echo "no revert timer armed: nothing to confirm (test first)"; exit 1; }
    t=$(R 'cat /var/lib/seed-tested'); run=$(R 'readlink -f /run/current-system')
    [ "$t" = "$run" ] || { echo "site2 runs $run, not the tested $t: not confirmed (the timer stays)"; exit 1; }
    R "sudo flock $LOCK sh -c 'set -o pipefail; systemctl stop seed-upgrade-revert.timer && nix-env -p /nix/var/nix/profiles/system --set $t && $t/bin/switch-to-configuration switch 2>&1 | tail -4'"
    echo "confirmed: $t is the boot default"; status ;;
  status) status ;;
  *) echo "mode: dry-run, test, confirm or status"; exit 2 ;;
esac
