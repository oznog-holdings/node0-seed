# Rung 6: the dedicated firewall, by phase

**Status (20260929):** phase 0 done (`evidence/20260929-rung6-0/`); phase 1 waits for the owner at
the bench. Brief: `briefs/rung6.md`. Design: rung-6.md at 3da9785.

## What phase 0 settled
- **The ports:**
  - **WAN (upstream) = the 1 GbE port**: Realtek RTL8168h, `re0` in OPNsense, MAC 02:00:00:00:00:01
    (Linux enp1s0). The oldest and best-supported driver goes on the side you can't reach when it
    fails, and 1 GbE is more than the upstream carries.
  - **LAN = the 2.5 GbE port**: Realtek RTL8125B, `rge0` in OPNsense (FreeBSD 15.1's driver),
    MAC 02:00:00:00:00:01 (Linux enp2s0). It carries the main LAN untagged plus VLANs 20 and 30.
  - The upstream side is static (a fixed address), whatever the chip.
- **The switch drops 802.1Q-tagged frames** (`vlan-test.md`). So, as the brief says, the wiring at
  the cut-over is:

      upstream ── re0 [firewall] rge0 ── 2.5G port [access point, the OpenWrt One] 1G port ── switch ── every box

  The trunk (untagged main, tagged 20 and 30) runs only on the firewall ↔ access point cable. The
  main LAN reaches the switch through the access point's bridge.
- **The installer:** OPNsense 26.7 vga, verified by checksum, signature and a key from three
  mirrors, written to the SanDisk stick (serial SERIAL-PLACEHOLDER) and read back equal (sha256
  9017eab1…).
- **Addresses declared before use** (hosts.md, the zone, NetBox):
  - VLAN 20 → 192.168.20.0/24, VLAN 30 → 192.168.30.0/24;
  - `fw` = 192.168.1.2 as the firewall's management address until the cut-over.
- **Power:** Larkbox one powers on by itself after AC loss (the orchestrator cycled plug3 at about
  13:50Z on 20260929; it came back into the live system unattended).

## Phase 1: the owner at the console (a checklist in plain words)
Bring: a keyboard and screen for Larkbox one, and access to the site vault (item `opnsense root`).

**Before you start:**
- The live Linux on Larkbox one runs from memory. The builder's key there disappears the moment
  the box is switched off. Nothing needs it after this install; if the live system is booted again
  for any reason, the key must be added again.
- The router, the switch and every box stay as they are today. Larkbox one isn't in any path yet.

**1. Power (the owner's decision 1).**
- Larkbox one stays on plug3 (a UPS battery outlet).
- Move **the switch and the router** from the wall outlet to UPS battery outlets. Each move is a
  short outage for the whole LAN: do the switch first, then the router, and tell the orchestrator
  the times.

**2. Firmware.** Switch Larkbox one on and press **Del** (or Esc) for its setup screen.
- **Power on after AC loss:** already works (it came back by itself on 20260929). Check it's still
  set to "Power On" / "Last State".
- **Clock:** set to **UTC** (now, in UTC: the time the builder gives you).
- **Secure Boot:** off (FreeBSD's loader isn't signed for it).
- **Boot entries:** remove any old ones you can (the Unraid stick, Windows Boot Manager, NixOS). Put
  the **SanDisk stick first** for this boot only (or use the one-time boot menu, F7).
- Save and exit.

**3. The installer.** It boots from the SanDisk stick.
- At the login prompt: user `installer`, password `opnsense`.
- Keymap: your keyboard's.
- Choose **Install (ZFS)** → stripe → the disk **AirDisk 512GB SSD** (about 477 G). **Not** the
  SanDisk (57 G), and not a "Flash Drive FIT" if one is plugged in.
- Root password: the value of vault item **`opnsense root`**.
- When it says it's done: **remove the SanDisk stick**, label it "OPNsense 26.7 installer", keep it
  on site, and reboot.

**4. Interfaces, at the console menu after the first boot.** Option **1) Assign interfaces**:
- VLANs now? **No** (phase 2).
- **WAN = `re0`** (MAC ending xx:xx, the 1 GbE port, the one without a cable today).
- **LAN = `rge0`** (MAC ending xx:xx, the 2.5 GbE port, cabled to the switch today).
- **If `rge0` isn't in the list, stop there** and tell the builder (the driver is the one thing
  phase 0 couldn't prove).

**5. Addresses.** Option **2) Set interface IP address**:
- **LAN:** static **192.168.1.2/24**, no upstream gateway, **DHCP server on LAN: NO** (the router
  still serves DHCP; two DHCP servers is the failure to avoid). IPv6: none. Web GUI over HTTPS: yes.
- **WAN:** static, **the same address, prefix and gateway as the router's internet side**. The owner
  has these; they aren't in the site's records. **Leave the WAN port unplugged** until the cut-over:
  the router still holds that address upstream.

