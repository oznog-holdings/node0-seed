# DNS cut-over: AdGuard → Technitium (rung 5, phase B), and the way back

**Status:** run 20260929, cut-over at 05:04Z (`evidence/20260929-rung5-B/`). Phase F retired AdGuard the
same day (`evidence/20260929-rung5-F.md`), so the way back below now starts from the archive:
`site/dns/adguard-archive/README.md`.

The migration is a copy, verified from a third machine, then a cut-over (design › DNS). By the
cut-over, the copy and the verification are done:
- **The copy:** ns1 (Technitium on core, 192.168.1.15) and ns2 (Technitium on infra, a container
  at 192.168.1.16) serve the zone rendered from `site/dns/rewrites.yaml`
  (`site/dns/technitium/push`).
- **The verification:** every name gets the same answer from the agent box and from compute
  (`tools/dns-compare.sh`), and `site/bin/check-dns` is green for all four servers.

**What the cut-over changes:** one commit to `site/router/config/dhcp`, applied by
`site/router/config-tool apply`:
- **DHCP option 6** (what clients are told): `192.168.1.12,192.168.1.10` (AdGuard) becomes
  `192.168.1.15,192.168.1.16` (Technitium).
- **The router's own forward** of the site's zone (`server=/seed.example.com/…`, used by the router
  and by anything that resolves through it, such as infra's own resolver) moves to the same pair.

**What it doesn't change:**
- **AdGuard** keeps running on both boxes, untouched, until phase F.
- **The boxes with static resolvers:** core (127.0.0.1 → AdGuard), the agent box and compute.
  Moving them is phase F.
- **Tailscale's split DNS:** the admin console is the owner's.

**Who sees it, and when:** a DHCP client takes the new servers at its next renewal (half the
12 h lease) or at its next join. On 20260929 the LAN had no active DHCP client (the one lease was
Larkbox one's, which is off), and the wifi radios were off.

## Before (every gate green)

1. `site/dns/technitium/push check`: 0 differences.
2. `site/bin/check-dns`: all five lines green (AdGuard ×2, the Technitium configuration, ns1, ns2).
3. The watcher is promoted with the ns1 and ns2 checks, and `seed_watcher_ok` is 1.
4. Alertmanager: only the Watchdog.
5. `tools/router-backup.sh` (a fresh backup), then `site/router/config-tool apply --dry-run`:
   only `dhcp` differs, and exactly in those two options.

## The cut-over

`site/router/config-tool apply`. It uses the router's 120 s rollback and the fixture hash before
and after. Then:
- **The router's offer:** `ssh admin@192.168.1.12 'sudo python3 - eth0' < tools/dhcp-discover.py`.
  Exactly one server answers, and its offer says DNS 192.168.1.15, 192.168.1.16.
- **The router's own forward:** from the router, `nslookup vault.seed.example.com 127.0.0.1`, and
  ns1's log shows the query from 192.168.1.1.
- **The rest:** `site/bin/check-dns`, the watcher, the filtering test (`doubleclick.net` → 0.0.0.0
  on ns1 and ns2), and Alertmanager.

## The way back

Any of these is enough to go back:
- a failed check after the cut-over;
- a client that can't resolve;
- the owner's call.

1. `git revert <the cut-over commit>` (it touches only `site/router/config/dhcp`).
2. `tools/router-backup.sh`, then `site/router/config-tool apply`. DHCP again offers
   192.168.1.12, 192.168.1.10 (AdGuard, still running), and the router forwards the site's zone
   to them.
3. Check the offer with `dhcp-discover.py` as above. Clients return at their next renewal; a
   client in trouble now can renew (or rejoin) at once.
4. Commit the revert and push. If ns1 or ns2 is the problem, stop it:
   - ns1: `sudo systemctl stop technitium` on core;
   - ns2: stop the `technitium` container through the Docker page.

   Nothing depends on them once DHCP is back. (Before phase F, only the new lease records and
   the watcher's ns1/ns2 checks do.)

**If the router itself is lost:** `site/router/README.md` › The way back, step 3 (the encrypted
`sysupgrade -b` backup).
