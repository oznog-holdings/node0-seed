#!/bin/bash
# infra's sshd on its tailnet address too (rung 5 › E: site2 pulls from infra over the tailnet and never
# accepts routes). Unraid lists tailscale1 in its listening interfaces (/boot/config/network-extra.cfg:
# include_interfaces="tailscale1") and runs its own `rc.sshd update` when interfaces change. But at boot the
# Tailscale plugin takes tailscale1 away and back while it installs, and Unraid's update can land in the
# gap and bind br0 only. Seen 20260929 after the power-off test: this script bound tailscale1 at 09:30:31Z,
# and Unraid's own update at 09:30:39Z dropped it again.
# So this is an idempotent check, every 5 minutes (User Scripts, */5): nothing to do if tailscale1 has no
# address yet or sshd already listens on it; otherwise Unraid's `rc.sshd update` (restarts only the listener).
ts=$(ip -4 -o addr show dev tailscale1 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
[ -n "$ts" ] || { echo "tailscale1 has no address yet"; exit 0; }
ss -lnt | grep -q " $ts:22 " && exit 0
echo "$(date -u +%FT%TZ) sshd not on $ts:22: rc.sshd update"
/etc/rc.d/rc.sshd update
sleep 2
ss -lnt | grep -q " $ts:22 " && echo "sshd listens on $ts:22" || { echo "sshd does NOT listen on $ts:22"; exit 1; }