**6. The builder's access.** In the web GUI (https://192.168.1.2, user root):
- **System › Access › Users › root:** authorised keys = the builder's key
  `ssh-ed25519 AAAA...REPLACE-WITH-YOUR-PUBLIC-KEY
  and the orchestrator's (the lab fixture, ANNEX).
- **System › Settings › Administration:** Secure Shell on, root login allowed, **password login
  off**, listen on LAN only.

**7. Check, and tell the builder.**
- From the agent box: `ssh root@192.168.1.2` works (the builder checks).
- Then the orchestrator cycles plug3 once more: OPNsense comes back by itself on the internal SSD,
  at 192.168.1.2.

**Way back from phase 1:** nothing in the path changed; Larkbox one can simply be switched off. The
SanDisk stick reinstalls.

## Phase 2: beside the router, not yet in the path (the builder)
Each step is followed by its check; the way back from all of phase 2 is to switch Larkbox one off
(it isn't in any path).
1. **VLANs 20 and 30 on `rge0`.** Interfaces GUEST 192.168.20.1/24 and IOT 192.168.30.1/24 (the
   same gateways the router has today). **Check:** interface status; nothing else changes on the
   LAN.
2. **DHCP on each network,** with the repository's reservations (site/router/config/dhcp is the
   source) and dynamic DNS into Technitium's `lan.seed.example.com` (a new token scoped to that zone,
   like the router's). Main LAN DHCP stays **disabled** until the cut-over. **Check:** on a spare
   cable (below), a lease on each network, and its name resolves in `lan.`.
3. **The rules,** the same as rung 5:
   - main: everything it had;
   - guest: internet only, DHCP and DNS at its own gateway;
   - IoT: internet only, and main may open connections into IoT, never the reverse;
   - the private and tailnet ranges refused beyond the WAN, as the router does.
   The two `fixture:` rules recreated **under the same names** from the router's (the lab's; read
   from the router, never into the repo).
   **Check:** the rule list against the router's, rule by rule.
4. **DNS for guest and IoT:** a resolver at each network's gateway that forwards only to the
   internet (no site names), as the router's second dnsmasq did. **Check:** `vault.seed.example.com`
   doesn't resolve from guest.
5. **The configuration from the repository:**
   - a daily export (config.xml, secrets redacted on the firewall) into seed/device-configs, beside
     the router's;
   - a drift alert against the repository's copy, as RouterConfigDrift does;
   - the firewall added to monitoring.
   **Check:** a deliberate change is caught.
6. **The spare-cable test:** a laptop or Larkbox two's second port on `rge0`, tagged 20 and 30, then
   untagged. Each network gets a lease, its DNS answers, and the containment matrix holds (the same
   rows as tools/wifi-test.sh). Only then is phase 3 scheduled.

## Phase 3: the cut-over (the builder and the owner, with a window)
**Before:**
- the dead-man paused;
- `tools/router-backup.sh`, and `site/router/config-tool check` clean;
- the containment matrix run on the rung 5 edge (the "before" half of rung-6's check);
- the firewall's config exported.

**The change:**
1. **The router becomes a dumb access point**, from the repository (a new `site/router/config`
   commit):
   - DHCP off on every network, dnsmasq off, firewall off (or allow-all bridged);
   - its main, guest and IoT wifi bridged to the untagged, VLAN 20 and VLAN 30 sides of its 2.5G
     port;
   - its LAN address 192.168.1.4 for management (declared first).
   **Check:** from each wifi network, only the firewall answers DHCP and DNS (dhcp-discover on each;
   the classic trap is a leftover resolver on the access point).
2. **The cables** (the owner):
   - the upstream cable moves from the router's 2.5G port to the firewall's `re0`;
   - the router's 2.5G port connects to the firewall's `rge0`;
   - the switch stays on the router's 1G port.
3. **The firewall takes the LAN gateway:**
   - LAN 192.168.1.1/24;
   - main DHCP on, with the rung 5 settings: pool .100-.249, option 6 = ns1, ns2, the reservations;
   - `fw` in hosts.md, the zone and NetBox moved to .1, and .2 freed.
4. **The owner's upstream step:** have the upstream's ARP entry for the internet-side address
   refreshed. The address moved from the router's MAC to the firewall's, and a stale entry upstream
   keeps sending traffic to the old box.
5. **Checks, straight after:**
   - every box answers;
   - `site/bin/check-dns`, `check-after-reboot`, the watcher;
   - the tailnet: the agent box's subnet route, site2's pull through the guard;
   - the three wifi networks each get a lease from the firewall;
   - the containment matrix from each network (the "after" half);
   - no rule anywhere still names the router's old role (the repo, the firewall's export, the
     router's config).

**Way back:**
- apply the router's rung 5 configuration: `git revert` the access-point commit, then
  `site/router/config-tool apply`;
- move the upstream cable back to the router's 2.5G port;
- the owner has the upstream ARP entry refreshed again;
- DHCP and DNS are as at rung 5 at once.

## Phase 4: after
- **The power test:** the orchestrator cuts plug3, restores it, and times the firewall's return to
  forwarding (ping through it from the LAN, and the tailnet from site2).
- **A day of the watcher** through the new edge; then rung-6's measurements for the page.
