#!/bin/sh
# root-reboot-agent-box.sh: reboot the agent box, as root, after the owner's (or his stand-in's) approval. A root step
# by design (the orchestrator, 20261006): the builder prepares, root reboots, so "approved" and "done" stay in the
# same hands; the builder has no right to reboot this box (no sudo rule, polkit refuses it).
# Before it, the builder has: asked in STATUS and had it approved (worst case, cost, way back); written STATUS
# "rebooting at <time>; resume by <who>" with its resume command; paused hc tender-claude-work; stopped
# tender-claude-tick.timer and exited Claude (herdr lists no agent); pushed everything; left nothing of its own running.
# After it, the box comes back by itself (boot counting falls back to the last blessed entry if the new one fails).
# Then: resume the builder in its pane with the command in STATUS; it checks the boot was blessed, the agents, the
# heartbeats, and records the reboot.
set -eu
T=/home/tender; U=$(id -u tender)
as_tender() { sudo -u tender XDG_RUNTIME_DIR=/run/user/$U HOME=$T env PATH=$T/.local/bin:/run/current-system/sw/bin "$@"; }
echo "== preconditions (nothing done if one fails)"
agents=$(as_tender herdr agent list) || { echo "herdr agent list failed: stop"; exit 1; }
names=$(printf '%s' "$agents" | jq -r '.result.agents[] | .name') || { echo "herdr's answer didn't parse: stop"; exit 1; }
[ -z "$names" ] || { echo "an agent is running ($names): exit it first (herdr agent prompt claude /exit): stop"; exit 1; }
! as_tender systemctl --user is-active -q tender-claude-tick.timer || { echo "Claude's tick timer is active: stop"; exit 1; }
grep -qi 'rebooting at' /work/agent/STATUS.md || { echo "the builder's STATUS doesn't say 'rebooting at': stop"; exit 1; }
echo "   kernel: running $(uname -r), installed $(readlink /run/current-system/kernel | grep -o 'linux-[0-9.]*')"
echo "   failed units: $(systemctl --failed --no-legend | wc -l)"
echo "== rebooting at $(date -u +%FT%TZ)"
systemctl reboot
