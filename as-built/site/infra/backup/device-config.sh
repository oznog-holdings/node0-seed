#!/bin/bash
# Device config backup (design › Inventory: "pull every management device's config to the repo on a
# schedule, from the day the device arrives"; Services: "Device config backup | infra, on a
# schedule"; R1.66). Daily from User Scripts. Pulls each management device's configuration and
# commits it to the forge repo seed/device-configs when it changed.
#   router: /usr/libexec/seed-config-export over ssh with a key whose only command is that export
#           (secrets are redacted on the router); host key pinned in known_hosts below
#   UPS:    Unraid's UPS settings (flash dynamix.apcupsd.cfg) and the rendered apcupsd.conf (no secrets)
#   switch: unmanaged (nothing to pull)
#   firewall (rung 6): /usr/local/sbin/seed-config-export over ssh with key fw_ed25519, whose only command on the
#           firewall is that export (restrict, from infra only; site/firewall/device-config-authorized-key). It
#           redacts on the firewall: the WAN's values (the owner's), the fixture: rules (the lab's), every secret.
#           Compared with device-configs-expected/firewall.xml (the repo's site/firewall/config.expected.xml):
#           seed-state/firewall-drift.lines and .diff, seed_firewall_config_drift_lines, FirewallConfigDrift.
#           FW is its LAN address: 192.168.1.1 from the cut-over (20260929; 192.168.1.2 beside the router before it).
#           The router is pulled at 192.168.1.4, the access point, from the cut-over.
# Keys in /mnt/data/system/secrets/device-config (0700): router_ed25519 (forced command on the
# router), forge_ed25519 (write deploy key on seed/device-configs only). Writes
# seed-state/device-config.last on success (JobStale).
# The drift check (rung 5 brief › A; R5.01, R5.03): the router's uci part, in the normal form of
# uci-normal.awk (the lab's sections left out, secrets redacted), against the repository's, which
# site/router/config-tool pushes to device-configs-expected/router.normal. The count of differing
# lines goes to seed-state/router-drift.lines (-1: no expected copy), the diff (redacted, no lab
# sections) to router-drift.diff; seed-metrics.sh exports it and RouterConfigDrift fires on non-zero.
set -euo pipefail
umask 077
K=/mnt/data/system/secrets/device-config; W=/mnt/data/system/device-configs; state=/mnt/data/system/seed-state
REPO=ssh://git@git.seed.example.com:2222/seed/device-configs.git
log() { echo "$(date -u +%FT%TZ) $*"; }
export GIT_SSH_COMMAND="ssh -i $K/forge_ed25519 -o IdentitiesOnly=yes -o BatchMode=yes -o UserKnownHostsFile=$K/known_hosts -o StrictHostKeyChecking=yes"
[ -d "$W/.git" ] || git clone -q "$REPO" "$W"
cd "$W"
git -c user.name=x -c user.email=x pull -q --ff-only
out=$(mktemp); trap 'rm -f $out' EXIT
ssh -n -i $K/router_ed25519 -o IdentitiesOnly=yes -o BatchMode=yes -o UserKnownHostsFile=$K/known_hosts \
  -o StrictHostKeyChecking=yes -o ConnectTimeout=10 root@192.168.1.4 export > "$out" 2>/dev/null
grep -q '^### uci export' "$out" || { log "FAIL: router export incomplete"; exit 1; }
# belt and braces: nothing that looks like a secret value leaves infra
if grep -qE "^\s*(option|list) (key|password|psk|sae_password|private_key|preshared_key|secret) '[^<]" "$out"; then
  log "FAIL: router export carries an unredacted secret option; not committed"; exit 1; fi
mkdir -p router ups firewall
FW=192.168.1.1   # the firewall, the LAN gateway from the rung 6 cut-over (20260929); the router is the access point at .4
fwout=$(mktemp); trap 'rm -f $out $fwout' EXIT
if ssh -n -i $K/fw_ed25519 -o IdentitiesOnly=yes -o BatchMode=yes -o UserKnownHostsFile=$K/known_hosts \
     -o StrictHostKeyChecking=yes -o ConnectTimeout=10 root@$FW export > "$fwout" 2>/dev/null && grep -q '^<opnsense>' "$fwout"; then
  cp "$fwout" firewall/config-export.xml; git add firewall/config-export.xml
  fexp=/mnt/data/system/device-configs-expected/firewall.xml
  if [ -s "$fexp" ]; then diff "$fexp" "$fwout" > "$state/firewall-drift.diff" || true
    grep -c '^[<>]' "$state/firewall-drift.diff" > "$state/firewall-drift.lines" || true
  else echo -1 > "$state/firewall-drift.lines"; fi
  log "firewall drift: $(cat "$state/firewall-drift.lines") lines differ from the repository"
else echo -2 > "$state/firewall-drift.lines"; log "FAIL: firewall export not received (drift unknown)"; fi
cp "$out" router/config-export.txt
exp=/mnt/data/system/device-configs-expected/router.normal
if [ -s "$exp" ]; then
  sed -n '/^### uci export/,/^### /p' "$out" | sed '1d;$d' | awk -f /mnt/data/system/seed-bin/uci-normal.awk \
    | sort -s -t "$(printf '\t')" -k1,1 | diff "$exp" - > "$state/router-drift.diff" || true
  grep -c '^[<>]' "$state/router-drift.diff" > "$state/router-drift.lines" || true
else echo -1 > "$state/router-drift.lines"; fi
log "router drift: $(cat "$state/router-drift.lines") lines differ from the repository"
cp /boot/config/plugins/dynamix.apcupsd/dynamix.apcupsd.cfg ups/dynamix.apcupsd.cfg   # the UI's settings (flash)
cp /etc/apcupsd/apcupsd.conf ups/apcupsd.conf                                         # rendered from them at boot
git add router/config-export.txt ups/dynamix.apcupsd.cfg ups/apcupsd.conf
if git diff --cached --quiet; then log "no change"
else
  git -c user.name="seed device-config (infra)" -c user.email=device-config@seed.example.com \
    commit -q -m "device configs $(date -u +%FT%TZ): $(git diff --cached --name-only | tr '\n' ' ')"
  git push -q origin HEAD:main; log "committed and pushed $(git rev-parse --short HEAD)"
fi
date +%s > "$state/device-config.last"
