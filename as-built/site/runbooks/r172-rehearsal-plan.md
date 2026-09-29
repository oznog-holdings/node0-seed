# R1.72, the full rehearsal: infra rebuilt on spare hardware from the recovery pack (plan, 20260928)

The owner's go, 20260928. This rehearsal follows recovery-order.md steps 2 to 6 and 8 on Larkbox one,
which runs Unraid 7.3.2 on a fresh stick as `infra-rehearsal` (192.168.1.14). It is the Unraid half
that the first rehearsal (20260927, R1.72 "done in part") couldn't do.

**The rules** (the orchestrator's):
- **The pack alone:** the stick, the hosted Bitwarden (break-glass), B2 with the pack's
  restore-reader key, the public internet, and the bundle's repo.
- **infra stays up until the orchestrator turns it off.**
- **The Unraid way:** the UI or emhttp where they reach.
- **Keep the trial key.**
- **A single-disk pool** on sdc.
- **Time every step.**
- **Nothing may write to B2, the rest-server, the tailnet or DNSimple.**
- **The live site exactly as it was afterwards.**

## Pre-checks done (20260928 15:15 to 15:25Z, nothing written anywhere)

| check | result |
|---|---|
| the box | .14 answers; Unraid 7.3.2; `regTy=Trial` (Trial.key, GUID GUID-PLACEHOLDER); array STOPPED; 11.7 GiB RAM (infra has 48), 4 cores |
| sda | SanDisk 3.2Gen1 57.3G, serial SERIAL-PLACEHOLDER, usb: the Unraid stick |
| sdb | ProductCode 29.3G, serial SERIAL-PLACEHOLDER, usb, vfat SEEDRECOV: pack copy A, `seed-recovery-20260928T0002Z.tar.gpg` (1,229,967,733 bytes) with MANIFEST.txt and README-RECOVERY.md |
| sdc | AirDisk 512GB SSD, serial SERIAL-PLACEHOLDER, sata. **It holds a Windows install: SYSTEM (vfat), a 128M MSR, BitLocker (474.9G) and Recovery (ntfs).** The owner has released it; it's to be wiped and become the pool |
| network | the cable is in the 2.5G port (MAC ending xx:xx, r8169), which this stick names **eth1**; eth0 (…xx:xx) has no carrier. The bond takes every port (no BONDNICS), so the active slave is eth1 |
| the pack | decrypted as a stream in **24 s** with the passphrase from the **hosted** org (item "recovery pack passphrase"); **all 12 files match MANIFEST.txt**. The plaintext is in the agent box's RAM only (/dev/shm, 0700), shredded at the end |
| the bundle | main a1845da (20260927 18:02 local), forge/deploy c8a31d0. **The rehearsal restores infra's config as of the pack.** What was committed since (the 4b gateway routes, the fast UPS rule, LinkFlapping, compute's probe) isn't in it |
| B2, read-only | the pack's **seed-restore-reader** key and `restic seed infra` password, `--no-lock`: the latest site-data snapshot is **8e076ea9** (20260928 07:00Z): **487 files, 1.335 GiB**, paths `/boot`, appdata, documents, finance, photos, system/identity |
| what it holds | dumps from 06:30Z today: Vaultwarden (`db_20260928_063001.sqlite3`, `rsa_key.pem`), Postgres (`litellm-…`, `netbox-…`), Forgejo (`forgejo-dump-20260928T063001Z.tar.gz`, repo bundles); **Caddy's production wildcard certificate, valid until 2026-12-23** (Let's Encrypt YE2); **no `system/secrets`** (by design: from the vault) |
| the pack's flash | `config/Trial.key` (**infra runs on a trial too**, bound to its own stick); **the Tailscale plugin with infra's tailnet state**; User Scripts schedules device-config, rest-maint, seed-dumps, seed-metrics, weekly-verify and sandbox-isolation, all wrappers for /mnt/data/system/seed-bin (not in B2); network.cfg .10, bond and bridge, no BONDNICS; `startArray="yes"`; pool `data` zfs, autotrim, compression |

## What the pack alone doesn't cover, and what's done instead

