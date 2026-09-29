# Rung 5: the edge and the second site

**In plain terms.** Your network becomes yours. You decide which devices may talk to what, and
guests and smart-home gadgets get wifi networks of their own, away from your own machines. A
copy of the data that matters lives at a second place, such as a relative's house, so even
losing the whole house does not lose it.

**Status.** Built and tested on the bench, 20260928 and 20260929. The bench keeps double NAT by
the owner's decision (below), so "no double NAT" is described and measured, not built.

## What you get

- **A router whose configuration lives in the repository:** applied from it, exported back to
  it every day, and an alert when the two differ.
- **DNS the site owns:** Technitium, authoritative for the site's names, on the core box as the
  primary and the infra box as the secondary, with ad and tracker filtering, and every DHCP
  lease written into DNS as a name.
- **Three wifi networks: main, guest and IoT**, each kept apart by the router.
- **A second site** that receives an hourly, one-way, encrypted replica of the datasets that
  matter, with an alert when it falls behind, and a restore proven with the primary off.

**Buy.** A router you control, such as the OpenWrt One the bench has used since
[rung 0](../0-laptop/) ($145.99 on 20260928). If you already run one, this rung buys no
router. For the second site, a rescued box with its own drives ($300) or a second infra box
($2,540), at a place you trust.

![A blue metal router with three black antennas, between a mini PC and a laptop](../../images/router.jpg "The bench's router, an OpenWrt One: the household router from rung 0, and the site's edge at rung 5. Photographed 20260928.")

**What still fails.** The switch and the UPS are still single, and every application still
runs on the one infra box. The second site holds a copy of the data, not a running copy of the
services.

**What comes next.** [Rung 6](../6-firewall/) puts a dedicated firewall at the edge, for a site
that wants the network itself to be as trustworthy as the boxes on it, and this router becomes
its wifi access point.

This rung is a branch. A site can take it before [rung 4](../4-compute/), or take the second
site before the edge.

## Decisions and options

**The router's configuration in the repository.** One file per configuration package, an
`apply` that pushes them behind a rollback on the router (if a change cuts the router off, it
reverts itself after two minutes), and a daily export that alerts on any difference. Settings
the site does not own, such as the provider's side, stay on the router and appear in the
repository only as markers. Secrets are placeholders filled from the vault at apply time. Before
the first apply, take the router's own backup (`sysupgrade -b`) and keep it encrypted.
*Proof:* on 20260929 applying the repository changed nothing (the export was byte-identical
before and after); a deliberate change on the router was caught by the drift check, alerted and
reverted, and the rollback worked by itself when one confirmation failed.

**DNS: Technitium, with AdGuard retired.** A full authoritative server holds the zone itself,
answers reverse lookups, and takes lease updates from the router.
- Two servers, on addresses of their own (the bench: `.15` on core, `.16` on infra), so both the
  old and the new answer during the migration, and the cut-over and the way back are each one
  DHCP setting.
- The one list of names in the repository becomes one zone. The secondary follows the primary
  by zone transfer. Pin the primary's outgoing address, or the secondary refuses its notices
  when the primary has more than one address.
- Leases are written into a subzone (`lan.`) with a token that can change that subzone only.
- The migration as a copy: every name answered the same by old and new, checked from two other
  machines, before DHCP hands out the new servers. Retire the old servers only after every
  check points at the new ones, and change the deployed checks first.
- Traps: Technitium ships its own DHCP server, which must stay off. A container on a macvlan
  network cannot be reached from its own host, so the host itself resolves through the router.
  Technitium's API treats the PTR flag on an add as a replace; on 15.5.1 a delete removes only
  that name's own PTR.
*Proof:* on 20260929 every site name, outside name and blocked name gave the same answer from
both servers before the cut-over; after it, the checks, the watcher and filtering passed, and
with everything on core stopped, a name only the secondary held resolved in 14 ms.

