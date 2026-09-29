# AdGuard Home: retired 20260929 (rung 5 › F), kept here for the way back

AdGuard Home was the site's DNS from rung 1 (infra, 192.168.1.10) and rung 3 (core, 192.168.1.12, the
primary) until the rung 5 cut-over to Technitium (ns1 192.168.1.15 on core, ns2 192.168.1.16 on infra).
DHCP moved to Technitium at 05:04Z on 20260929 (site/runbooks/dns-cutover.md). Phase F then stopped
AdGuard on both boxes and archived its configuration here. Nothing was deleted.

## What's here
| file | was | what it is |
|---|---|---|
| `render-adguard` | `site/bin/render-adguard` | renders AdGuardHome.yaml from `site/dns/rewrites.yaml` over the pinned defaults (`--host infra|core`; the admin's bcrypt hash from `ADGUARD_ADMIN_HASH`) |
| `infra/defaults-v0.107.79.yaml` | `site/infra/adguard/` | the pinned version's own defaults, which the render starts from |
| `infra/start.sh` | `site/infra/adguard/` | the container's entrypoint: copies the rendered file over AdGuard's own at every start |
| `infra/my-adguard.xml` | `site/infra/templates/` | the Unraid container template (image pinned by digest) |
| `core/adguardhome.service` | `site/core/files/etc/systemd/system/` | core's unit |
| `core/pins-line` | a line of `site/core/pins` | the binary's version, sha256 and URL |

**What's still on the boxes**, stopped:
- **infra:** the container `adguard` (stopped, autostart off), `/mnt/data/appdata/adguard` (its
  rendered config, working copy, query log, statistics, filters), and
  `/boot/config/plugins/dockerMan/templates-user/my-adguard.xml`.
- **core:** `/opt/adguardhome` (the binary), `/etc/adguardhome` (the last rendered config) and
  `/var/lib/adguardhome`. `site/core/apply` removed the unit and disabled it.

**The vault items** `adguard core admin` and `adguard infra admin` are still there (deleting vault
items is the owner's call).

## The way back (to AdGuard, if Technitium must go)
Only if Technitium can't serve. For a short fault, the old DHCP way back is enough: point DHCP at one
AdGuard (the first steps below).
1. **infra:** start the container `adguard` through the Docker page (`tools/unraid-docker-action.sh
   start adguard`), and turn its autostart on (`tools/unraid-docker-autostart.sh adguard on`). Its
   last rendered config is still in appdata. To render it again from today's list:
   `ADGUARD_ADMIN_HASH=<bcrypt of the vault item> site/dns/adguard-archive/render-adguard --host infra`,
   written to `/mnt/data/appdata/adguard/seed/AdGuardHome.yaml` 0600, then restart the container.
   (The old `site/bin/deploy-infra-config` did this; see its history before 20260929.)
2. **core:** put `core/adguardhome.service` back under `site/core/files/etc/systemd/system/` and the
   pins line back into `site/core/pins`.
   - In `site/core/apply`: restore the render line, the unit in `units=`, the check, and the
     resolver `127.0.0.1 192.168.1.10`, and remove the "2b. retired services" block.
   - Put `ADGUARD_ADMIN_HASH` back in `tools/core-secrets-make.sh`, remake `secrets.age`, then
     promote.
   - `git show 3f2cabd:site/core/apply` (and that commit's other files) is the last full working
     state.
   - AdGuard on core must bind 192.168.1.12 and 127.0.0.1 only, never 0.0.0.0: ns1 holds
     192.168.1.15:53.
3. **The router:** in `site/router/config/dhcp`, set `dhcp_option '6,192.168.1.12,192.168.1.10'` and
   `server '/seed.example.com/192.168.1.12'` and `…/192.168.1.10`. Then `tools/router-backup.sh` and
   `site/router/config-tool apply`.
4. **Everything else that was moved to Technitium:**
   - the agent box's `dns` (nixos/hosts/agent), the watcher's DNS checks, the blackbox DNS targets,
     `site/bin/check-dns` (its AdGuard half is in git history);
   - Tailscale's split DNS (the owner's console);
   - compute's resolvers (`site/laptop/admin-setup.sh`, the owner).