1. **Decryption:** Unraid has no gpg (nor restic, bw or age), and Docker needs a started array. The
   pack is decrypted on the agent box, as a tool. The ciphertext streams from .14, gpg comes from
   nixpkgs, and the plaintext stays in RAM. restic and bw likewise run on the agent box, or as the
   public static binaries on the rehearsal box (restic from GitHub, sha256 from the bundle's pins).
2. **The secrets directory** (step 4) isn't in B2. It comes from the vault: first the **restored**
   Vaultwarden (from the B2 dump; its ADMIN_TOKEN from the hosted break-glass item), opened by a
   **fresh** bw profile. Its password comes from the hosted item `vaultwarden seed-builder`, not from
   my working profile. Then the **bundle's** `site/bin/deploy-infra-config` runs with that profile
   (`HOME` a fresh directory, `SEED_REPO` the bundle's clone).

## The order, with the rehearsal's guards

| # | step (recovery-order.md) | how | guard |
|---|---|---|---|
| 0 | before anything is written | diary: sdc's serial and contents; the pack's flash kept aside | the owner released sdc |
| 1 | **stop: the orchestrator pauses the dead-man and shuts infra down** | none | .14 isn't .10 until then |
| 2a | the flash | keep this stick's `Trial.key` and `network-rules.cfg`; extract `flash/boot.tar` onto sda over ssh (the UI can't restore a flash); put `Trial.key` back | **before the first boot:** (i) remove the Tailscale plugin (`tailscale.plg` and its state) off the flash; (ii) User Scripts `rest-maint` and `weekly-verify` set to disabled |
| 2b | the first boot as infra | reboot; it claims **infra, 192.168.1.10** (bond over eth1) | Tailscale absent; no VM (libvirt.img is new); no container (docker.img is new) |
| 2c | the pool | **the Unraid way (the UI, tools/ui):** the pool `data` reassigned to one device, sdc (**a single disk: no redundancy, unlike infra's raidz1**); format zfs; array auto start on (it is: `startArray=yes`) | sdc's serial checked before the format |
| 3 | the site's data from B2 | restic, the reader key, `--no-lock`, `restore 8e076ea9 --target / --exclude /boot`. **The runbook says `--target /` without the exclude: that would overwrite the new stick's flash (its trial key and NIC rules) with infra's newer copy.** A fix for recovery-order.md, recorded as a finding | reader key: B2 can't be written |
| 4 | secrets | Vaultwarden first (step 6's dump, ADMIN_TOKEN from the hosted org), then the bundle's deploy-infra-config through the fresh profile | **restic-infra.env gets the reader key**, never the writer key the script renders |
| 5 | containers | templates from the bundle's `site/infra/templates/` into `templates-user/`; each created through **Docker › Add Container** (tools/ui), in the runbook's order | **not started: rest-server** (clients would back up into a copy that's thrown away; left failing, they resume against the real infra), **backrest** (created with no plans rendered), **alertmanager** (it would ping Healthchecks.io and so resume the paused dead-man, and write to the phone); **syncthing not created** (it would sync into compute) |
| 6 | databases from dumps | Vaultwarden (`db_20260928_063001.sqlite3` as `db.sqlite3`, `rsa_key.pem`); Forgejo (`forgejo dump` of 06:30Z); Postgres (`pg_restore` litellm, netbox). **Certificate: skipped.** The restored certificate is valid to 2026-12-23, so Caddy serves it and makes no ACME call. A staging certificate would still write a TXT record at DNSimple | no DNSimple write |
| 8 | checks | `check-dns`; Prometheus: targets up, only the Watchdog (and the alerts a single disk and the stopped services explain); `check-after-reboot` adapted (below); a restore test with the reader key (restic check, `--no-lock`) | no B2 write |
| end | a clean shutdown of the rehearsal box (the UI's Shutdown) | none | then the orchestrator brings infra back |

**Timing:** every step's start and end, UTC, in the evidence (evidence/20260928-r172/).

**While the rehearsal holds .10, the rest of the site talks to it:**
- core and the agent box pull `deploy` from the restored forge;
- the gateway's callers reach the restored LiteLLM;
- the agent box's vault scripts read the restored Vaultwarden.

Two rules follow:
- **Nothing is committed or pushed during the window.** The forge is the rehearsal's until the real
  infra is back; the records are written afterwards.
- **The restored forge's `deploy` must equal the live one**, or core and the agent box would roll
  back. The dump (06:30Z) must show the same deploy commit as the live forge before the cutover;
  this is checked at step 6.

**check-after-reboot on one disk:**
- **Expected to differ:** "pool data ONLINE" holds, but on one device; "every autostart container
  running" isn't true for the three deliberately stopped; "only the Watchdog fires" won't hold while
  those are stopped (TargetDown for rest-server and alertmanager).
- **Everything else is checked as written.**

## For a reader: the licence

- **The restored flash carries infra's own `Trial.key`, bound to infra's stick** (Unraid binds a key
  file to the stick's GUID). On a new stick it's invalid.
- **The rehearsal keeps the new stick's own Trial.key.**
- **In a real recovery with a paid key:** Tools › Registration › "Replace Key" on the new stick
  transfers the licence to the new GUID. That's self-service once a year; beyond that, through
  Unraid support. It retires the old stick for good.
- **With a trial (as infra has now, to 2026-10-23):** a new trial on the new stick. It doesn't carry
  the old trial's remaining days.

## Found during the pre-checks (20260928 15:05 to 15:21Z)

- **infra's link flapped twice while running:** 8 changes at 15:05Z, and about 38 from 15:16 to
  15:21Z. .10 was unreachable from 15:20:25 until 15:21:13Z.
- The system didn't reboot (booted 14:14:25Z); eth0's carrier_changes reached 47.
- The new LinkFlapping alert fired, with AgentWatcherFailing and NotifierFailing.
- F-INFRA-LINK-FLAP isn't only a cold-start problem.
