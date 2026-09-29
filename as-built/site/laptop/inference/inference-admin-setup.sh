#!/bin/bash
# One-time admin step for rung 4 on compute: the inference supervisor as a LaunchDaemon running AS
# seed, so the model backend comes back after a reboot without seed logging in. Run ONCE with sudo
# by a person with an admin account, after reading it and comparing `shasum -a 256` with the diary:
#   sudo bash /Users/seed/.local/share/seed/laptop/inference/inference-admin-setup.sh
# It changes exactly two things, each reversible (the last lines print how):
#   1. /Library/LaunchDaemons/co.oznog.seed.inference.plist (runs supervise.sh as seed, Nice 5);
#   2. /etc/sudoers.d/seed-inference: seed may restart that one job, nothing else.
# The interim copy of the supervisor (started with nohup) is stopped first, so only one runs.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
SRC=/Users/seed/.local/share/seed/laptop/inference; P=co.oznog.seed.inference
[ -s "$SRC/$P.daemon.plist" ] && [ -x "$SRC/supervise.sh" ] || { echo "missing files in $SRC"; exit 1; }
plutil -lint "$SRC/$P.daemon.plist" >/dev/null
pkill -TERM -u seed -f "inference/supervise.sh" && sleep 5 || true
install -o root -g wheel -m 644 "$SRC/$P.daemon.plist" /Library/LaunchDaemons/$P.plist
launchctl bootstrap system /Library/LaunchDaemons/$P.plist
echo "1. LaunchDaemon $P loaded: $(launchctl print system/$P | awk '/state =/{print $3; exit}')"
printf 'seed ALL=(root) NOPASSWD: /bin/launchctl kickstart -k system/%s\n' "$P" > /etc/sudoers.d/seed-inference.new
chmod 440 /etc/sudoers.d/seed-inference.new; visudo -cf /etc/sudoers.d/seed-inference.new >/dev/null
mv /etc/sudoers.d/seed-inference.new /etc/sudoers.d/seed-inference
echo "2. /etc/sudoers.d/seed-inference: seed may restart $P"
echo "Undo:  launchctl bootout system/$P; rm /Library/LaunchDaemons/$P.plist /etc/sudoers.d/seed-inference"
echo "Pause: sudo -u seed touch /Users/seed/.local/state/seed/inference/held   (resume: remove it)"
