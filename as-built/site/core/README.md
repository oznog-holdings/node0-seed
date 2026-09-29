# core (rung 3)

index › Rung 3: "Move the DNS primary and the NTP primary here; infra's containers become the
second server of both", then notifications, the restore rehearsal and the home hub, and
"nothing else. Core is boring on purpose, and it is the box that handles power events".

On this bench core is a **Raspberry Pi 4 (4 GB) on Debian 13**, booting from its **USB SSD** since
20260928 01:31Z (a Pi on SSD, the pages' acceptable form; they prefer an N100). The SD card it ran
from before is untouched and is **the way back**: the EEPROM tries USB first, then SD. The move and
the way back: `site/core/ssd/README.md`. There is no NixOS here, so
`apply` is what a NixOS configuration would be (finding F-DEBIAN).

| what | how | where it is declared |
|---|---|---|
| DNS primary | AdGuard Home 0.107.79 (pinned, sha256), the same rewrites as infra | `bin/render-adguard --host core`, `files/etc/systemd/system/adguardhome.service` |
| NTP primary | chrony, `local stratum 10 orphan activate 0.1`, infra as a source | `files/etc/chrony/chrony.conf` |
| notifications | ntfy 2.28.0 (pinned), `https://ntfy.seed.example.com`, topic `seed`, deny-all with one user per sender | rendered in `apply` from `secrets.age` |
| restore rehearsal | weekly, reads infra's B2 repository, restores to tmpfs, `--verify`, one application restore | `files/usr/local/sbin/seed-restore-rehearsal` |
| power | reads infra's UPS (apcupsd network server) every minute and reports; never shuts core down | `files/usr/local/sbin/seed-power-watch`, `site/runbooks/power-protocol.md` |
| home hub | **not installed**: the home is not part of this site (owner, Q5, 20260923) | |
| deploy | pull from the forge's `deploy` ref every 15 minutes, fails closed | `seed-deploy`, `apply` |
| firewall | nftables, inbound denied; LAN for ssh, DNS, NTP and ntfy; exporter for infra only | `files/etc/nftables.conf` |
| metrics | node_exporter on 192.168.1.12:9100 plus textfiles (deploy, power, time, root filesystem, rehearsal) | `files/usr/local/sbin/seed-core-metrics` |

**Secrets:** `secrets.age`, one age file to three recipients (core's ssh host key, the master
key, the laptop key), made from the vault by `tools/core-secrets-make.sh`. `apply` decrypts
it in memory with the host key and writes each value to the one file that needs it (0600, or
0640 to the one service's group).

**Writes are kept low** (a rule from the SD card, kept on the SSD). The DNS query log stays in
memory, restored files and restic's work go to `/tmp` (a tmpfs, and no restic cache), the journal
is capped at 64 MB and synced every 15 minutes, and root is mounted `noatime`. The monitoring reads
ext4's error count on whatever root is mounted from (the SSD now), and the SD card's identity while
the card is present. core keeps no state that matters beyond ntfy's message store
(F-CORE-NTFY-STORE): everything is in this repo and its identity (host keys) is in infra's identity
store, so a dead SSD is a new one built by `site/core/ssd/`, or the SD card meanwhile, with the host
keys put back.

## Bootstrap (once, on a fresh Debian 13 as `admin` with sudo)

1. Static address 192.168.1.12/24 (NetworkManager), gateway .1.
2. `sudo install -d -m 0700 /var/lib/seed-deploy`; a deploy key made there
   (`ssh-keygen -t ed25519 -C seed-deploy@core -f /var/lib/seed-deploy/deploy_key -N ''`),
   registered on the forge **read-only** for `seed/seed-lab`; the forge's host key pinned
   in `/var/lib/seed-deploy/known_hosts` from `nixos/forge-hostkey.pub` for
   `[git.seed.example.com]:2222,[192.168.1.10]:2222`.
3. `sudo apt-get install git age python3-yaml`; `192.168.1.10 git.seed.example.com` in
   `/etc/hosts`; then `sudo install -m 0755 site/core/seed-deploy /usr/local/sbin/` from a
   checkout and run it. From then on the timer keeps core as `deploy` says.
4. **With the USB SSD attached** (bridge 0dd8:2320): `usb-storage.quirks=0dd8:2320:u` in
   `/boot/firmware/cmdline.txt` (usb-storage is built into the kernel, so modprobe.d can't set it).
   On `uas` the SSD drops off the bus under load (F-CORE-SSD-UAS). The move onto the SSD:
   `site/core/ssd/README.md`.
5. If the host keys are new (a new card without the identity tarball), re-run
   `tools/core-secrets-make.sh` for the new key, commit and promote before step 3.
