# Costs

What a Seed costs, rung by rung. Two kinds of figure, kept apart:

- **Measured.** What the bench's recurring services cost or were billed, with list prices
  marked as such.
- **Estimated.** Hardware prices from the Seed page (US, checked 20260920, the agent, core
  and firewall boxes and the router rechecked 20260928, before tax and shipping). The bench ran on borrowed and spare hardware, so these are not what we paid; they
  are what a reader would pay, and are labelled so.

## Hardware, by rung (estimated)

The columns follow the Seed page. **Lean** is the cheapest version that still does everything
the rung promises.
**Full** is what the page recommends for someone who will develop on the site. **Max** is
full plus 48 GB of memory in the infra box, bought up front.

| Rung | Lean (US$) | Full (US$) | Max (US$) | What |
|---|---|---|---|---|
| 0 | 0 | 0 | 0 | the laptop you have |
| 1 | 1,580 | 2,580 | 3,430 | the box, the licence, a switch, two or three drives, a UPS, cables |
| 2 | 240 | 960 | 960 | an N100 box, or an eight-core Ryzen mini PC with 64 GB and a second NVMe (both rechecked 20260928) |
| 3 | 240 | 240 | 240 | a second N100 box (rechecked 20260928) |
| **through 3** | **2,060** | **3,780** | **4,630** | the complete site without local compute |
| 4 | 1,830 | 5,000 | 5,000 | a used 64 GB M1 Max plus an adapter, or a DGX Spark; a GPU box is its own budget; see [rung 4](rungs/4-compute/) |
| 5 | 550 | 2,840 | 2,840 | the router (an OpenWrt One, $145.99 on 20260928), an access point and the second site's box; see [rung 5](rungs/5-edge/) |
| **through 5** | **4,440** | **11,620** | **12,470** | the site with its own edge and a second site |
| 6 | 240 | 890 | 890 | an N100 mini PC with two or more ports running OPNsense, or a firewall appliance (rechecked 20260928) |
| **through 6** | **4,680** | **12,510** | **13,360** | a small Node0 |

What the bench ran: an eight-slot all-flash box with three 512 GB NVMe drives, an 8-port 10G
unmanaged switch, a 1350 VA UPS, two N100 mini PCs (one now a spare), a Raspberry Pi 4
as core, and a 64 GB M1 Max laptop for rung 4.

**The Unraid licence.** Its tier is set by how many storage devices are attached, assigned to
a pool or not. The tiers differ in device count and in whether updates need a yearly fee; only the
lifetime tier has no recurring cost. Count the drives you will end with before you buy, and
check the current prices on Unraid's site.

## Recurring (measured or billed; list prices where marked)

| Service | What the bench used | Cost | Notes |
|---|---|---|---|
| Object storage (Backblaze B2) | 1.4 GB site data, 0.2 GB machine backups | about $0.02 a month | $6.95 per TB per month; the first 10 GB per account are free, so the bench's 1.6 GB cost nothing |
| DNS hosting | one zone | $0.50 a month | list price: DNSimple's per-zone price; its Solo plan has no base fee |
| Domain | one `.com` | $15.50 a year | list price; a `.co`, as on the bench, was $48.90 a year |
| External dead-man (Healthchecks.io), a hosted check that alarms when expected pings stop | one check | free | one check fits the free tier |
| Password manager (Bitwarden, hosted) | a free organisation, two members | free | the break-glass store, kept for emergencies only; Vaultwarden on infra is free |
| Remote access (Tailscale) | the personal plan | free | |
| Electricity | everything behind the UPS, rungs 1 to 4, at rest | about 55 W with a spare mini PC (5.9 W) also plugged in, so about 49 W for the site itself; about 480 kWh a year at 55 W | measured 20260928 at the UPS input; multiply by your price per kWh; the Mac adds about 60 W at the wall while it generates (see [data](data/README.md#power-draw)) |

**Recurring floor.** About $22 a year: the $15.50 domain and 12 months of DNSimple's $0.50
zone on its Solo plan. Solo has no domain-scoped API tokens, which the certificate job wants
(below), so $22 is the floor without them. Add storage beyond 10 GB: 100 GB is about $0.70 a
month, 1 TB about $7. Deleted versions stay hidden for 30 days, so add up to one month of
changed data on top.

**Choosing a DNS provider.** You need one whose API token can be limited to your one domain,
because the certificate job holds that token. DNSimple offers domain-scoped tokens on its
Teams plan ($29 a month) and Enterprise, not on Solo (checked 20260928,
support.dnsimple.com/articles/dnsimple-plans/). The bench's token was made on a middle tier.
Porkbun enables API access per domain, which gives a similar limit.

## Time

The person's time on the bench, rounded: about two hours at a desk for accounts, keys and
logins; one setup visit of about three hours at the bench (placing and cabling everything,
firmware settings, first boots), plus time on one faulty mini PC; then short answers to
questions as the build went. Everything else was agent work.
