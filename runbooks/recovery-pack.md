# The recovery pack

One encrypted file on a USB stick that holds everything needed to rebuild the site when the
infra box and its password manager are both gone. Rung 1 and up.

## What goes in it

- The site's configuration repository, as a `git bundle`.
- Every backup credential: the restic repository passwords, the rest-server logins and the
  object storage keys.
  Include a **read-only restore key** for the bucket; a restore should never need a key that
  can write.
- The master key your configuration's secrets are encrypted to (for example a sops age key).
- The login the agent uses for the password manager, so the agent can run the restore.
- The infra box's boot flash, as a tar.
- Each host's identity (ssh host keys, machine ids), so rebuilt hosts keep their names in
  every `known_hosts`.
- A `README-RECOVERY.md`: the order of operations for the site as currently built. The bench's
  copy is [as-built/site/runbooks/recovery-order.md](../as-built/site/runbooks/recovery-order.md).
- A `MANIFEST.txt`: the sha256 of every file above.

The passphrase does **not** go in it. It lives in the hosted password manager's break-glass set
(the items kept for emergencies only) and in the person's head or on paper.

## Where it lives

Two copies, on two sticks:

- **One fully off site.** With a relative, at work, or in a bank's safe deposit box. It survives
  whatever takes the house.
- **One on site, but away from the machines.** A different room, or a fireproof safe. It is
  the one you reach for when a box dies and the house is fine.

A fireproof safe is rated to keep paper below the temperature at which paper chars. Flash
storage fails at much lower temperatures, so the safe will not protect the stick in a house
fire. It keeps the stick in one known spot, away from spills, knocks and borrowing. The
off-site copy covers the fire.

A stick left in the infra box is convenient for writing and useless in a fire. Write it
at the site, then take it away.

## Building it

Build it with a script, so every refresh is the same and can be reviewed. The bench's script
is [as-built/tools/recovery-pack.sh](../as-built/tools/recovery-pack.sh). Before you run it,
put in your two sticks' serials, your boot flash's serial and your infra box's address; it
ships with placeholders and the bench's address.

0. Check what the script needs before it runs. It reads the passphrase from a
   password-manager item named `recovery pack passphrase`, through the Bitwarden CLI (`bw`),
   which it unlocks with the master password in `BW_PASSWORD` (the bench's
   [vault-env.sh](../as-built/tools/vault-env.sh) loads that from a file readable only by the
   agent's account). It runs `gpg` through `nix-shell`. Create the item, log `bw` in on the
   agent box, and check that `nix-shell -p gnupg --run 'gpg --version'` prints a version. If
   the item is missing, the script stops, naming it, before the pack is written.
1. Plug one of the two sticks into the machine that will write it (on the bench, infra by
   default). Only one of the two may be plugged in.
2. On the agent box, from the site repository, run
   `STICK_HOST=user@host tools/recovery-pack.sh`, where `user@host` is the machine holding
   the stick. For a new stick, run `PREPARE=1 STICK_HOST=user@host tools/recovery-pack.sh`
   instead: it first makes one partition labelled `SEEDRECOV`, and refuses a stick that
   already carries that label.
3. Read the log. It should include `read back after dropping caches: sha256 ... (the same)`,
   `decrypted as a stream: 12/12 files match MANIFEST.txt` (your count may differ) and
   `the bundle verifies`, and end with `done`. A line starting `guard:` means it wrote nothing: fix what
   it names (no stick found, two sticks plugged in, a wrong label, something mounted) and run
   it again. `READ-BACK MISMATCH` means the pack on the stick is not what was written: stop, and try
   another stick.
4. Unplug the stick, plug in the other one, and repeat from step 2.

What the script does, in order:

- **Guards.** It finds the stick by its serial number, checks its label, and checks that it is
  not the device holding the boot flash and that nothing is mounted from it. On an Unraid box
  the boot flash is also a USB stick, and a script that picks "the USB stick" by position will
  sooner or later pick the wrong one.
- **Assembles the plaintext in memory** (`/dev/shm`, mode 0700), never on a disk. The files
  from infra are streamed over ssh.
- **Encrypts as a stream** (`tar | gpg --symmetric --cipher-algo AES256`, passphrase from a
  file descriptor) straight onto the stick, hashing while it writes. Only ciphertext leaves
  the machine that assembled it.
- **Reads back** after dropping the page cache and compares the hash. It then decrypts the
  whole pack into memory, checks every file against the manifest, and runs
  `git bundle verify` on the bundle.
- **Deletes the previous pack only now**, after the new one has passed those checks.

On exit it shreds the plaintext and unmounts the stick.

## When to refresh

Whenever one of its contents changes: a new backup key, a new host, a rotated master key, a
changed order of operations. On the bench the first pack (20260924) was made by hand; by
20260927 it lacked the master key, the read-only restore key and two hosts.

## Rehearsing

A pack nobody has restored from is a belief. Rehearse on a spare machine with the infra box
**off**, using only the stick, the passphrase from the hosted password manager, the README
inside the pack and the public internet.

The bench rehearsed on 20260927 on a spare mini PC running a live installer, all in memory,
in about 4.5 minutes in all, 2 min 40 s of it in the steps:

| Step | Time | What it proved |
|---|---|---|
| Fetch the tools (gpg, age, sops, restic, sqlite, pg_restore) | 50 s | a public package cache is enough |
| Check the stick, hash the pack, decrypt into memory | 32 s | 12 of 12 files match the manifest |
| Clone the configuration bundle | under 1 s | every template that README-RECOVERY.md names is there |
| Open the encrypted secrets with the master key | 18 s | after the fix below |
| Restore dumps from the bucket with the read-only key | 48 s | the password manager's database passes `PRAGMA integrity_check`; the forge's dump opens; `pg_restore --list` reads each Postgres dump |
| Shred the plaintext, unmount | 11 s | nothing left behind |

It found two faults, both in how the pack was built:

- **The master key was packed as the whole password-manager note**, and age and sops refused it. Pack
  only the key line (`grep '^AGE-SECRET-KEY-'`), and test it in the build's verify step by
  opening one real secret with it.
- **The bundle's copy of the deploy branch was stale**, because the build did not fetch first.
  Fetch every branch before `git bundle create`, and compare each head with the forge's.

### The whole infra box, on other hardware (20260928)

The second rehearsal rebuilt the infra box itself: the infra box switched off, a spare mini PC
(12 GB, one 512 GB SSD) on a fresh Unraid stick, and only the pack, the passphrase and the
internet. It ran as the infra box, with the infra box's own name, address and ssh host keys.
It brought back the password manager's 59 items, both forge repositories, and the gateway's
and the inventory's databases. 13 of the 16 services ran; the backup server, the backup
scheduler and the alert manager were kept stopped (see the last paragraph). Services answered
27 minutes after the pool was created; the whole run took 1 h 48 min, of which about 70 minutes went on the traps below.

**The order, as it worked.** The files to carry over and to leave behind, and the commands,
are listed in
[recovery-order.md](../as-built/site/runbooks/recovery-order.md).

1. **Set the clock first.** The spare's hardware clock was 7 hours off (a previous operating
   system kept local time). Nothing on a restored Unraid box sets the time until the array
   runs, and a wrong clock breaks the licence check, backup times, TLS and the password
   manager's tokens. Set the firmware clock to UTC before the first boot.
