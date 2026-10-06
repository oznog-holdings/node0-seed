# site2: the second site (rung 5, phase E)

**Status:** built 20260929: replicating hourly, monitored. **The restore test (R5.15) passed on 20260929**, with
infra powered off (below; evidence/20260929-r515/README.md).

rung-5: "a second site that receives an hourly, one-way, encrypted replica of the datasets that
matter".

## What it is
- **The box:** site2 is a NixOS 26.05 VM at another place, reached only over the internet through
  the seed's tailnet (100.64.0.12), as a relative's house would be. It accepts no subnet routes,
  and where it runs isn't the site's business.
  - Its LAN settings are a local, plain file, `/etc/systemd/network/10-lan.network`. It is kept on
    the box and not in the repository. NixOS doesn't manage it; it was made a plain file with its
    content unchanged, by sha256, before the first deploy.
  - Everything else is `nixos/hosts/site2`.
- **Access:** `ssh admin@100.64.0.12` with the builder's key (the orchestrator's key is there
  too, as the lab fixture). Its host key is ED25519
  SHA256:HOST-KEY-FINGERPRINT-PLACEHOLDER, checked on first connect.
- **Deploys:** `tools/site2-deploy.sh dry-run|test|confirm|status [ref]`, by default from the promoted `deploy` branch,
  built on site2 itself. site2 is remote-only, so a change never lands without a way back that needs nothing from us
  (20261004):
  - `dry-run` builds and shows what would change;
  - `test` arms a self-reverting timer first (an absolute UTC deadline, `REVERT_MIN`, default 15 minutes, back to the
    boot default's system), then activates without making it the boot default;
  - `confirm`, after checking site2 healthy (ssh over the tailnet, no failed units, tailscaled/sshd/node-exporter/
    networkd active, the pool ONLINE, Prometheus up=1, no new alerts), stops the timer and makes it the boot default;
    without it, the timer reverts.
  - Run by the builder, the orchestrator, or the site agents (in Tender's scope since 20261004, Christoph).

**What's replicated:** `data/documents`, `data/finance`, `data/photos` and `data/appdata`. appdata
holds the apps' nightly dumps (seed-dumps.sh: Vaultwarden, Forgejo dump and bundles, Postgres) and
the forge's own data.
- **Not replicated:** bulk media (none yet), `data/backups` (the restic repositories go to B2),
  `data/domains`, `data/isos`, `data/system` (secrets, metrics, state).
- **About 230 MB** at the first pull (20260929).

## How it works
1. **infra snapshots:** `replica-snap.sh` (User Scripts, `5 * * * *`, local time) snapshots the four
   datasets every hour.
   - Names are as sanoid makes them: `autosnap_<UTC>_hourly`, plus `_daily` at 00h UTC.
   - It keeps 48 hourly and 30 daily, never destroying a held snapshot.
2. **site2 pulls:** syncoid (`services.syncoid`, at :15) pulls as `root@100.64.0.10`, with a key
   made on site2 (`/var/lib/syncoid/infra_ed25519`; the private half never leaves).
   - On infra that key may run only `zfs-send-guard.sh`, and only from site2's address
     (`site/infra/backup/site2-authorized-key`): send and hold snapshots of the four datasets,
     read-only queries, nothing else. Every command is logged, refusals marked DENIED
     (`/mnt/data/system/seed-state/zfs-send-guard.log`).
   - Options: `--no-sync-snap --use-hold --no-resume --compress=none --no-clone-handling`, receive
     with `-u`. The newest common snapshot is held on both sides (`syncoid_site2`), so pruning on
     either side can't break the chain.
3. **Transport:** infra's sshd listens on its tailnet address too. At boot `sshd-tailnet.sh` (User
   Scripts, at array start) waits for tailscale1, then runs Unraid's `rc.sshd update`.
   `check-after-reboot` checks it.
4. **Encryption and pruning:** the replica lands in `site2/seed`, natively encrypted (aes-256-gcm,
   keyformat hex). The received datasets inherit it (encryption root `site2/seed`), read-only,
   mounted at `/srv/replica/<name>`. site2's sanoid prunes them (48 hourly, 30 daily).
5. **The key:** the vault item `zfs site2 replica key` (64 hex), on the recovery pack's list, and in
   `nixos/secrets/site2.yaml` (sops: the master key, site2's host key, compute).
   - At boot sops-nix writes it to `/run/secrets/zfs_key` (a tmpfs), and `site2-pool.service`
     imports the pool and loads it.
   - Where it lives, and what that protects: F-SITE2-KEY.
6. **The pool:** `site2`, one sparse file vdev `/var/lib/site2-pool/vdev0` (150 GiB) on the VM's
   single disk (F-SITE2-POOL). Made once, by hand:

       sudo install -d -m 0700 /var/lib/site2-pool && sudo truncate -s 150G /var/lib/site2-pool/vdev0
       sudo zpool create -o ashift=12 -O compression=zstd -O atime=off -O canmount=off -O mountpoint=none site2 /var/lib/site2-pool/vdev0
       sudo zfs create -o encryption=aes-256-gcm -o keyformat=hex -o keylocation=file:///run/secrets/zfs_key \
         -o readonly=on -o canmount=off -o mountpoint=/srv/replica site2/seed

7. **Monitoring** (on infra, from site2's node_exporter over the tailnet, which only infra may reach
   on :9100):
   - **ReplicaStale:** the newest replicated snapshot of a dataset is older than 2 h (a healthy
     replica is at most ~70 min old).
   - **ReplicaKeyNotLoaded.**
   - **ReplicaSnapshotsStale:** infra's hourly job.
   - **TargetDown** for site2 itself.

## The restore test (R5.15): passed 20260929, with infra off

**Result** (evidence/20260929-r515/README.md):
- **Infra off:** a clean powerdown from 09:22:46Z, confirmed from the agent box at 09:25:09Z (no ping, offline on
  the tailnet, no ssh).
- **Steps 2 to 4 ran from site2 alone, 09:25 to 09:30Z:**
  - documents restored, all 23 files identical by hash (the marker included), and the Forgejo dumps 23/23;
  - Forgejo ran on site2 from the appdata replica: `/api/healthz` passed at 09:27:42Z;
  - `git ls-remote` from the agent box showed the snapshot's refs (main 3f2cabd, deploy cee23db).
- Cleaned up, and infra powered back on at 09:29:32Z.

The procedure, as it was run:


**The gate:** with infra powered off (the owner or orchestrator does the power, and pauses the
dead-man first, `tools/healthchecks-window.sh pause`), from site2 alone:
- one dataset brought back, its files compared by hash;
- the forge answering from it.

**Before:**
- `check-after-reboot` green;
- ReplicaStale quiet;
- the newest snapshot on site2 less than 1 h old;
- on infra, a hash list of the files to compare: `/mnt/data/documents` and the Forgejo dump in
  appdata, taken right after the last pull and kept on the agent box.
- A marker is already in place: `/mnt/data/documents/.replica-test-20260929` (sha256 20e087ab… at
  the 05:48Z snapshot).

**The test:**
1. **Power off infra** (the owner). From the agent box, check it's off: no ping, and plug2 at
   standby. This is done by the person, not by me.
2. **On site2:** `zfs clone` (or `zfs send | zfs receive` locally) the newest `site2/seed/documents`
   snapshot to a writable dataset outside `site2/seed`'s read-only tree (it stays encrypted under
   the same key). Compare every file by sha256 with the list.
3. **The forge from the replica:** start Forgejo on site2 from a clone of `site2/seed/appdata`'s
   newest snapshot. Use the pinned image, or the NixOS module with the same version, on
   127.0.0.1. Then `curl …/api/healthz` from site2, and `git ls-remote` of `seed/seed-lab` from the
   agent box over the tailnet (agent → site2 is allowed). Its HEAD should equal the forge's last
   known `main`.
4. **Clean up:** destroy the clones on site2, and don't leave the Forgejo test running. Power infra
   back on (the owner), then run `check-after-reboot` and resume the dead-man.

**What it doesn't prove:** a replacement for infra's other services. The replica is data, not a
running copy of the site (rung-5 › What still fails).
