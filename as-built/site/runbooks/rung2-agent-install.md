# Rung 2: installing the agent box on Larkbox two, without hands (planned 20260924; done 20260924, F-LARK)

index › Rung 2: "NixOS from the start, deployed from the site's own git forge … this box is
disposable and comes back from the repo." "If this is also the dev box, the second NVMe is the
work volume, mounted before the first repo is cloned." design › Deploying: a rescue boot entry
with automatic fallback; the identity store; rebuild one machine on purpose.

## Constraints (owner, 20260924)

- Larkbox two: 192.168.1.134 today (a minimal test NixOS by the orchestrator, root with the
  orchestrator's key, hostname larkbox2). NVMe **RS512GSSD510, serial SERIAL-PLACEHOLDER,
  cleared for wiping**. A USB stick is still in it: the installer goes there, found **by
  serial**.
- **Its firmware can't keep settings, and it doesn't return after a power cut. Warm restarts
  only, never a power-cycle.** It runs on the UPS directly.
- No hands: every step is remote. The orchestrator adds my (agentvm) key to its root first.
- **The stock installer's console:** the key on larkbox2's minimal NixOS was put there by the
  orchestrator (step 0), and the builder's records don't have the commands typed at that console.
  From step 2 on, the installer is the repo's own ISO with the keys built in, so nothing is typed.
  The builder's one stock-installer console step was on agentvm (20260923, typed with `virsh
  send-key`, `tools/vm-type.py`). Three lines, as the screenshots show them
  (evidence/20260923-agentvm/: console-04 the first line typed clean, console-03 all three garbled
  by a stuck Shift): `mkdir -p .ssh; chmod 700 .ssh; ls -ld .ssh`, then `echo '<the public key>' >
  .ssh/authorized_keys`, then `chmod 600 .ssh/authorized_keys; sha256sum .ssh/authorized_keys`.
  sshd was already running there; nothing was fetched.

## The one irreversible-without-hands risk, and its guard

A hang during a boot. Nobody may power-cycle it, so a hung kernel would stay hung. **Guard:**
both the installer and the installed system arm the hardware watchdog
(`systemd.settings.Manager.RuntimeWatchdogSec = "30s"`, `RebootWatchdogSec = "5min"`) and boot with `panic=30`, so a
hang ends in a *warm* reset by the chipset, which is a restart, not a power-cycle. Step 1
checks that the machine has a watchdog device (`/dev/watchdog`, `iTCO_wdt` or similar). If
it has none, I stop and report before step 4.

## Steps

**0. Before anything (orchestrator):** my key on larkbox2's root. **Owner:** this plan
approved, and the questions at the end answered.

**1. Discovery, read-only** (ssh as root, commands that change nothing):
`lsblk -o NAME,SIZE,MODEL,SERIAL,TRAN,MOUNTPOINTS` (the NVMe by serial; **the USB stick's
serial, size and contents**), `findmnt /`, `bootctl status`, `efibootmgr -v` (entries,
BootOrder, BootCurrent: **is USB before the NVMe in the default order?**), `ip -br link` and
`ethtool` (which NIC is wired, its MAC and negotiated speed, R1.13/R2.02), `lscpu`, `free`
(F-LARK: soldered RAM, one M.2?), `dmidecode -t bios -t system`, watchdog devices. All
recorded in the diary; the stick's serial written there before step 3 (annex rule).

**2. Build, on agentvm (nothing touches larkbox2):** a flake in the repo of record
(`seed-lab/nixos/`), nixpkgs pinned to agentvm's revision (1bc55b9d, 26.05), disko 1.13.0.
Outputs:
- `installer`: the minimal installer ISO with my key and the orchestrator's (the fixture) for
  root, sshd on, DHCP, no passwords, the watchdog and `panic=30`, disko and git included.
- `agent`: the installed system:
  - **disk (disko), `/dev/disk/by-id/nvme-RS512GSSD510_SERIAL-PLACEHOLDER`, GPT:** ESP 1 GiB
    (vfat, `/boot`), root 100 GiB (ext4, as on agentvm), **`/work` = the rest, about 376 GiB,
    XFS with `reflink=1`, noatime** (design › Development: a partition when there is one
    slot). zram swap.
  - **boot that doesn't depend on the firmware's memory:** systemd-boot with
    `canTouchEfiVariables = false`, so it lives at the removable path
    `\EFI\BOOT\BOOTX64.EFI` that any firmware falls back to; 20 generations in the menu (the
    rescue: boot an older one); boot counting where supported.
  - **identity:** a new ed25519 host key made on agentvm before the install, stored in the
    vault and as a 0600 tarball in the identity store on infra (R1.73, R2.24), and copied in
    at install time, so its fingerprint is known before first boot.
  - **network:** static 192.168.1.11/24 on the wired NIC (matched by MAC), DNS 192.168.1.10,
    router advertisements' DNS off (F-RA-DNS), the site's addresses in `networking.hosts`
    (R2.09: names without infra), chrony `server 192.168.1.10 prefer` plus the pool, firewall
    denying inbound except ssh.
  - **users:** `admin` (1000, wheel) and `agent` (1001, no sudo), the same fixed uids as
    agentvm (R2.17), `mutableUsers = false`. Keys: see question 2.
  - **power:** the power key ignored (`services.logind.settings.Login.HandlePowerKey = "ignore"`); not a UPS
    shutdown client (see question 5).
  - (Option names checked against the pinned nixpkgs: `systemd.settings.Manager.RuntimeWatchdogSec` (the older `systemd.watchdog.*` is deprecated in 26.05),
    `boot.loader.efi.canTouchEfiVariables`, whose `false`
    makes NixOS call `bootctl install --no-variables`, `zramSwap.enable`,
    `users.mutableUsers`.)
  - hostname `agent`, domain `seed.example.com`.
  - Evaluated and built on agentvm before step 3. The ISO's sha256 recorded.

**3. Write the stick** (destroys the stick's contents; serial in the diary first): stream the
ISO over ssh straight to `/dev/disk/by-id/usb-…<serial>` with `dd … conv=fsync`, guarded (the
resolved device's serial must match, it must not be mounted, and it must not be the NVMe).
**Verify:** read back exactly the ISO's length from the stick and compare sha256.

**4. One-time boot to the stick (warm):** `efibootmgr --bootnext <the stick's entry>` (create
an entry for the stick's `\EFI\BOOT\BOOTX64.EFI` if the firmware has none), then `systemctl
reboot`. The installer comes up on DHCP; I find it by MAC in the router's leases, ssh in with
my key, and check `BootCurrent` = the stick.
- **If the firmware ignores BootNext** (the test system comes back): plan B is `kexec` from the
  running test system straight into the installer's kernel and initrd. No firmware involved,
  and still a warm transition.

**5. Install:** in the installer, check the NVMe's serial against SERIAL-PLACEHOLDER, then
`disko` (wipes and partitions it from the flake's layout), then install the `agent`
system. The closure is built on agentvm and copied (`nix copy`); the host key comes in with
`--extra-files`. **Verify before rebooting:** `\EFI\BOOT\BOOTX64.EFI` and the loader entries
on the ESP, `/work` is XFS with `reflink=1`, and the hardware configuration (generated
without filesystems) is committed to the repo.

**6. First boot of the installed system (warm):** if step 1 showed that the firmware's
default order puts USB first, the stick's boot partition is erased first (otherwise the
next warm restart boots the installer again). Otherwise the stick stays, not in the boot
path. `systemctl reboot`. **Verify from agentvm:** ssh to 192.168.1.11 and check the host
key's fingerprint against the identity store's; `hostname`, `nixos-version`, `findmnt
/work`, `xfs_info /work`, `id admin agent`, `sudo -l -U agent` (nothing), `systemctl
--failed` (none), chrony selects infra, `nmap` from agentvm shows only 22. Then **one
deliberate warm reboot** to prove it comes back unaided.

**7. Records, in the same commit (R1.68):** `hosts.md` (agent = Larkbox two, its MAC,
static .11, arrival date; Larkbox one's MAC off that row), `rewrites.yaml` (already .11),
NetBox (`netbox-sync`), the identity store, coverage R2.01 to R2.29 as they apply. Then the
rest of rung 2 (Tailscale as the second subnet router, the watcher, flow-2 backups of `/work`,
pull-deploy from the forge's `deploy` ref, the nightly closure build), each as its own step.

## What can go wrong, and what then

| point | failure | recovery, still without hands |
|---|---|---|
| 3 | the stick write fails verification | rewrite it; the test system is untouched |
| 4 | BootNext ignored | kexec into the installer (plan B) |
| 4 | the installer hangs while booting | the watchdog resets it warm; the firmware returns to its default order (the test system, or the stick again) |
| 5 | the install fails after the wipe | the machine is still in the installer (DHCP, my key): fix and repeat |
| 6 | the installed system doesn't boot | the watchdog resets it warm; if the firmware then boots the stick, repair from the installer; if it boots nothing, **this is the case that needs hands** (a monitor and keyboard; still no power-cycle) |

## Questions before starting

1. The USB stick: cleared to overwrite once I've recorded its serial (I read "written to the
   USB stick still in it (by serial)" as yes)?
2. Keys on the new box: `admin` gets the laptop key and the orchestrator's fixture. Should my
   agentvm key go on `admin` (or root) **for the install and first checks only**, removed by
   a commit once pull-deploy from the forge works (so the boundary of F-AGENT-ADMIN holds on
   rung 2)? Or kept?
3. Name and address: it becomes `agent` at 192.168.1.11 (the annex's names), and Larkbox one's
   MAC leaves that row. Right?
4. The hardware watchdog as the guard against a hung boot: acceptable?
5. Power: it rides the UPS and is **not** told to shut down on a power event (it wouldn't come
   back). Agreed, or should it shut down with infra?
6. Layout: ESP 1 GiB, root 100 GiB ext4, `/work` the rest as XFS. Fine?
