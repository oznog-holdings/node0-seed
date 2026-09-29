#!/usr/bin/env bash
# The router's own backup (`sysupgrade -b`), the way back for any router change (rung 5 brief › A).
# The archive holds /etc/config in full (the wifi passphrases, and the lab's WAN and fixture
# sections), /etc/shadow and dropbear's host keys, so it never exists in the clear off the router:
# router stdout -> age (armoured) -> site/router/backup/<UTC stamp>.tar.gz.age, to the recipients of
# .sops.yaml (the master key from the vault item "sops master age key", the agent box's host key,
# compute's key). Only file names are listed from it here (a decrypt needs the master key).
# Restore (on the router, from a decrypted copy): `sysupgrade -r <file>`, then `reboot`.
# Usage: tools/router-backup.sh   -> prints the file written and its sha256
set -euo pipefail
cd "$(dirname "$0")/.."
R="ssh -o BatchMode=yes -o LogLevel=ERROR root@${ROUTER:-192.168.1.4}"   # the router: the access point at .4 from rung 6
rcp=$(awk '/^  - &(master|agent) age1/{printf " -r %s", $3} /^  - &laptop_[a-z0-9]+ age1/{printf " -r %s", $3} /^  - &laptop_[a-z0-9]+ ssh-ed25519 /{printf " -r \"%s %s\"", $3, $4}' .sops.yaml)
[[ $(grep -o -- ' -r ' <<<"$rcp" | wc -l) -eq 3 ]] || { echo "recipient lookup failed (want 3)" >&2; exit 1; }
mkdir -p site/router/backup
out=site/router/backup/$(date -u +%Y%m%dT%H%M%SZ).tar.gz.age
# the archive's size and hash are taken on the router side of the pipe, before encryption
$R 'f=/tmp/seed-router-backup.tar.gz; umask 077; sysupgrade -b $f >/dev/null 2>&1 && echo "#size $(wc -c <$f) sha256 $(sha256sum $f | cut -d" " -f1)" >&2 && tar tzf $f | sed "s/^/#file /" >&2 && cat $f; rm -f $f' \
  2> >(grep '^#' > "$out.meta") | nix-shell -p age --run "age -a$rcp -o $out.tmp"
sleep 1
grep -q '^#size [1-9]' "$out.meta" && grep -q '^#file etc/config/network$' "$out.meta" \
  || { echo "backup incomplete; nothing kept" >&2; rm -f "$out.tmp" "$out.meta"; exit 1; }
mv "$out.tmp" "$out"
{ echo "# $(basename "$out"): sysupgrade -b of the router, $(date -u +%FT%TZ); archive (before encryption):"
  sed 's/^#//' "$out.meta"; } > "${out%.tar.gz.age}.txt"; rm -f "$out.meta"
echo "$out $(sha256sum "$out" | cut -d' ' -f1)"; head -2 "${out%.tar.gz.age}.txt" | tail -1
