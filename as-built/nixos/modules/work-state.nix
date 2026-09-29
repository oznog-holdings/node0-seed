# /work survives every rebuild, and so does the agent's state that must outlive the OS
# (design › Development: "the dev volume is not the OS. The OS is disposable and comes back from
# the repo. /work is a separate XFS volume ... so it survives every rebuild"; R2.06; finding
# F-REBUILD-STATE, 20260924).
#  - /work is made ONCE by hand (runbooks/rebuild-agent-box.md) and never by disko (disko.nix
#    creates the partition only). Its mount is declared here, the same as disko generated it.
#  - The guard: /work's filesystem UUID is pinned below. If the mounted /work isn't that
#    filesystem (reformatted, replaced), seed-work-guard fails, and the state mounts and the /work
#    backup refuse to start: nothing binds or backs up an empty /work as if it were the real one.
#    The metric seed_work_guard_ok feeds the alert AgentWorkGuard (monitoring/rules/agent.yml).
#  - The agent's tool state lives on /work and is bind-mounted into its home: the person's
#    Claude Code and Codex logins and the tools' own state, the builder's ssh key and its vault
#    login. So a rebuild needs no new logins and no re-keying; flow 2 backs them up (encrypted).
#  - ~/.claude.json is a file the tool replaces by rename (it can't be bind-mounted); Claude Code
#    keeps a copy of it in ~/.claude/backups on every write. After a rebuild it is restored from the
#    newest one if missing.
{ config, lib, pkgs, ... }:
let
  workUuid = "YOUR-WORK-VOLUME-UUID";   # mkfs.xfs of 20260924 02:07 (lsblk, 20260924)
  home = "/home/agent"; state = "/work/agent/.state";
  textfile = "/var/lib/prometheus-node-exporter-text";
  guarded = [ "x-systemd.requires=seed-work-guard.service" "x-systemd.after=seed-work-guard.service" ];
  bind = src: { device = "${state}/${src}"; fsType = "none"; options = [ "bind" "nofail" ] ++ guarded; depends = [ "/work" ]; };
in {
  # the same mount disko generated (by partlabel, xfs, noatime): the unit does not change
  fileSystems."/work" = { device = "/dev/disk/by-partlabel/disk-main-work"; fsType = "xfs"; options = [ "noatime" ]; };

  systemd.services.seed-work-guard = {
    description = "Refuse a /work that isn't the pinned filesystem";
    unitConfig = { DefaultDependencies = false; RequiresMountsFor = [ "/work" ]; };
    before = [ "local-fs.target" ];
    wantedBy = [ "local-fs.target" ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    path = [ pkgs.util-linux pkgs.coreutils ];
    script = ''
      u=$(findmnt -n -o UUID /work || true)
      mkdir -p ${textfile}
      ok=0; [ "$u" = "${workUuid}" ] && ok=1
      printf '# HELP seed_work_guard_ok 1 if /work is the pinned filesystem.\n# TYPE seed_work_guard_ok gauge\nseed_work_guard_ok %s\n' $ok > ${textfile}/work-guard.prom.tmp
      mv ${textfile}/work-guard.prom.tmp ${textfile}/work-guard.prom
      if [ $ok = 1 ]; then echo "/work is ${workUuid}"; exit 0; fi
      echo "REFUSED: /work is '$u', not the pinned ${workUuid}: state mounts and the /work backup will not start" >&2
      exit 1
    '';
  };

  fileSystems."${home}/.claude" = bind "claude";
  fileSystems."${home}/.codex" = bind "codex";
  fileSystems."${home}/.ssh" = bind "ssh";
  fileSystems."${home}/.config/seed" = bind "config-seed";
  systemd.tmpfiles.rules = [
    "d ${state} 0700 agent agent -"
    "d ${home}/.config 0700 agent agent -"
    "d ${home}/.config/seed 0700 agent agent -"
    "d ${home}/.ssh 0700 agent agent -"
    # the Bitwarden CLI (the hosted vault) keeps its login in ~/.config/Bitwarden CLI, which was on
    # root and lost at the rebuild of 20260927 (F-REBUILD-BW): it lives under ~/.config/seed now
    # (bind-mounted from /work), like the site vault's bw-local
    "L \"${home}/.config/Bitwarden CLI\" - - - - ${home}/.config/seed/bw-hosted"
  ];

  # ~/.claude.json back from Claude Code's own newest backup, if a rebuild left it missing
  systemd.services.seed-agent-claude-json = {
    description = "Restore the agent's ~/.claude.json from Claude Code's newest backup if missing";
    wantedBy = [ "multi-user.target" ];
    unitConfig.RequiresMountsFor = [ "${home}/.claude" ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; User = "agent"; Group = "agent"; };
    script = ''
      f=${home}/.claude.json
      [ -e "$f" ] && exit 0
      b=$(ls -1t ${home}/.claude/backups/.claude.json.backup.* 2>/dev/null | head -1)
      [ -n "$b" ] || { echo "no backup to restore ~/.claude.json from"; exit 0; }
      umask 077; cp "$b" "$f.new" && mv "$f.new" "$f" && echo "restored ~/.claude.json from $b"
    '';
  };

  # the /work backup only runs on the pinned /work
  systemd.services.restic-backups-work = { requires = [ "seed-work-guard.service" ]; after = [ "seed-work-guard.service" ]; };
}
