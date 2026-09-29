# The agent box heals a bad deploy by itself (R2.08): tests

Built and deployed 20260928 without a reboot (PRs #25-#27). The reboots are the orchestrator's, from
the operator's laptop, as root on the agent box (`ssh root@192.168.1.11`: root has the orchestrator's key only). Send back
every command's output.

## What is on the box

| layer | what | where |
|---|---|---|
| boot counting | the generation NixOS chooses gets **3 tries** (`nixos-generation-N+3.conf`). `seed-boot-check` proves 192.168.1.11 up, sshd answering on :22, the forge's ssh on 192.168.1.10:2222, and /work mounted by its guard, for up to 5 min. On a pass, `boot-complete.target` → `systemd-bless-boot` strips the counter (good). On a fail during a counted boot, it reboots (a used try). `seed-boot-deadline` reboots a counted boot that hasn't reached boot-complete after 15 min | nixos/modules/boot-assessment.nix |
| loader.conf | `preferred` = NixOS's chosen entry (skipped once its tries are 0); `default` = the newest plain entry (the last good). Written after every boot-loader install | the same module |
| rescue entry | `seed-rescue.conf`: a RAM system (13 M kernel, 418 M initrd), independent of every deploy, installed only from rescue-pin.nix. It has 192.168.1.11 by MAC (DHCP on the other port), sshd for the builder's key and the orchestrator's, and its own host key | nixos/rescue.nix, modules/rescue-entry.nix, rescue-pin.nix |
| no hang | the watchdog (intel_oc_wdt, 30 s), `panic=30`, `boot.panic_on_fail` (a stage-1 failure panics instead of waiting for a key), no emergency mode | hosts/agent, boot-assessment.nix |

**Why it works this way, from the sources** (nixpkgs 1bc55b9def81, systemd 260.4):
- **NixOS has no counting of its own:** systemd-boot.nix has no boot-counting option.
  systemd-boot-builder.py names entries `nixos-generation-N.conf` (95 to 103, 206), rewrites all of them
  on every install, and runs `extraInstallCommands` afterwards (systemd-boot.nix 104 to 107). Its
  cleanup regex (257 to 279) skips counted names.
- **The counter** lives in the entry's file name. The loader parses and renames it (boot.c 1245 to 1289),
  and entries with 0 tries left sort to the end (1769).
- **`preferred` is matched with the assessment, `default` without it** (boot.c 1113 to 1127, 1839, 1893,
  ~1920). NixOS writes only `default`, which is why this module writes both.
- **Blessing:** `systemd-bless-boot.service` and `boot-complete.target` ship with NixOS's systemd
  (systemd.nix 112, 119).
- **Stage 1:** without `boot.panic_on_fail`, stage 1's `fail()` waits for a key (stage-1-init.sh 227,
  ~56).

**The arming step, tested** (evidence/20260928-boot-assessment-armtest.txt) on a copy of the ESP
layout, through: arm, rewrite, a used try, bless, deploys without a reboot, exhaustion, the builder's
limit, and a rollback.

## 0. Look first (as root)

```
bootctl status | sed -n '/Current Boot Loader/,/Boot Loaders Listed/p'   # systemd-boot 260.4; "Boot counting" features
bootctl list --no-pager                        # each entry: id, file name (with +LEFT-DONE), sort order
grep -E '^(preferred|default|timeout)' /boot/loader/loader.conf
ls /boot/loader/entries; cat /boot/loader/seed-armed
ssh-keygen -lf /boot/rescue/ssh_host_ed25519_key.pub     # the rescue's host key: record it
sha256sum /boot/rescue/bzImage /boot/rescue/initrd       # = rescue-pin.nix
systemctl status seed-boot-check seed-rescue-entry --no-pager
```

Expected on 20260928: entries for generations 3 (plain: booted before counting, the last good), 4 and 5
(armed `+3`, never booted), and 6 once PR #27 deploys (armed). `preferred` is the newest, `default` is
nixos-generation-3.conf.

## (a) A normal reboot marks the new generation good

