# hosts

Update in the same commit as the address record and `dns/rewrites.yaml` (design › Inventory).
Servers are static outside the DHCP pool (.100 to .249, deviation D.04; Kea on the firewall from rung 6, the router's before); laptops
use DHCP. MACs as seen by the router (`ip neigh`, `/tmp/dhcp.leases`) on 20260923.
Arrival: the day the box was first configured on the bench.

| name | role | address | MAC | location | arrival |
|---|---|---|---|---|---|
| router | OpenWrt One: **the access point from rung 6** (cut-over 20260929 20:4xZ; site/router/config.ap): br-lan = eth1 (the switch) + eth0 (the trunk from the firewall, 2.5 GbE), VLAN 20/30 bridged to the guest/IoT wifi, no routing, DHCP or DNS; its WAN disabled. Wifi (radios off except for tests): `seed` (LAN), `seed-guest` (VLAN 20), `seed-iot` (VLAN 30); site/router/wifi.md. Until rung 6 it was the gateway at 192.168.1.1 | 192.168.1.4 | 02:00:00:00:00:01 (br-lan) | bench, UPS battery outlet (from 20260929: switch ~15:37Z, router ~15:48Z; rung 6 decision 1) | 20260923 |
| switch | YuanLey 8-port 10G, **unmanaged** (8 x 10GBASE-T RJ45, 10G/5G/2.5G/1G/100M auto-negotiation, 160 Gbps; the owner, 20260928); no address, no config to pull | none | none | bench, UPS battery outlet (from 20260929: switch ~15:37Z, router ~15:48Z; rung 6 decision 1) | 20260923 |
| infra | infra: Unraid 7.3.2, TerraMaster F8 SSD Plus, pool `data`. Docker's host access to custom networks on (20260929): the host reaches its macvlan containers (ns2) through `shim-br0`, and resolves through ns2 (.16) then ns1 (.15) | 192.168.1.10 | 02:00:00:00:00:01 (br0); **the LAN sees 02:00:00:00:00:01 (shim-br0)** for .10 since the shim (its routes win) | bench, UPS (pending) | 20260923 |
| agent | agent box (rung 2): Larkbox two, Chuwi LarkBox X (N100, 12 GB, NVMe SERIAL-PLACEHOLDER), NixOS from `nixos/` (flake), /work XFS; warm restarts only (a reboot is a root step: tools/root-reboot-agent-box.sh), rides the UPS. The site agents run here as `tender`: Claude Code (Tender) the ACTIVE agent from 20261006 04:50:43Z; Hermes installed, PAUSED by decision (20261002, its comparison moves to a GPU); its Telegram check (tender-telegram-check) PAUSED by decision 20261006 until Hermes's GPU day. Each pause is a marker, ~/.config/site-agents/paused/{hermes,telegram}, first line the reason; remove it to resume | 192.168.1.11 | 02:00:00:00:00:01 | bench, UPS battery outlet (owner 20260928) | 20260924 |
| larkbox1 | **became `fw` on 20260929** (rung 6 phase 1: OPNsense installed on its SSD by the owner); kept as a row for the history | none |, (see fw) | bench | 20260923 |
| fw | the firewall (rung 6): OPNsense 26.7 on Larkbox one (Chuwi LarkBox X, SSD AirDisk SERIAL-PLACEHOLDER), installed by the owner at the console 20260929 (phase 1). WAN re0 (RTL8168h 1 GbE, …xx:xx), LAN re1 (RTL8125B 2.5 GbE on the Realtek vendor driver, os-realtek-re). **The LAN gateway from the cut-over (20260929 20:43Z):** 192.168.1.1, main DHCP (Kea, DNS .15 .16, DDNS into lan.seed.example.com), guest 192.168.20.1 and IoT 192.168.30.1 on VLANs 20/30 over re1; the upstream on re0 (the owner's static values). It was 192.168.1.2 beside the router in phases 1 to 2 (.2 is free). Powers on after AC loss (38 s to ssh). Host key ED25519 SHA256:HOST-KEY-FINGERPRINT-PLACEHOLDER | 192.168.1.1 | 02:00:00:00:00:01 (re1, LAN) | bench, plug3 behind the UPS | 20260929 |
| core | core box (rung 3): Raspberry Pi 4 (4 GB), Debian 13, **root on a USB SSD from 20260928** (Netac Portable SSD 476.9 G, serial SERIAL-PLACEHOLDER, usb-storage quirk 0dd8:2320:u; EEPROM USB then SD), the SD card SD32G serial SERIAL-PLACEHOLDER kept as the fallback; DNS and NTP primary, ntfy, restore rehearsal, power watch; config from `site/core` (pull-deploy) | 192.168.1.12 | 02:00:00:00:00:01 | bench, plug4 behind the UPS | 20260924 |
| agentvm | agent VM on infra (rung 1): NixOS 26.05, 4 GiB; **kept running with an empty /work from 20260928** (its old contents retired after verification, R2.20; its backup plan stopped, the rest-server repository `agentvm` dormant; ready for rung 6) | 192.168.1.13 | 02:00:00:00:00:01 | on infra | 20260923 |
| compute | the laptop from 20260924 (user `seed`; config in `site/laptop`), and compute at rung 4, **dedicated to the seed from 20260927** (the owner doesn't use it; the model backend: `site/laptop/inference`): MacBook Pro M1 Max 64 GB, macOS 26.6, FileVault on, wired (USB 2.5G, en9), wifi off | 192.168.1.20 | 02:00:00:00:00:01 | bench, UPS surge-only outlet (no battery; the Mac's own battery carries it; owner 20260928) | 20260924 |
| ns1 | Technitium DNS on core (rung 5): the primary, authoritative for seed.example.com, lan.seed.example.com and 1.168.192.in-addr.arpa; core's second address (NetworkManager, site/core/apply) | 192.168.1.15 | 02:00:00:00:00:01 (core's eth0) | on core | 20260929 |
| ns2 | Technitium DNS on infra (rung 5): the secondary (zone transfers from ns1); the container `technitium` on Docker's br0 (macvlan), so infra itself can't reach it | 192.168.1.16 | 02:00:00:00:00:01 (set in the template) | on infra | 20260929 |
| site2 | the second site (rung 5 › E): NixOS 26.05 VM elsewhere, from `nixos/hosts/site2`; receives the hourly encrypted replica of data/{documents,finance,photos,appdata} (site/runbooks/site2.md). Reached only over the tailnet; its LAN isn't the site's, so no LAN address, MAC or DNS name here (Tailscale names it `site2`); the site agents reach it as admin by their own key since 20261004 (Christoph), deploys only by `tools/site2-deploy.sh` (a self-reverting timer) | 100.64.0.12 (tailnet) |, (not the site's) | elsewhere | 20260929 |
| sandbox | **sandbox** VM on infra (R1.92): from `nixos/` (tracks `main`, deployed first), nothing of production, isolated (`site/infra/sandbox/isolation.sh`), **not monitored, not autostarted**; no LAN name | libvirt NAT, DHCP (192.168.122.155 seen) | 02:00:00:00:00:01 | on infra (virbr0) | 20260924 |
| laptop | **retiring** (owner, 20260927): its key is off every host and secret; goes back to its owner's network once its seed user is deleted (borrowed workstation `laptop`) | DHCP (.210 seen) | 02:00:00:00:00:01 | bench | 20260923 |

## Networks (declared before they are configured anywhere: rung 6 brief › F, 20260929)

`site/bin/netbox-sync` keeps NetBox's VLANs and prefixes equal to this table. The VLAN tag equals the
subnet's third octet; the main LAN stays untagged (the owner's decision 3, rung 6).

| network | VLAN | subnet | gateway | role | since |
|---|---|---|---|---|---|
| main | untagged | 192.168.1.0/24 | 192.168.1.1 (the firewall, from the rung 6 cut-over 20260929; the router until then) | the site's LAN: every box, the main wifi `seed` | 20260923 |
| guest | 20 | 192.168.20.0/24 | 192.168.20.1 (the firewall, over VLAN 20 through the access point, from rung 6; the router in rung 5) | wifi `seed-guest`: internet only | 20260928 (subnet); 20260929 (VLAN declared) |
| iot | 30 | 192.168.30.0/24 | 192.168.30.1 (the firewall, over VLAN 30 through the access point, from rung 6; the router in rung 5) | wifi `seed-iot`: internet; main may open connections in | 20260928 (subnet); 20260929 (VLAN declared) |

## Recovery media (the recovery pack: runbooks/recovery-order.md)

Two copies. **One is fully off site; the other is on site in a separate location** (a different room,
a fireproof safe). A fireproof safe is rated for paper, not necessarily for electronics, but it
stores the stick safely and survives minor incidents; that's why the other copy is off site. Refresh
**both** copies each time (`STICK_HOST=… tools/recovery-pack.sh`, once per stick).

| copy | medium | serial | label | written | where |
|---|---|---|---|---|---|
| A | USB stick, VendorC "ProductCode", 29.3 GB | SERIAL-PLACEHOLDER | SEEDRECOV (GPT, FAT32) | 20260928 00:09Z (seed-recovery-20260928T0002Z) | taken by the owner, 20260928 |
| B | USB stick, VendorC "ProductCode", 29.3 GB | SERIAL-PLACEHOLDER | SEEDRECOV (GPT, FAT32) | 20260928 00:30Z (seed-recovery-20260928T0024Z) | taken by the owner, 20260928 |

