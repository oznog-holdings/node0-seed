# core onto its USB SSD (R3.01, R3.02, R3.05)

core ran from its SD card until 20260928 01:31Z; this is how it moved to the USB SSD (Netac Portable SSD, 476.9 G, serial
SERIAL-PLACEHOLDER, bridge 0dd8:2320). core is built **fresh from the repo**, the way README.md's
bootstrap rebuilds a dead core, so this is also the proof that core comes back from the repo with its
names. **The SD card is not touched and stays as the fallback:** the EEPROM tries USB first, then SD.

**Not carried across: ntfy's message store** (/var/lib/ntfy/cache.db; F-CORE-NTFY-STORE). A core built
from the repo starts with an empty store. Messages from before the move (on 20260928 the SSD's store
starts at 01:47Z) are only in the SD card's store and on the phones that received them.

**Why the retry is different (F-CORE-SSD-UAS, 20260928):** on the `uas` driver the SSD dropped off the
bus under resize2fs's writes. The retry runs it on plain usb-storage (the kernel quirk
`usb-storage.quirks=0dd8:2320:u`) and proves it under load before anything else.

## 0. The quirk (done 20260928)

- **usb-storage and uas are built into this kernel** (modules.builtin), not modules, so
  /etc/modprobe.d can't set it. Only two places can: at runtime `/sys/module/usb_storage/parameters/quirks`,
  and at boot the kernel command line, `usb-storage.quirks=0dd8:2320:u` in `/boot/firmware/cmdline.txt`.
- **Set on the SD system (20260928):** the runtime parameter read back `0dd8:2320:u`, and cmdline.txt
  gained exactly that one word (a single line still; backup `cmdline.txt.pre-ssd-quirk`).
  build.sh puts the same word into the SSD's own cmdline.txt.
- **It takes effect when the SSD is (re)plugged:** the kernel logs "UAS is ignored for this device,
  using usb-storage instead" and the device binds `usb-storage`, not `uas`. stress.sh refuses to run
  otherwise.

## 1. After the owner replugs the SSD

```
ssh admin@core 'cat /sys/module/usb_storage/parameters/quirks; sudo dmesg | grep -E "0dd8|UAS is ignored|Quirks match" | tail -3'
ssh admin@core 'ls /sys/bus/usb/drivers/usb-storage /sys/bus/usb/drivers/uas'   # the device (2-2:1.0) under usb-storage only
```

## 2. The stress test (destroys the SSD's contents; about 10 to 20 min; no outage)

```
cat site/core/ssd/stress.sh | ssh admin@core 'sudo bash -s' | tee evidence/<date>-core-ssd-stress.txt
```

- **What it runs:** mixed writes (4 × 8 GiB sequential across the disk plus random 4 KiB writes),
  a full read-back compared by sha256, then a whole-disk mkfs.ext4 with the inode tables written now,
  and e2fsck.
- **It FAILs** on any UAS abort, reset, offline, I/O error or "error -71" in the kernel log.
- **On a FAIL, stop.** The quirk didn't cure it, so it's power: a powered hub or a Y-cable (hands).
  Nothing else changes.

## 3. The build (no outage; core keeps serving from the SD card)

From the agent box, the image (checked against its published sha256) and core's identity to core's RAM:

```
xz -t 2026-09-15-raspios-trixie-arm64-lite.img.xz; cat 2026-09-15-raspios-trixie-arm64-lite.img.xz | ssh admin@core 'cat > /tmp/raspios.img.xz'
ssh root@infra cat /mnt/data/system/identity/core-20260924.tar | ssh admin@core 'sudo sh -c "umask 077; cat > /run/seed-core-identity.tar"'
cat site/core/ssd/build.sh | ssh admin@core 'sudo bash -s /tmp/raspios.img.xz' | tee evidence/<date>-core-ssd-build.txt
```

build.sh:
1. **Writes the image** with its own disk id, root UUID and boot volume id (the SD card's image has the
   same filesystem UUIDs), and grows root to the SSD.