2. **Restore only what moves to new hardware:** the network settings and identity (name,
   address, host keys), users and shares, the Docker templates, the plugins' settings and the
   scheduled scripts. **Not** the array and disk configuration (`super.dat`, `disk.cfg`,
   `pools/`) or hardware state (for example a ZFS memory cap sized for the old box). Those
   belong to the old disks and are recreated anyway.
3. **Turn Docker and VMs off before the first array start,** or the pool format fails; create
   the pool; turn array auto start on.
4. **Restore the data from the bucket with the read-only key, excluding `/boot`:**
   `restic restore latest --host infra --target / --exclude /boot --no-lock`. Without the
   exclude, the restore overwrites the new stick's licence and port settings with the old
   box's. Without `--no-lock` it fails, because a read-only key cannot write restic's lock.
5. **Build the images the repository builds** (ours: chrony and Caddy) before their containers.
6. **Bootstrap the password manager:** it sits behind the proxy, and the proxy's password hash
   lives in the password manager. Start the proxy with a throwaway hash, restore the password
   manager, then set the real hash.
7. **Restore each database from its dump,** not from copied files. Check each dump's needs:
   our forge's SQLite dump needed SQLite 3.50 or later.
8. **Turn container autostart back on;** a restore does not carry it.
9. **Check** with the site's own tools:
   [`check-dns`](../as-built/site/bin/check-dns) (it exits 1 on any difference between the
   names in the repository and what the DNS server serves), a request through the gateway, a
   backup check with the read-only key (`restic check --no-lock`), and
   [`check-after-reboot`](../as-built/site/bin/check-after-reboot) (it checks the array, the
   pool and every autostart container, and exits 1 on any failure). If a check fails, stop and
   fix that step before you let the other boxes use the rebuilt one.

**The licence, planned before you need it.** Unraid refused the new stick's trial with "It is
not possible to use a Trial key with an existing Unraid OS installation": the restored array
record (`super.dat`) made it look like one. With only the configuration that moves to new
hardware (step 2), the trial was accepted. For a real recovery, a paid licence is tied to the
old stick's GUID, and moving it to a new stick retires the old stick for good. Know how you
will license the new stick before the day you need it, and never move the licence off a
working box for a rehearsal.

**Keep a good USB stick for Unraid.** The rehearsal's throwaway stick needed a hand at every
reboot (the firmware could not boot it and fell through to network boot). A recovery onto a
spare box should have someone standing by for each boot, and a stick that has booted that box
before.

**The rehearsal must not touch the live site.** It used only the bucket's read-only key. It
kept the backup server, the backup scheduler and the alert manager stopped, because the alert
manager would have un-paused the external dead-man (a hosted check that alarms when expected
pings stop). It never started remote access or file
sync, and requested no certificate, since the restored one was still valid. It made no commits
while it held the infra box's address, so the other boxes, which deploy from the forge, saw no
change.
