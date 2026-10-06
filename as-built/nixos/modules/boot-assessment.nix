# A bad deploy heals itself without hands, on a box that may only ever be warm-reset (R2.08; the owner,
# 20260927). Three layers:
#  1. Boot counting (systemd's Automatic Boot Assessment). A new generation gets 3 tries. It is marked
#     good only by seed-boot-check, which proves what matters: 192.168.1.11 up, sshd answering, the
#     forge reachable, /work mounted by its guard. A generation that never passes falls back to the
#     last good one by itself.
#  2. The rescue entry (rescue.nix): fixed, RAM-booted, independent of every deploy.
#  3. The hardware watchdog (hosts/agent: RuntimeWatchdogSec 30 s, RebootWatchdogSec 5 min), with
#     panic=30, boot.panic_on_fail and no emergency mode, so a hung boot becomes a warm reset and a
#     counted try.
#
# How, from the sources (nixpkgs 1bc55b9def81, systemd 260.4; site/runbooks/rescue-boot.md cites lines):
#  - NixOS's systemd-boot module has no boot-counting option in this nixpkgs. Its builder names every
#    entry nixos-generation-N.conf and rewrites them all on every install (systemd-boot-builder.py
#    95-103, 206), and runs extraInstallCommands afterwards (systemd-boot.nix 104-107). Its cleanup regex
#    `^nixos.*-generation-([0-9]+)(-specialisation-.*)?\.conf$` (257-279) skips counted names, so
#    this module cleans those up itself.
#  - The counter lives in the entry's file name: NAME+LEFT[-DONE].conf. The loader renames it at every
#    try and strips it for the entry's id (boot.c 1245-1289). Entries with 0 tries left sort to the end
#    (1769).
#  - loader.conf `preferred` is matched with the assessment (a 0-tries entry is skipped; boot.c 1121-1127,
#    1893). `default` is matched without it (1113-1119, ~1920), and NixOS writes only `default`. So this
#    module writes preferred = NixOS's chosen entry, and default = the last entry actually booted and
#    blessed: seed-boot-blessed records it in /boot/loader/seed-blessed when systemd-bless-boot has marked
#    this boot good (tested 20260928: "the newest plain entry" picked generation 3, plain only because it
#    predated counting, never proven).
#  - systemd-bless-boot.service and boot-complete.target ship with NixOS's systemd (systemd.nix 112, 119).
#    The generator enables blessing only when the booted entry is counted (LoaderBootCountPath).
{ config, lib, pkgs, ... }:
let
  tries = 3;
  armCounting = pkgs.writeShellScript "seed-arm-boot-counting" ''
    # runs after NixOS's systemd-boot builder, as root, at every boot-loader install (a switch)
    set -euo pipefail
    PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.gnused pkgs.gnugrep pkgs.findutils pkgs.gawk ]}
    B=''${SEED_BOOT_ROOT:-/boot}   # overridable only for the test (tools/test-boot-counting.sh)
    E=$B/loader/entries; L=$B/loader/loader.conf; A=$B/loader/seed-armed
    touch $A
    chosen=$(sed -n 's/^default //p' $L)            # NixOS's choice: nixos-generation-M.conf
    # The builder has just rewritten a plain entry for every generation it lists (the newest
    # configurationLimit). So a counted entry with a plain twin wins over the twin; a counted entry
    # without one is outside the builder's list (deleted, or past the limit) and goes, since the
    # builder's own cleanup doesn't see counted names.
    for f in $E/nixos-generation-*+*.conf; do
      [ -e "$f" ] || continue
      b=''${f##*/}; id=''${b%%+*}
      if [ -e "$E/$id.conf" ]; then rm -f "$E/$id.conf"; else rm -f "$f"; echo "boot counting: removed $b (no longer listed by the builder)"; fi
    done
    # arm NixOS's chosen entry once: ${toString tries} tries. Armed and now plain means it was blessed (good).
    if [ -n "$chosen" ] && [ -e "$E/$chosen" ] && ! grep -qxF "$chosen" $A; then
      mv "$E/$chosen" "$E/''${chosen%.conf}+${toString tries}.conf"; echo "$chosen" >> $A
      echo "boot counting: ''${chosen%.conf} armed with ${toString tries} tries"
    fi
    # preferred: NixOS's choice, while it has tries left. default: the newest generation recorded as
    # blessed (seed-boot-blessed) whose entry is still there, and plain
    R=$B/loader/seed-blessed; touch $R
    if [ ! -s $R ]; then   # once, for boots blessed before the record existed: armed, now plain = blessed
      while read -r id; do if [ -e "$E/$id" ]; then echo "$id 0 (armed, then plain: blessed before the record)"; fi; done < $A >> $R
    fi
    # a blessed generation whose entry the builder has since removed (garbage-collected, past the limit) can't
    # be booted: drop it from the record. (Written as `[ -e ] && echo` in a loop this died under pipefail when
    # the last id tested was gone, and failed every switch from 20260930 11:00Z; the orchestrator's incident.)
    gone=$(cut -d' ' -f1 $R | sort -u | while read -r id; do if [ ! -e "$E/$id" ] && ! compgen -G "$E/''${id%.conf}+*.conf" >/dev/null; then echo "$id"; fi; done)
    if [ -n "$gone" ]; then
      awk -v g="$(printf '%s ' $gone)" 'BEGIN{n=split(g,a," "); for(i=1;i<=n;i++) d[a[i]]=1} !($1 in d)' $R > $R.tmp
      mv $R.tmp $R; echo "boot counting: dropped from the blessed record (entries gone): "$gone
    fi
    good=$(cut -d' ' -f1 $R | sort -u | while read -r id; do if [ -e "$E/$id" ]; then echo "$id"; fi; done \
      | sed 's/^nixos-generation-\([0-9]*\)\.conf$/\1 &/' | sort -n | tail -1 | cut -d' ' -f2)
    if [ -z "$good" ]; then   # nothing proven yet (a new box): the newest plain entry, said so
      good=$(find $E -maxdepth 1 -name 'nixos-generation-*.conf' ! -name '*+*' -printf '%f\n' | sed 's/^nixos-generation-\([0-9]*\)\.conf$/\1 &/' | sort -n | tail -1 | cut -d' ' -f2)
      echo "boot counting: no blessed entry recorded; default = the newest plain entry, unproven"
    fi
    sed -i '/^default /d; /^preferred /d' $L
    [ -n "$chosen" ] && echo "preferred $chosen" >> $L
    [ -n "$good" ] && echo "default $good" >> $L
    echo "boot counting: preferred $chosen, default (last good) ''${good:-none}"
  '';
  check = pkgs.writeShellScript "seed-boot-check" ''
    # proves what matters, for up to 5 minutes; while this boot is being counted, a failure reboots (a
    # used try); on a counted-good boot a failure only fails this unit (the monitoring sees it)
    PATH=${lib.makeBinPath [ pkgs.bash pkgs.coreutils pkgs.iproute2 pkgs.util-linux pkgs.systemd pkgs.gnugrep ]}   # bash: banner() runs it (without it the first live run failed, 20260928)
    counting=0; ls /sys/firmware/efi/efivars/LoaderBootCountPath-* >/dev/null 2>&1 && counting=1
    banner() { timeout 5 bash -c "exec 3<>/dev/tcp/$1/$2; head -c 7 <&3" 2>/dev/null; }
    ok() {
      ip -4 -o addr show | grep -q ' 192\.168\.1\.11/24 ' || { why="192.168.1.11 not up"; return 1; }
      [ "$(banner 192.168.1.11 22)" = SSH-2.0 ] || { why="sshd not answering on 192.168.1.11:22"; return 1; }
      [ "$(banner 192.168.1.10 2222)" = SSH-2.0 ] || { why="the forge (192.168.1.10:2222) not reachable"; return 1; }
      systemctl is-active -q seed-work-guard && [ "$(findmnt -n -o UUID /work)" = YOUR-WORK-VOLUME-UUID ] \
        || { why="/work not mounted by its guard"; return 1; }
    }
    for i in $(seq 1 60); do
      if ok; then echo "boot check: all good (network, sshd, forge, /work)$([ $counting = 1 ] && echo '; this generation will be marked good')"; exit 0; fi
      sleep 5
    done
    echo "boot check FAILED after 5 min: $why"
    if [ $counting = 1 ]; then echo "this boot is being counted: rebooting (a used try)"; systemctl reboot; fi
    exit 1
  '';
in {
  boot.loader.systemd-boot.extraInstallCommands = "${armCounting}";
  system.build.seedArmBootCounting = armCounting;   # for tools/test-boot-counting.sh

  # the post-boot check that marks a generation good (boot-complete.target gates systemd-bless-boot)
  systemd.services.seed-boot-check = {
    description = "Prove the network, sshd, the forge and /work before this generation is marked good";
    wantedBy = [ "boot-complete.target" ];
    requiredBy = [ "boot-complete.target" ];
    before = [ "boot-complete.target" ];
    after = [ "network-online.target" "sshd.service" "seed-work-guard.service" ];
    wants = [ "network-online.target" ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; ExecStart = check; TimeoutStartSec = "7min"; };
  };
  systemd.targets.boot-complete.wantedBy = [ "multi-user.target" ];
  # the last good generation, recorded when systemd-bless-boot has marked this boot good ("good" from its
  # status only on the boot that did it; "clean" on a boot of an already good entry): the loader's
  # LoaderEntrySelected is the booted entry's id, without the counter
  systemd.services.seed-boot-blessed = {
    description = "Record the generation systemd-bless-boot marked good (the last good for the boot loader)";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-bless-boot.service" "boot-complete.target" ];
    unitConfig.RequiresMountsFor = [ "/boot" ];
    serviceConfig.Type = "oneshot";
    path = [ pkgs.coreutils pkgs.gnugrep ];
    script = ''
      st=$(${config.systemd.package}/lib/systemd/systemd-bless-boot status 2>/dev/null || true)
      [ "$st" = good ] || { echo "not blessed on this boot (status: ''${st:-none})"; exit 0; }
      id=$(tail -c +5 /sys/firmware/efi/efivars/LoaderEntrySelected-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f | tr -d '\000')
      case $id in nixos-generation-*.conf) ;; *) echo "blessed, but the booted entry is '$id': not recorded"; exit 0 ;; esac
      grep -q "^$id " /boot/loader/seed-blessed 2>/dev/null || echo "$id $(date +%s)" >> /boot/loader/seed-blessed
      echo "blessed and recorded as the last good: $id"
    '';
  };
  # the deadline: a counted boot that hasn't reached boot-complete within 15 minutes reboots (a used try),
  # whatever held the check up
  systemd.timers.seed-boot-deadline = { wantedBy = [ "timers.target" ]; timerConfig.OnBootSec = "15min"; };
  systemd.services.seed-boot-deadline = {
    description = "Reboot a counted boot that never reached boot-complete";
    serviceConfig.Type = "oneshot";
    path = [ pkgs.systemd pkgs.coreutils ];
    script = ''
      ls /sys/firmware/efi/efivars/LoaderBootCountPath-* >/dev/null 2>&1 || exit 0
      systemctl is-active -q boot-complete.target && exit 0
      echo "counted boot without boot-complete after 15 min: rebooting (a used try)"; systemctl reboot
    '';
  };

  # a hung boot must end in a reset: no emergency shell (it would keep systemd, and the watchdog, alive),
  # and a stage-1 failure panics (stage-1-init.sh: without it, fail() waits for a key) into panic=30
  systemd.enableEmergencyMode = false;
  boot.kernelParams = [ "boot.panic_on_fail" ];
}