2. **Sets the SSD's cmdline.txt and fstab:** its own PARTUUIDs, the quirk, no `ds=nocloud`;
   cloud-init disabled.
3. **Restores core's identity:** host keys and deploy key, so ssh stays strict and secrets.age opens.
4. **Names and access, as on the card:** hostname core, the git.seed.example.com line, America/Denver,
   the NetworkManager connection (192.168.1.12/24; resolver 127.0.0.1, .10). The image's `pi` becomes
   `admin` (uid 1000, the same groups), with the card's authorized_keys and sudoers file. ssh enabled;
   `regenerate_ssh_host_keys`, `userconfig`, `rpi-resize` and `sshswitch` masked.
5. **Runs README.md's bootstrap steps 2 to 3 and `apply` in a chroot**, with `SEED_APPLY_OFFLINE=1` and
   service starts blocked (policy-rc.d), so nothing binds the running core's ports.
   - The offline stage runs sections 1 to 4 (packages, pinned binaries, files, secrets), enables the
     units, and gets ntfy's certificate (DNS-01, about 2 min).
   - At first boot DNS, NTP, ntfy and the firewall start by themselves. seed-deploy runs the full
     apply 5 min later.

Then `/run/seed-core-identity.tar` and `/tmp/raspios.img.xz` are shredded on core.

## 4. The EEPROM boot order (no outage; takes effect at the next boot)

```
ssh admin@core 'sudo rpi-eeprom-config' > evidence/<date>-core-eeprom-before.txt
ssh admin@core 'sudo rpi-eeprom-config > /tmp/bootconf.txt; grep -q ^BOOT_ORDER= /tmp/bootconf.txt && sudo sed -i "s/^BOOT_ORDER=.*/BOOT_ORDER=0xf14/" /tmp/bootconf.txt || echo BOOT_ORDER=0xf14 >> /tmp/bootconf.txt; sudo rpi-eeprom-config --apply /tmp/bootconf.txt'
```

- `0xf14` is read right to left: 4 = USB mass storage, then 1 = SD, then f = restart and try again.
- **If the SSD is missing or won't boot, the SD card boots.** The before and after configs go into
  evidence. (The current config sets no BOOT_ORDER, so the firmware default applies.)

## 5. The switch (the outage: core is the site's primary DNS)

- **Watch from the agent box** every second: `dig @192.168.1.12` and `chronyc -h 192.168.1.12
  tracking`, and log the first and last failure.
- Then `sudo systemctl reboot` on core. **Expected:** the reboot (about 30 to 60 s, with the EEPROM
  update applied), then AdGuard, chrony and ntfy up at boot.
- infra's AdGuard answers as the second DNS server throughout (DHCP option 6 hands out both), so
  clients only see a delay.
- Then `sudo systemctl start seed-deploy` right away, rather than waiting 5 min: the firewall is
  loaded, the resolver set, and apply's own checks run.

## 6. The proofs

- **Root:** `findmnt /` on `/dev/sda2` with the SSD's PARTUUID; `/proc/cmdline` has the quirk; the
  device is on usb-storage.
- **Services:** DNS (`dig @192.168.1.12`, and DNS serves exactly rewrites.yaml via `site/bin/check-dns`),
  NTP (chrony synced, stratum 3), and ntfy (https health, and a message read back).
- **The power watch** reads the UPS (`seed_power_ups_readable 1`).
- **apply's own checks:** "core as the repo says".
- **From the agent box:** `site/bin/check-after-reboot` all ok.
- **The host key is unchanged:** strict ssh from the laptop and the agent box.

## 7. The way back

- **The SSD doesn't boot at all:** the EEPROM falls through to the SD card by itself.
- **It boots but is wrong:** hands. Unplug the SSD, and cycle plug4 (the Pi has no button). The SD
  card boots as before.
- **The SD card is never written by any of this**, except the one word in its cmdline.txt (the quirk,
  harmless without the SSD).
