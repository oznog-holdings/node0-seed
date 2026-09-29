#!/usr/bin/env bash
# Deploy site2 (rung 5 › E) from a ref of this repository, by default the forge's promoted `deploy` branch
# (site/runbooks/promote.md; its build check builds site2 like every host). The nixos/ tree is copied to
# site2 and built there: site2's admin isn't a nix trusted user, so a closure pushed from here would be
# refused, and site2 substitutes from cache.nixos.org itself. Usage: tools/site2-deploy.sh test|switch|boot [ref]
# `test` activates without making it the boot default (a reboot returns to the last `boot`/`switch`).
set -euo pipefail
cd "$(dirname "$0")/.."
mode=${1:?test, switch or boot}; ref=${2:-forge/deploy}
case $mode in test|switch|boot) ;; *) echo "mode: test, switch or boot"; exit 2 ;; esac
git fetch -q forge
rev=$(git rev-parse --verify "$ref^{commit}")
S="ssh -o BatchMode=yes -o StrictHostKeyChecking=yes admin@100.64.0.12"
echo "site2: $mode from $ref ($rev)"
git archive --format=tar "$rev" nixos | $S "set -e; sudo rm -rf /var/lib/seed-src.new; sudo mkdir -p /var/lib/seed-src.new
  sudo tar -x -C /var/lib/seed-src.new; echo $rev | sudo tee /var/lib/seed-src.new/REV >/dev/null
  sudo rm -rf /var/lib/seed-src; sudo mv /var/lib/seed-src.new /var/lib/seed-src"
$S "sudo nixos-rebuild $mode --flake path:/var/lib/seed-src/nixos#site2 2>&1 | tail -15"
$S 'echo "site2 now: $(readlink /run/current-system) (source $(cat /var/lib/seed-src/REV))"'