```
date -u +%T; systemctl reboot
# from the operator's laptop: wait for ssh, then
journalctl -b -u systemd-bless-boot -u seed-boot-check --no-pager -o short-iso
bootctl list --no-pager; grep -E '^(preferred|default)' /boot/loader/loader.conf
journalctl --list-boots | tail -2
```

**Pass:**
- seed-boot-check says "all good … this generation will be marked good";
- systemd-bless-boot says the entry was marked good;
- the newest entry has **no counter** now.

(`default` moves to it at the next boot-loader install; until then the entry is plain, which is what
the loader reads.)

## (b) A broken generation is tried 3 times, then the box falls back by itself

Uses the test fixture `agent-test-nonet`: the agent box with its network matched to a MAC it doesn't
have. It boots, but 192.168.1.11 never comes up. It's installed by hand **for the next boot only**:
never through `deploy`, which would keep switching to it live.

```
systemctl stop seed-deploy.timer          # nothing may switch back before the reboot (the boot starts it again)
B=$(nix --extra-experimental-features 'nix-command flakes' build --no-link --print-out-paths \
      path:/work/agent/seed-lab/nixos#nixosConfigurations.agent-test-nonet.config.system.build.toplevel)
nix-env -p /nix/var/nix/profiles/system --set "$B"
"$B"/bin/switch-to-configuration boot     # the builder makes it the default; the hook arms it: "armed with 3 tries"
bootctl list --no-pager | head -20; grep -E '^(preferred|default)' /boot/loader/loader.conf
date -u +%T; systemctl reboot
```

**What happens, and the times to take from the operator's laptop:**
- **Each try:** about 30 s to boot, up to 2 min for `network-online` to give up, then 5 min of the
  check, then "boot check FAILED … rebooting (a used try)". **About 7 to 8 min per try**, and 192.168.1.11
  never answers.
- **After the 3rd try the entry has 0 tries left.** `preferred` is skipped and `default`, the last good
  entry, boots. **.11 answers again after about 22 to 25 min.** Note the time.

**Then, as root on the recovered box:**

```
journalctl --list-boots --no-pager | tail -5     # 3 failed tries + the fallback, with their times
for b in -3 -2 -1; do journalctl -b $b -u seed-boot-check --no-pager -o cat | tail -2; done
bootctl list --no-pager | head -20               # the fixture's entry: +0-3, sorted last; booted: the last good one
readlink /run/booted-system; readlink /nix/var/nix/profiles/system
```

**Pass:** 3 failed boots with "a used try", then a boot of the last good generation, with no hands.

**Clean-up:**
- `systemctl start seed-deploy`. It switches to `deploy`'s config as a new generation, armed; the next
  reboot blesses it.
- Then remove the fixture's generation:
  `nix-env -p /nix/var/nix/profiles/system --delete-generations <its number>`, and
  `/run/current-system/bin/switch-to-configuration boot`. The hook removes its counted entry.

## (c) The rescue entry boots when chosen once

```
bootctl list --no-pager | grep -A3 -i rescue
date -u +%T; systemctl reboot --boot-loader-entry=seed-rescue.conf
# from the operator's laptop, about 30 to 60 s later (it's a RAM system: no /work, no deploy):
ssh -o HostKeyAlias=agent-rescue root@192.168.1.11 'hostname; cat /proc/cmdline; findmnt / ; lsblk -o NAME,SIZE,MOUNTPOINT; ip -4 -o addr'
#   first time: compare the key ssh shows with the one recorded in step 0, then accept it (HostKeyAlias
#   keeps it apart from the agent box's own key)
ssh -o HostKeyAlias=agent-rescue root@192.168.1.11 systemctl reboot    # back to the normal default
```

**Pass:**
- the hostname is `agent-rescue`, and root is RAM (tmpfs/squashfs);
- 192.168.1.11 is up, and ssh answers with the recorded rescue host key;
- nothing of /work is mounted;
- the next boot is the normal one, since a one-shot entry doesn't stick.

**Last resort, not tested:** with every NixOS entry at 0 tries, the loader's own choice is the first
bootable entry in its sorted list, which is this one (boot.c 1924 to 1935).
