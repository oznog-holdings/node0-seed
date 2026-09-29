# Rebuilding the agent box without touching /work (R2.06)

design › Operating: "rebuild one machine on purpose, and make it the agent box, because a
restore procedure that has never run is a guess"; Development: "/work is a separate XFS volume
... so it survives every rebuild and never needs restoring". This runbook formats **boot and
root only**. It never runs disko's destroy or format modes on this disk: disko.nix no longer
gives /work a filesystem (F-REBUILD-STATE), but the partition table stays as it is too.

**Who:** the orchestrator (root, physical or kexec access), scheduled with the person. The
builder is off the box for the whole rebuild (it runs there). **Time it**: note the clock at
steps 0, 3, 8 and 10.

What comes back, and from where:

| what | from |
|---|---|
| the OS, every service, users, keys allowed in | the forge's `deploy` ref (`nixos/`) |
| ssh host key (and so the sops identity) | infra `/mnt/data/system/identity/agent-20260927.tar` |
| Tailscale's node identity, the forge deploy key | infra `/mnt/data/system/identity/agent-extra-20260924.tgz` |
| the agent's tool logins and state, ssh key, vault login | `/work/agent/.state` (bind mounts, `modules/work-state.nix`) |
| `~/.claude.json` | Claude Code's newest copy in `~/.claude/backups` (service `seed-agent-claude-json`) |
| everything under /work | /work itself (not formatted); flow 2 has a copy on infra |

Lost and accepted: the journal, metrics and timer stamps under `/var/lib` (the next runs rebuild
them; timers with `Persistent=true` fire at once), the builder's shell history, caches.

## 0. Before (with the box still up)

1. A fresh flow-2 snapshot of /work: `sudo systemctl start restic-backups-work.service`; note the
   snapshot id (`seed_backup_last_snapshot_timestamp_seconds{repo="rest-agent"}` moves).
2. Record, as the guard's inputs: `findmnt -n -o UUID /work` (must be the pinned
   `YOUR-WORK-VOLUME-UUID`, `nixos/modules/work-state.nix`), and
   `find /work -xdev | wc -l`.
3. On infra: `sha256sum /mnt/data/system/identity/agent-20260927.tar agent-extra-20260924.tgz` and
   `tar tf` both (expect `etc/ssh/ssh_host_ed25519_key*`; `var/lib/tailscale/...`,
   `var/lib/seed-deploy/deploy_key`). The host key's fingerprint:
   `ssh-keygen -lf` of the `.pub` inside, equal to `ssh-keygen -F 192.168.1.11` on the laptop.
