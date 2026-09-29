#!/bin/bash
# One-time admin steps that make compute the site's laptop. The seed user is not an admin, so a
# person with an admin account runs this ONCE with sudo, after reading it:
#   sudo bash /Users/seed/.local/share/seed/laptop/admin-setup.sh
# and compares `shasum -a 256` of the file with the one in the diary or the repo first.
# It changes exactly four things, each reversible (the last lines print how):
#   1. /etc/hosts: a marked block with the site's names (site/bin/render-laptop-hosts), so the
#      laptop resolves the site with both DNS servers down. The rest of the file is left as it is.
#   2. DNS servers of the wired service: core, infra, then Quad9 as external fallbacks, so the
#      internet resolves with core, infra or both down (the site's names come from the block).
#   3. The flow-2 backup as a LaunchDaemon running AS seed (not root), so it runs after a reboot
#      without seed logging in; the interim user-domain job is removed.
#   4. /etc/sudoers.d/seed: seed may flush the DNS cache and start its own backup job, nothing else.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
SRC=/Users/seed/.local/share/seed/laptop; SVC="USB 10/100/1G/2.5G LAN"; ZONE=seed.example.com
stamp=$(date +%Y%m%d%H%M%S)
for f in hosts.block co.oznog.seed.backup.daemon.plist; do [ -s "$SRC/$f" ] || { echo "missing $SRC/$f"; exit 1; }; done
grep -q "^# BEGIN $ZONE" "$SRC/hosts.block" && grep -q "^# END $ZONE" "$SRC/hosts.block" || { echo "hosts.block malformed"; exit 1; }

# 1. hosts
cp -p /etc/hosts /etc/hosts.before-seed-$stamp
awk -v b="# BEGIN $ZONE" -v e="# END $ZONE" 'index($0,b)==1{skip=1} !skip{print} index($0,e)==1{skip=0}' /etc/hosts > /etc/hosts.new
cat "$SRC/hosts.block" >> /etc/hosts.new
chown root:wheel /etc/hosts.new; chmod 644 /etc/hosts.new; mv /etc/hosts.new /etc/hosts
echo "1. /etc/hosts: block installed (previous file: /etc/hosts.before-seed-$stamp)"

# 2. DNS servers of the wired service
echo "2. DNS servers of '$SVC' before: $(networksetup -getdnsservers "$SVC" | tr '\n' ' ')"
networksetup -setdnsservers "$SVC" 192.168.1.15 192.168.1.16 9.9.9.9 149.112.112.112   # Technitium ns1, ns2 (rung 5 › F)
echo "   after: $(networksetup -getdnsservers "$SVC" | tr '\n' ' ')"

# 3. the backup as a daemon running as seed
launchctl bootout user/502/co.oznog.seed.backup 2>/dev/null || true
install -o root -g wheel -m 644 "$SRC/co.oznog.seed.backup.daemon.plist" /Library/LaunchDaemons/co.oznog.seed.backup.plist
launchctl bootout system/co.oznog.seed.backup 2>/dev/null || true
launchctl bootstrap system /Library/LaunchDaemons/co.oznog.seed.backup.plist
echo "3. backup job: $(launchctl print system/co.oznog.seed.backup | awk '/^\tstate/{print}')"

# 4. named sudo for seed
cat > /etc/sudoers.d/seed.new <<'EOF'
# the seed user on compute (site/laptop/admin-setup.sh): flush the DNS cache, start its own backup
seed ALL=(root) NOPASSWD: /usr/bin/dscacheutil -flushcache, /usr/bin/killall -HUP mDNSResponder, /bin/launchctl kickstart system/co.oznog.seed.backup
EOF
chmod 440 /etc/sudoers.d/seed.new
visudo -cf /etc/sudoers.d/seed.new && mv /etc/sudoers.d/seed.new /etc/sudoers.d/seed
echo "4. /etc/sudoers.d/seed installed"

dscacheutil -flushcache; killall -HUP mDNSResponder
echo "done. To undo: cp /etc/hosts.before-seed-$stamp /etc/hosts; networksetup -setdnsservers \"$SVC\" 192.168.1.1;"
echo "  launchctl bootout system/co.oznog.seed.backup; rm /Library/LaunchDaemons/co.oznog.seed.backup.plist /etc/sudoers.d/seed"
