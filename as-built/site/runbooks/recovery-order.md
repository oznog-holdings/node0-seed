# Seed site: order of operations for a recovery (one page, in the recovery pack)

design › Secrets › recovery pack: in two places, neither of which is the site. This page is
inside it. Decrypt the pack with the passphrase in the hosted Bitwarden organisation "Seed"
(item "recovery pack passphrase"):
`gpg --decrypt seed-recovery-<date>.tar.gpg | tar -x`

## Where the pack is kept (the owner's rule, 20260928)

- **Two copies:** A (serial SERIAL-PLACEHOLDER) and B (serial SERIAL-PLACEHOLDER), both labelled SEEDRECOV
  (site/hosts.md › Recovery media).
- **One copy fully off site. The other on site, but in a separate location:** a different room, or
  a fireproof safe. A fireproof safe is rated for paper, not necessarily for electronics, but it
  stores a stick safely and survives minor incidents; that's why the other copy is off site.
- **Refresh both copies each time:** plug one in (the agent box or Larkbox one), then run
  `STICK_HOST=user@host tools/recovery-pack.sh`, and repeat for the other. The script takes either
  serial, refuses if both are plugged in, and deletes a stick's old pack only after the new one
  reads back and decrypts. Refresh after a change to the repo, the vault's routine items, a host
  identity or the flash, and at least quarterly (core's quarterly reminder says so).

## What the pack holds (see MANIFEST.txt for names and sha256; refreshed 20260927)

- `repo/seed-lab.bundle`: the config repo of record (git bundle of every ref). `git clone
  seed-lab.bundle seed-lab` gives the whole site config (`site/`, `nixos/`) and the record.
- `secrets/restic.txt`: every `restic seed *` repository password (B2 `restic/infra`, `restic/laptop`;
  rest-server repositories agent, agentvm, compute), the rest-server logins, and the B2 keys:
  **seed-restore-reader** (read-only: use it to restore), seed-writer, and seed-machines-writer.
  The B2 **admin** key is the owner's and is not here.
- `secrets/master-key.txt`: the sops/age master key. (The pack of 20260927 holds the vault item's
  whole notes, and age rejects that file at line 1; take the key line first:
  `grep '^AGE-SECRET-KEY-' master-key.txt > key.txt`.) It opens `nixos/secrets/agent.yaml` and
  `site/core/secrets.age` in the bundle (`SOPS_AGE_KEY_FILE=master-key.txt sops -d …`,
  `age -d -i master-key.txt …`).
- `secrets/builder-vault-login.env`: the builder agent's Bitwarden API login (F-REBUILD-STATE).
- `flash/boot.tar`: the Unraid flash (config, host keys, the container templates, and the licence
  key file, which is bound to the old stick's GUID: on a new stick, Unraid's licence transfer or a
  fresh trial).
- `identity/`: host identity tarballs (infra, router, core; the agent box's ssh host keys, and its
  Tailscale state with the forge deploy key in `agent-extra-*.tgz`; agentvm's host keys).

## Order (infra lost, rebuilding on spare hardware)

**Proven by the rehearsal of 20260928 (R1.72; evidence/20260928-r172/).** These notes come before the
steps, and each is written into the step it concerns:
- **The clock first,** before the licence, restic, TLS or Vaultwarden. A box that last ran Windows
  keeps its hardware clock in local time, which Unraid reads as UTC. infra's flash has Unraid's NTP
  off, and its chrony container only runs once the array does.
- **The licence: plan it before you need it.** A flash restored onto a new stick needs the licence
  moved to that stick (Tools › Registration › Replace Key), which blacklists the old stick for good.
  A trial can't be used: a restored `super.dat` makes the stick "an existing installation"
  (ETRIAL). Never move the real infra's licence during a rehearsal.
- **Restore only the configuration that moves to other hardware** (step 2).
- **Build the site's own images** (step 5): `seed/chrony`, `seed/caddy`.
- **Vaultwarden needs Caddy, and Caddy needs one vault item** (step 4).

1. **Names and a box.** A spare box on the LAN, internet up. The domain and DNS registrar are
   unaffected (DNSimple); the router still serves DHCP.
2. **Unraid.** Write a fresh Unraid USB, restore `flash/boot.tar` onto it (keeps the config
   and host keys), boot. Create the pool `data` (the layout rule: see `site/hosts.md` and the
   diary of 20260923).
   - **Set the clock first.** Check `date -u` against a good clock, and set the firmware clock to
     UTC.
   - **Carry over** from `config/`: `network.cfg`, `network-extra.cfg`, `ident.cfg`, `ssh/`, `ssl/`,
     `passwd`, `shadow`, `smbpasswd`, `secrets.tdb`, `share.cfg`, `shares/`, `docker.cfg`,
     `domain.cfg`, `go`, `rclone/`, `wireguard/`, and `plugins/` (the container templates and
     User Scripts included).
   - **Keep the new stick's own** key file and `network-rules.cfg` (its own NICs).
   - **Don't carry over** (array, disk, installation or hardware state; Unraid recreates them):
     `super.dat` (it made the stick an "existing installation"), `disk.cfg`, `pools/`, `machine-id`,
     `random-seed`, `drift`, `forcesync`, `savedpcidata.json`, `custom_params_comments.json`,
     `plugins-error`, `modprobe.d/zfs.conf` (the ZFS memory cap is sized to infra's RAM).
   - **Move aside before the first boot** anything that mustn't act yet: in a rehearsal, the
     Tailscale plugin (it would bring up infra's identity on the tailnet), and apcupsd if there's
     no UPS on USB (core would report COMMLOST).
   - **The pool,** through Main (or emhttp's `changeSlots`, `changeDevice`, `changeDisk` and
     `cmdStart`/`cmdFormat` with `startState`, which is what the page posts). Set Docker and VMs off
     (Settings) **before** the first array start: otherwise they start on the unformatted pool's path
     in RAM, and the format fails with "mountpoint /mnt/data exists and is not empty". Then turn
     auto start on. Create each share's top level through `/mnt/user/<share>`, so it becomes a ZFS
     dataset.
3. **Restore the site's data from B2** with restic (the **seed-restore-reader** key and the
   `restic/infra` password from `secrets/restic.txt`, with `--no-lock`, since that key can't
   write a lock; repository
   `s3:https://s3.us-east-005.backblazeb2.com/your-seed-bucket/restic/infra`):
   `restic restore latest --host infra --tag plan:site-data --target / --exclude /boot`. That
   returns appdata (with the application dumps), identity, documents, finance, photos (1.3 GiB,
   seconds). **`--exclude /boot` matters:** the snapshot holds infra's flash too, and restoring it
   over the new stick would undo step 2's choices.
4. **Secrets directory.** Recreate `/mnt/data/system/secrets` from the vault
   (`site/bin/deploy-infra-config` does it from the agent box, or by hand from the vault items).
   **The order (rehearsed):**
   1. `vaultwarden.env` (ADMIN_TOKEN from the hosted item) and `caddy.env` (the DNSimple token from
      the hosted item).
   2. `caddy-auth.env` bootstrapped with the bcrypt of a random throwaway, because the real hash comes
      from the site vault. The bw CLI refuses plain HTTP, so the vault must be reached through
      Caddy's TLS.
   3. Vaultwarden from its dump, then Caddy.
   4. A fresh bw login to `https://vault.seed.example.com`, with its password from the hosted item
      `vaultwarden seed-builder`.
   5. deploy-infra-config.
   6. Remove the bootstrap `caddy-auth.env` first, since the script leaves a present one alone, and
      create rest-server before the script runs (it aborts on a host without one).
   7. Restart Caddy.
5. **Containers.** First build the site's own images from the repo: `docker build -t
   seed/chrony:4.8-alpine3.24 site/infra/chrony`, and `-t seed/caddy:2.11.4-dnsimple
   site/infra/caddy` (the tags are in the templates). Start Docker from Settings, or with the array.
   Never start it from an ssh session: dockerd inherits that session's `XDG_RUNTIME_DIR`, and
   `docker exec`, including the health checks, breaks when the session ends. Copy the templates from
   `site/infra/templates/` (the restored flash has them too) into
   `/boot/config/plugins/dockerMan/templates-user/`, and create each through Docker › Add Container,
   **turning Autostart on** for each on the Docker page (templates don't carry it), in the start
   order: chrony, adguard, postgres, valkey, caddy, vaultwarden,
   forgejo, litellm, netbox, netbox-worker, rest-server, backrest, node-exporter, blackbox,
   prometheus, alertmanager.
6. **Databases from their dumps**, not from copied data: Vaultwarden (`dumps/db_*.sqlite3` as
   `data/db.sqlite3`, plus `rsa_key.pem`), Forgejo (`forgejo dump` archive), Postgres
   (`pg_restore` per database). Then Caddy obtains its certificate by DNS-01.
   - **Forgejo:** extract the dump. `data/` goes to `appdata/forgejo/data`, where this image keeps
     `custom/conf/app.ini` too. `repos/` goes to `data/git/repositories`. Rebuild `gitea.db` from
     `forgejo-db.sql` with an SQLite of 3.50 or later: the dump uses `unistr()`, and older sqlite
     fails on it. Then `chown -R 1000:1000`.
   - **The certificate:** Caddy serves the restored one if it's still valid, and makes no ACME call
     until its renewal window.
7. **Agents and the other boxes.** The agent box and core are separate hardware and normally
   survive infra. If the agent box is lost too: `site/runbooks/rebuild-agent-box.md` (its identity
   tarballs are in `identity/`, and `/work` comes from the rest-server repository `agent`). core:
   `site/core/README.md` (it pull-deploys from the forge once infra is back). compute (rung 4):
   `site/laptop/inference/README.md`.
8. **Check** with the site's own tools: `site/bin/check-dns`, the monitoring floor
   (all targets up, only the Watchdog firing), a restore test (`weekly-verify.sh`).

If the vault itself is gone too: the hosted Bitwarden organisation "Seed" keeps the break-glass set,
the 19 items in `tools/vault-breakglass.txt`, each with its reason:
- the pack's passphrase;
- the site vault's own unlock (vaultwarden seed-builder) and admin token;
- infra's and the router's root;
- the sops master key;
- every restic password, and the rest-server logins;
- the three B2 keys, the read-only one included;
- the DNSimple token (certificates, so the bw CLI can reach a restored Vaultwarden over TLS);
- the Healthchecks.io API key, to pause the dead-man with infra down (`tools/healthchecks-window.sh`).

Every other item lives only in the site vault from the D.01d trim; the scripts read it there
(`tools/vault-env.sh`; `SEED_VAULT=hosted` for the break-glass items with the site vault down).
Restore Vaultwarden first (steps 5 to 6, its admin token from the hosted org); then
deploy-infra-config reads the rest from it.

## The second site (rung 5, from 20260929)
An hourly encrypted replica of data/{documents,finance,photos,appdata} lives on site2 (tailnet
100.64.0.12; site/runbooks/site2.md). If infra's data is lost, a recent copy of documents,
finance, photos and the apps' dumps and forge data is there. Its key is the vault item `zfs site2
replica key` (on this pack's list), and the sops file nixos/secrets/site2.yaml opens with the master
key in this pack. Restoring from it was not yet rehearsed (R5.15).