**Double NAT, kept on the bench (the owner's decision, 20260928).** Two routers in a row that
each translate addresses is how many homes run, and not always by choice: a provider's gateway
that cannot bridge, or a mesh system that loses its mesh in bridge mode, forces it.
- *What it costs, measured 20260929:* both the bench and the second site sit behind "hard" NAT
  (the public mapping changes per destination) with no port mapping offered, so every remote
  path runs through a Tailscale relay: Denver, 31 to 45 ms, instead of a direct connection. No
  IPv6 reached the site. Remote access works; it is slower, and inbound ports are impossible.
- *The options, in order:* put the provider's gateway in bridge or passthrough mode where that
  costs you nothing else, so your router holds the public address and translates once; if you
  cannot, keep double NAT with a mesh VPN, as the bench does; on carrier-grade NAT (common with
  fiber and 5G providers), even bridge mode leaves translation upstream, and IPv6 is the way out.

**VLANs: none at this rung.** A site this size has one credible reason to segment: devices it
does not trust on the same wire as the boxes. The bench had none (guest and IoT are wifi only),
so it took no VLANs. Rung 6 needs them for the access point's link.

**Three wifi networks: main, guest and IoT.** Built on 20260928, tested, then switched off with
the configuration kept ([as built](../../as-built/site/router/wifi.md)).

| network | who joins it | may reach | may not reach |
|---|---|---|---|
| main (trusted) | your own laptops and phones | everything a wired box on the LAN may, including the site's services by name | nothing extra |
| guest | visitors | the internet | your LAN, the router's own services, IoT, other guests, the tailnet (your remote-access network) |
| IoT | smart-home devices: cameras, plugs, speakers, televisions | the internet | the same as guest; your own devices on main may open connections into IoT to control them, and IoT may open none back |

*Why:* visitors' devices and smart-home gadgets are the least trusted things in a house; many
gadgets never get a security update. On networks of their own, a compromised camera or a
visitor's infected laptop cannot reach your servers, your files or each other.
- Guest and IoT are each a routed segment with a bridge that holds only its wifi interface, so
  nothing on a wire changes. The router lets each reach only the internet, plus DHCP and DNS at
  its own address on that segment, and rejects every private range and the tailnet, so a guest
  gets a fast "refused". Clients on guest and IoT cannot see each other.
- Guest and IoT get a DNS server of their own on the router that knows none of the site's names.
- WPA2 and WPA3 mixed, so older devices still join.
*Would change it:* many IoT devices speak only 2.4 GHz; add the IoT network on that radio when
you have one. Casting and hubs need client isolation off on IoT.
*Proof:* 93 checks, none failed, on 20260928, from a mini PC joining each network in turn.
Isolation between two guests was checked on the access point's side only.

**The second site: a replica, pulled, one-way.** The cloud bucket from rung 0 already survives
a house fire, but restoring a whole site from it is slow; the replica keeps a recent copy of
the datasets that matter within reach.
- *What it holds:* documents, finance, photos, and the apps' data, which includes their nightly
  dumps and the forge. Not bulk media.
- *How:* the infra box snapshots those datasets every hour; the second site pulls them at a
  quarter past with syncoid, over the tailnet, as a relative's house would be reached. The pull
  uses a key that the infra box restricts to one command, a guard that allows only sending and
  holding snapshots of those four datasets and logs everything else as refused (21 hostile
  commands tried, all refused). The second site accepts no subnet routes, and a tailnet access
  policy lets it reach only the infra box's ssh.
- *Encrypted:* the replica lands in its own encrypted, read-only parent, so a stolen copy of the
  pool is unreadable. On the bench the key sits on the second site's disk, encrypted to its
  host key: that protects a stolen pool, not a stolen whole disk. *Would change it:* for a real
  relative's house, keep the key off the box entirely and send it after each reboot; the
  replication then pauses until you do.
- *Watched:* an alert when the newest replica is more than two hours old.
- *One disk:* the bench's second site is a single virtual disk with no redundancy. A real second
  site should keep the replica on a drive of its own.
*Proof:* on 20260929, with the infra box powered off, the second site alone gave back the
documents (23 of 23 files identical by hash) and ran the forge from its replica, which showed
exactly the branches expected at the snapshot. The hourly pull has run unattended since.

## Costs and measurements

Estimated from the Seed's design prices (US, checked 20260920; [costs](../../costs.md)): $550
lean and $2,840 full, for the router (an OpenWrt One, $145.99 on 20260928), an access point and
the replica box; the VLAN step ($250 to $400) is not included. Through rung 5: $4,440 lean and
$11,620 full.

Measured on the bench, 20260929:

| what | result |
|---|---|
| Remote access through double NAT | always relayed (Denver), 31 to 45 ms; no IPv6 from upstream |
| The replica's first full pull | about 230 MB at about 1.1 MB/s, through the relay |
| Each hourly pull after it | seconds |
| Restore with the primary off | passed: files by hash, and the forge from the replica |
| Infra power on to every container up | about 67 s |

What the power-off test also found, both now covered by checks: a newly added container left
off the autostart list stayed down after the reboot, and the infra box's ssh lost its tailnet
address when Unraid rebuilt its ssh settings at boot.

## Runbooks

- The DNS cut-over and its way back:
  [`dns-cutover.md`](../../as-built/site/runbooks/dns-cutover.md).
- The second site, its restore test and its way back:
  [`site2.md`](../../as-built/site/runbooks/site2.md).
- The router's configuration: [`README.md`](../../as-built/site/router/README.md), with
  [`config-tool`](../../as-built/site/router/config-tool).

## Configuration

As built:
- the router: [`site/router/config/`](../../as-built/site/router/config/);
- DNS: [`site/dns/technitium/`](../../as-built/site/dns/technitium/) and the one list of names
  [`rewrites.yaml`](../../as-built/site/dns/rewrites.yaml); AdGuard's retired configuration in
  [`adguard-archive/`](../../as-built/site/dns/adguard-archive/);
- the second site: [`nixos/hosts/site2/`](../../as-built/nixos/hosts/site2/), the snapshot job
  [`replica-snap.sh`](../../as-built/site/infra/backup/replica-snap.sh) and the restricted key
  [`site2-authorized-key`](../../as-built/site/infra/backup/site2-authorized-key);
- the tailnet's access policy: [`acl.hujson`](../../as-built/site/tailnet/acl.hujson).