4. Pause the external dead-man only if infra goes down too (it doesn't here). The watcher will
   stop while the agent box is off; the owner may see `AgentWatcherStale` (expected).

## 1 to 2. Boot the installer, then the first guard

5. Boot the keyed installer (`nixosConfigurations.installer`, USB) or kexec into it from the box.
   **It may come up on either Ethernet port** (at 20260927 it took the second port, MAC ending xx:xx, and
   8 minutes went on watching the other MAC). Find its lease by hostname, not by MAC:
   `grep seed-installer /tmp/dhcp.leases` on the router.
6. **Guard 1 (before any format):**
   `[ "$(lsblk -no UUID /dev/disk/by-partlabel/disk-main-work)" = YOUR-WORK-VOLUME-UUID ] || echo STOP`.
   On STOP: nothing is formatted; find out why before going on.

## 3. Format boot and root only

7. `mkfs.vfat -F 32 -n BOOT /dev/disk/by-partlabel/disk-main-ESP`
   `mkfs.ext4 -F -L nixos /dev/disk/by-partlabel/disk-main-root`
   **Never** `disk-main-work`, never `disko`, never `wipefs` or `sgdisk` on this disk.

## 4 to 5. Mount, then the second guard

8. `mount /dev/disk/by-partlabel/disk-main-root /mnt; mkdir -p /mnt/boot /mnt/work`
   `mount -o umask=0077 /dev/disk/by-partlabel/disk-main-ESP /mnt/boot`
   `mount -o noatime /dev/disk/by-partlabel/disk-main-work /mnt/work`
9. **Guard 2:** `findmnt -n -o UUID /mnt/work` is the pinned UUID, and `find /mnt/work -xdev | wc -l`
   is the count from step 0 (± the files written since). Else STOP and unmount.

## 6. Restore the identity before first boot

10. From infra (the installer has the orchestrator's key there):
    `ssh root@192.168.1.10 cat /mnt/data/system/identity/agent-20260927.tar | tar -x -C /mnt -p`
    `ssh root@192.168.1.10 cat /mnt/data/system/identity/agent-extra-20260924.tgz | tar -xz -C /mnt -p`
    Check: `stat -c '%a %U' /mnt/etc/ssh/ssh_host_ed25519_key /mnt/var/lib/seed-deploy/deploy_key`
    → `600 root` for both; the host key's fingerprint = step 3's.
    Check: `stat -c '%a %U' /mnt/etc /mnt/etc/ssh` → `755 root` for both, and
    `find /mnt/etc /mnt/var/lib/tailscale /mnt/var/lib/seed-deploy ! -uid 0` prints nothing. **STOP on
    anything else:** a /etc/ssh at 0700 breaks every non-root ssh login. (The tarball of 20260924 was
    made as uid 1001 with /etc/ssh 0700, fixed by hand at 20260927; agent-20260927.tar is made as root
    with `--numeric-owner`: F-REBUILD-IDENTITY.)

## 7. Install from the forge

11. `nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#git -c git clone --branch deploy
    ssh://git@git.seed.example.com:2222/seed/seed-lab.git /tmp/seed-lab` with
    `GIT_SSH_COMMAND="ssh -i /mnt/var/lib/seed-deploy/deploy_key -o IdentitiesOnly=yes"` (host key: `nixos/forge-hostkey.pub`).
12. `nixos-install --flake /tmp/seed-lab/nixos#agent --no-root-passwd`
13. `umount -R /mnt; reboot` (remove the stick if one was used).

## 8 to 10. After the first boot (the builder, back on the box, or the orchestrator)

- **The builder's vault login survives** from 20260927: the hosted Bitwarden CLI's data is in
  `~/.config/seed/bw-hosted` (on /work), linked from `~/.config/Bitwarden CLI` by tmpfiles. Check:
  `readlink ~agent/.config/Bitwarden\ CLI` and `bw status` (as agent: `locked`, not
  `unauthenticated`). If it says unauthenticated: `set -a; . ~/.config/seed/bw.env; set +a;
  bw login --apikey` (F-REBUILD-BW).
- **node_exporter** waits for network-online and retries every 5 s (F-REBUILD-EXPORTER). Check:
  `systemctl is-active prometheus-node-exporter` → active, without starting it by hand.

14. From the laptop, strictly: `ssh -o StrictHostKeyChecking=yes agent@192.168.1.11 true` (the
    host key is the old one).
15. `systemctl is-active seed-work-guard`; `findmnt /home/agent/.claude /home/agent/.codex
    /home/agent/.ssh /home/agent/.config/seed` (four bind mounts from /work/agent/.state);
    `systemctl status seed-agent-tool-config seed-agent-claude-json` (settings merged; claude.json
    restored if it was missing).
16. The logins, without the person: `claude -p 'Reply with the single word ok.' --max-turns 1`
    and `codex login status` as `agent`; `claude mcp list` shows no account connectors.
17. `tailscale status --self` shows the same node and address (100.64.0.11) and the route still
    primary (no re-approval); `sudo systemctl start seed-deploy.service` succeeds from the forge.
18. `sudo systemctl start restic-backups-work.service` succeeds on the same repository;
    `site/bin/check-after-reboot` from the box; Prometheus target `192.168.1.11:9100` up; the
    watcher runs.
19. Record in the diary: the times of steps 0, 3, 8 and 10, every check's output, anything that
    needed hands.

## First install on a blank disk (for the record)

disko creates the partitions and formats BOOT and root; it leaves `disk-main-work` without a
filesystem. Make it once: `mkfs.xfs -L work -m reflink=1 /dev/disk/by-partlabel/disk-main-work`,
then pin its UUID in `modules/work-state.nix` (a commit and a promotion) before the first boot.
