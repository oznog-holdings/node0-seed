# Rung 6: the dedicated firewall, by phase

**Status: every phase done, 20260929.** The firewall is the site's gateway, and the OpenWrt One is its access point.
- **Phase 0**, the preparation: `evidence/20260929-rung6-0/`.
- **Phase 1**, the install, by the owner at the console: `evidence/20260929-rung6-1.md`.
- **Phase 2**, the firewall configured beside the router: `evidence/20260929-rung6-2/`.
- **Phase 3**, the cut-over, done in four windows (see "The cut-over as it went" below):
  `evidence/20260929-rung6-3-before/` and `evidence/20260929-rung6-3-window1/` to `-window4/`.
- **Phase 4**, after:
  - the fixes made forward: `evidence/20260929-rung6-3-window4/`;
  - the owner's decisions on infra's DNS and the tailnet: `evidence/20260929-rung6-4-owner-decisions/`
    and `evidence/20260929-owner-decisions-2/`;
  - the throughput test: `evidence/20260929-rung6-throughput/`.

Brief: `briefs/rung6.md`. Design: rung-6.md at 3da9785. The phases' steps below are the plan as it was
written; where the cut-over went differently, the section after phase 3 says so.

## What phase 0 settled
- **The ports:**
  - **WAN (upstream) = the 1 GbE port**: Realtek RTL8168h, `re0` in OPNsense, MAC 02:00:00:00:00:01
    (Linux enp1s0). The oldest and best-supported driver goes on the side you can't reach when it
    fails, and 1 GbE is more than the upstream carries.
  - **LAN = the 2.5 GbE port**: Realtek RTL8125B, MAC 02:00:00:00:00:01 (Linux enp2s0). It carries
    the main LAN untagged plus VLANs 20 and 30.
    - **Corrected at phase 1:** the port is **`re1`**, on the Realtek vendor driver. Phase 0 had
      expected a native `rge0`, but FreeBSD 15.1 in OPNsense 26.7 has no `if_rge`, so it runs on the
      driver from the plugin `os-realtek-re`, loaded at boot. Phase 0's reading of an "RTL8125" string
      in the image as native support was wrong (F-RTL8125).
  - The upstream side is static (a fixed address), whatever the chip.
- **The switch drops 802.1Q-tagged frames** (`vlan-test.md`). So, as the brief says, the wiring at
  the cut-over is:

      upstream ── re0 [firewall] re1 ── 2.5G port [access point, the OpenWrt One] 1G port ── switch ── every box

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
- **LAN = `re1`** (MAC ending xx:xx, the 2.5 GbE port, cabled to the switch today).
- **If `re1` isn't in the list, stop there** and tell the builder (the driver is the one thing
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

## Phase 2: beside the router, not yet in the path (the builder): DONE 20260929 (evidence/20260929-rung6-2/)

**The firewall today** (evidence/20260929-rung6-1.md):
- OPNsense 26.7 / FreeBSD 15.1-p1;
- LAN re1 192.168.1.2/24 on the switch; WAN re0 unplugged, DHCP;
- a temporary gateway and DNS 192.168.1.1;
- the web GUI on every interface;
- no rules of the site's yet.

Nothing in the site's path goes through it, and nothing in phase 2 puts anything there.

**How changes are made:**
- over ssh (keys) and OPNsense's own API (configd/`configctl` and the MVC API on the LAN), each read
  back after it's made;
- one step per commit;
- before each step, `tools/fw-backup.sh` (new: `/conf/config.xml` over ssh → age-encrypted to the
  .sops.yaml recipients → `site/firewall/backup/`, like the router's). The file holds password
  hashes, the TSIG secret and the lab's values, so it never lands in the clear.

**The way back from any step:** restore the step's backup (System › Configuration › Backups, or
`/conf/config.xml` from the backup and `configctl` reload), or switch the box off. It's in no path.

1. **Take the phase 1 scaffolding out.**
   - Remove the LAN gateway (LAN_GW, 192.168.1.1) and the system DNS 192.168.1.1, and set DNS
     servers ns1 192.168.1.15 and ns2 192.168.1.16 (same subnet, no gateway needed). NTP from core
     (192.168.1.12) and infra (192.168.1.10).
   - Limit the web GUI to LAN (it listens on every interface), keeping the anti-lockout rule.
   - Disable DHCPv6 and IPv6 on WAN, as at rung 5 (no IPv6 upstream).
   - **Check:** `netstat -rn` has no default route; `sockstat -4l` shows lighttpd on 192.168.1.2
     only; `drill infra.seed.example.com` answers via ns1.
   - **The consequence:** the firewall has no internet until the cut-over, so no firmware or plugin
     updates until then. The versions are pinned as installed: OPNsense 26.7, os-realtek-re 1.0,
     realtek-re-kmod 1102.01.
2. **Declare, then configure, VLANs 20 and 30 on re1** (declared in hosts.md 20260929):
   - GUEST 192.168.20.1/24, IOT 192.168.30.1/24.
   - The router's wifi-only bridges hold the same gateway addresses today. No conflict: tags don't
     cross the switch (phase 0), and the router's guest and IoT never touch a wire.
   - **Check:** `ifconfig re1_vlan20` and `re1_vlan30` up, with those addresses; the main LAN
     unaffected (the watcher, check-dns).
3. **DHCP: Kea DHCPv4** (26.7 ships Kea 3.0.3 with DDNS in its model).
   - **GUEST and IOT:** subnets with pools .100-.249, the gateway and DNS at their own .1, 12 h
     leases. Enabled now: nothing is on those VLANs until the cut-over or the spare-cable test.
   - **Main LAN:** the rung 5 settings (pool .100-.249, option 6 = ns1, ns2, domain `lan`, 12 h,
     the reservations: none today, servers are static per D.04), written but **disabled** until the
     cut-over. Two DHCP servers on the LAN is the failure to avoid.
   - **Check:** Kea running with the main subnet absent from its active config; dhcp-discover from
     core still finds exactly one server (the router).
4. **Leases into Technitium's `lan.seed.example.com`** by RFC 2136 with TSIG, main LAN only (as at rung
   5).
   - A new TSIG key: vault item `technitium ddns firewall`, and Technitium settings `tsigKeys`.
   - `lan.seed.example.com`'s options: `update=UseSpecifiedNetworkACL` for 192.168.1.2 (and .1 from the
     cut-over), with `updateSecurityPolicies` letting that key change only `*.lan.seed.example.com`,
     type A. Added to site/dns/technitium/push.
   - Kea DDNS: forward zone `lan.seed.example.com`, server 192.168.1.15, the key; no reverse zone (no
     lease PTRs, as at rung 5).
   - The router's API token keeps working in parallel until the cut-over, then is revoked (N-item
     at phase 3).
   - **Check:** a scratch update signed with the key succeeds for `x.lan.` and is refused for
     `x.seed.example.com` and for the reverse zone (from the agent box with the key in a pipe); the
     real test waits for a lease (step 7).
5. **The rules** (the rung 5 policy):
   - **LAN:** pass all.
   - **GUEST:** pass DHCP to self, pass DNS to GUEST address:53. Reject to 10/8, 172.16/12,
     192.168/16, 169.254/16 and 100.64/10 (the tailnet), and to the firewall's own other addresses.
     Pass to any (the internet).
   - **IOT:** the same. LAN → IOT is covered by LAN's pass; IOT → LAN is rejected by the private
     block.
   - **WAN:** "block private networks" OFF. The upstream is itself private (double NAT); left on,
     it would block the lab's `fixture:` sources. "Block bogons" on.
   - **Outbound NAT:** automatic (masquerade every internal network on WAN), as the router does.
   - **The two `fixture:` rules** recreated on WAN under the same names, from the router's live
     config, read at the time and not into the repo (the lab's).
   - **Check:** the rule list against the router's (uci show firewall), rule by rule; pfctl -sr
     shows each.
6. **DNS for guest and IoT:** Unbound listening on 192.168.20.1 and 192.168.30.1 only (and
   127.0.0.1), forwarding to Quad9/Cloudflare over DoT, private answers dropped (rebind
   protection), no site names; not on the LAN address (main uses ns1, ns2).
   - **Check:** from the firewall, `drill @192.168.20.1 vault.seed.example.com` gives no answer, and
     `example.com` answers once the WAN is up (at the cut-over).
7. **The spare-cable test** (brief: before the cut-over). The switch drops tags, so a tagged test
   client must be on a cable straight to re1, and re1 is the firewall's only LAN port.
   **Options for the orchestrator and the owner:**
   - (a) during a short window, the owner moves re1's cable from the switch to a test laptop that
     can tag (the firewall then unreachable from the site until it's moved back); or
   - (b) do the tagged checks as the first checks of phase 3, through the access point, with the
     way back ready.
   - Either way the untagged half (the main LAN rules, Kea disabled) is tested now.
8. **The configuration into the repository, and drift:**
   - infra's daily device-config job also pulls `/conf/config.xml` over ssh, with a forced-command
     key on the firewall (its own entry in root's authorized_keys, `command=` a small export script
     that redacts password hashes, keys, the TSIG secret, the WAN addresses and the `fixture:`
     rules on the firewall, as the router's export does);
   - the redacted copy is committed to seed/device-configs;
   - a normal form is compared with `site/firewall/config.expected.xml` (the repository's), with
     FirewallConfigDrift alerting on a difference.
   - **Check:** a deliberate change is caught and alerted, then reverted.
9. **Monitoring:** node_exporter on the firewall (the `os-node_exporter` plugin needs the internet:
   installed at the cut-over), and blackbox ping of 192.168.1.2 now; TargetDown covers it.

**Waiting for the owner or orchestrator before or during phase 2:**
- **The WAN's static values** (the upstream's address, prefix, gateway), which the owner holds.
  Either the owner sets them on re0 now (the cable stays unplugged), or at the cut-over.
- **The spare-cable option** (7a or 7b).
- **The live system's stick** (Samsung "Flash Drive FIT") stays in Larkbox one on purpose (the owner's
  decision 3: for a future re-provision; not the default boot).
- **The vault items:** `technitium ddns firewall` (made in step 4); `opnsense root` exists.

## Phase 3: the cut-over (the builder, the owner and the orchestrator, in a window): THE PLAN

The ports: the router (OpenWrt One) has **eth0**, 2.5 GbE (its WAN today, to the upstream), and
**eth1**, 1 GbE (its LAN today, to the switch). Afterwards:

    upstream ── re0 [firewall] re1 ═══ trunk: untagged main + VLAN 20 + VLAN 30 ═══ eth0 [access point] eth1 ── switch ── every box

### Before the window (the builder; nothing in the path moves)
1. **Stage the access point's configuration in the repository**, not applied: `site/router/config.ap/`,
   the router's UCI in config-tool's format, reviewed and committed.
   - **network:**
     - `br-lan` = eth0 (untagged) + eth1, `lan` static **192.168.1.4/24**, gateway 192.168.1.1, DNS
       192.168.1.15, 192.168.1.16 (192.168.1.4 declared first in hosts.md, the zone and NetBox as
       `ap`);
     - `br-guest` = eth0.20 + the guest wifi, and `br-iot` = eth0.30 + the IoT wifi, both
       **proto none** (no address, no routing).
   - **dhcp:** every pool `ignore`, dnsmasq and odhcpd disabled at boot.
   - **firewall:** the service disabled at boot (the bridge only forwards).
   - **wireless:** `seed` → lan, `seed-guest` → guest bridge, `seed-iot` → IoT bridge (client
     isolation kept).
   - **The lease hook** (`90-seed-ddns`) and its token removed from the files (Kea registers leases
     now).
   - **The lab's sections:** the WAN (`network.wan`, `wan6`) must be disabled, because eth0 joins
     br-lan. **That is the one exact change to the lab's sections**, and it needs the orchestrator's
     yes in writing before the window (ANNEX: only a change the rung plan states exactly): set
     `network.wan.disabled='1'` (wan6 is already disabled).
   - The `fixture:` rules stay in the router's firewall config, inert (the service is off). The
     firewall has its own copies under the same names.
   - config-tool gains `apply --ap`, which applies config.ap/ and keeps the 120 s rollback,
     confirming at 192.168.1.4.
2. **The agent box's wifi as the test client** (the owner's decision 4), promoted before the window:
   - a NixOS unit `seed-wifi-test` (root, oneshot) that creates a network namespace `wtest`, moves
     the wifi card's phy into it (`iw phy <phy> set netns name wtest`), and for each of `seed`,
     `seed-guest`, `seed-iot` in turn runs wpa_supplicant and a DHCP client **inside the namespace
     only** and the containment checks (the rows of tools/wifi-test.sh). It writes
     `/var/lib/seed-wifi-test/<time>.txt`, then deletes the namespace (the phy returns, the card
     stays down).
   - The passphrases come from sops (`nixos/secrets/agent.yaml`: `wifi_seed`, `wifi_guest`,
     `wifi_iot`, the same values as the vault items, compared by hash).
   - A polkit rule lets `agent` start only that unit.
   - **The wired link isn't touched:** the wifi's addresses, routes and DNS exist only in `wtest`;
     enp2s0, its routes and its resolver stay as they are.
   - The LAN-side rows (LAN → IoT allowed, LAN → guest not) run from the wired side against the
     client's address in the namespace.
   - **Rehearsed before the window** against today's router (radios on for the test only, with the
     owner's yes; off after, unless they decide otherwise): the same 3 networks and rows as on
     20260928.
3. **The owner:**
   - puts the WAN's static values on re0 and turns "Block private networks" off (the WAN is theirs);
   - has a way to reach the upstream's ARP refresh;
   - the orchestrator pauses the dead-man (`tools/healthchecks-window.sh pause`).
4. **The builder, "before" records:**
   - `tools/router-backup.sh`; `site/router/config-tool check` clean;
   - the firewall's export equal to config.expected.xml;
   - check-after-reboot, check-dns and the watcher green;
   - the containment matrix on the rung 5 edge (step 2's test).

### In the window (in this order)
**Run by one script (the owner's decision, 20260929: an agent must not depend on the path it is
changing).**
- **Start:** `tools/rung6-cutover.sh`, on the agent box, before the owner unplugs anything. It
  detaches, needs no internet and talks only to the router, the firewall, core and the site vault
  over the LAN.
- **Log:** `/var/tmp/seed-cutover/latest.log`, world-readable
  (`ssh agent@192.168.1.11 cat /var/tmp/seed-cutover/latest.log`). A `WAIT` line tells the owner
  when to unplug and when to recable.
- **The way back runs by itself** on any failed check or time limit (unplug 20 min, recable 20 min,
  the WAN gateway 5 min). It ends with one `OWNER:` line.
- **Before starting it:** `tools/rung6-cutover.sh --dry-run` (every precondition; nothing changes).
- **Window 1 (20260929 18:53Z) failed safe:** the router's reload never ran (busybox has no
  `nohup`). The rollback and the way back worked; the internet was down 6 min 48 s. Fixed with
  `setsid` and a start marker, and the wait now fits inside the rollback window (180 s when the
  address moves). The dry run checks that the router and the firewall can run detached processes
  (evidence/20260929-rung6-3-window1/).
- **The firewall's half:** site/firewall/seed-cutover-fw (copied to /root at step 3).
- **After the internet returns:** the builder rejoins, reads the log and runs the checks below that
  need the internet (the tailnet, the example.com rows, the firewall's own internet, the no-old-role
  sweep).

| # | who | step | check | internet |
|---|---|---|---|---|
| 1 | owner | **Unplug the upstream cable from the router's eth0.** (It must be out before eth0 joins the LAN bridge: bridging the lab's upstream into the LAN is the failure to avoid.) | the router's eth0 has no carrier | **down from here (t0)** |
| 2 | builder | **The router becomes the access point:** `config-tool apply --ap` (config.ap/ with the one WAN change; the 120 s rollback). | confirmed at 192.168.1.4; `uci show` equals config.ap; dnsmasq, odhcpd and firewall not running; nothing on :53 or :67 | down |
| 3 | builder | **The firewall takes the gateway:** LAN re1 192.168.1.2 → **192.168.1.1/24**; Kea's interfaces + lan (main DHCP on); `fw` → .1 in hosts.md, the zone, NetBox, device-config.sh, targets/tcp.yaml, known_hosts. | ssh root@192.168.1.1; dhcp-discover from core: **one server, the firewall**, DNS .15, .16 | down |
| 4 | owner | **Recable:** firewall re1 → router **eth0**; upstream → firewall **re0**. The router's eth1 stays on the switch. | re0 and re1 carrier; the router's eth0 at 2500 | down |
| 5 | owner | **The upstream step:** have the upstream's ARP entry for the internet-side address refreshed (it moved from the router's MAC to the firewall's re0). | the firewall pings its WAN gateway (checked by the owner, whose values they are) | **back (t1)** |
| 6 | builder | **Checks, straight after** (below). | all green | up |

**The checks after step 5:**
- **Every box answers;** check-after-reboot; check-dns; the watcher.
- **The tailnet:** the agent box's subnet route; site2's pull through the guard; `tailscale ping`.
- **The firewall's own internet:** Unbound's `example.com` for guest and IoT; node_exporter plugin
  installed; the export and drift.
- **The tagged checks, first thing** (step 7 of phase 2, the owner's decision 2) with the agent
  box's wifi (`seed-wifi-test`) on each network:
  - **seed:** a lease from the firewall in 192.168.1.0/24, **its name in `lan.seed.example.com`** (the
    Kea DDNS test); site names resolve.
  - **seed-guest:** a lease from 192.168.20.0/24 via VLAN 20, DNS at 192.168.20.1, the internet;
    refused: LAN, the firewall's other addresses, the tailnet, site names.
  - **seed-iot:** the same via VLAN 30; LAN → the client allowed, the client → LAN refused.
  - **Only the firewall answers** DHCP and DNS on each (the access point has none: the classic
    leftover-resolver trap).
- **No rule anywhere still names the router's old role:**
  - the repo's config.ap;
  - the firewall's export;
  - DHCP option 6 and Kea;
  - the dns.yaml/tcp.yaml targets;
  - the hotplug hook gone;
  - the router's API token (user dhcp-router) revoked in Technitium.

**Internet-down estimate:** steps 1 to 5, about **10 to 15 minutes** if each goes first time:
- step 2 about 2 min (apply, confirm);
- step 3 about 2 min;
- step 4 about 2 min;
- step 5 is the unknown: it depends on the upstream's ARP timer, or how fast the owner can have it
  refreshed.

The LAN between the boxes (the switch) stays up throughout, except for a few seconds when step 2
restarts the router's bridge; DNS (ns1, ns2) and the NAS services don't depend on the edge. Budget
**30 minutes**, including one way back.

### The way back (any step, any time in the window)
The order matters: the firewall gives up 192.168.1.1 **before** the router takes it back, so there
are never two gateways on one address.
1. **The firewall back beside the router:** re1 192.168.1.1 → 192.168.1.2 and Kea's `lan` off (step 3
   reversed, or its configuration history).
   **Check:** dhcp-discover finds no server (none for a minute is fine).
2. **Cables:** the upstream cable back into the router's **eth0**; the firewall's re1 back onto the
   switch.
3. **The router back to rung 5:** `site/router/config-tool apply` with site/router/config/
   (unchanged since rung 5), which re-enables the WAN, DHCP, dnsmasq and the firewall. The 120 s
   rollback confirms at 192.168.1.1.
4. **The owner** has the upstream's ARP entry refreshed again (the address is back on the router's
   MAC).
5. **Check:** dhcp-discover finds only the router (DNS .15, .16); the internet; check-after-reboot;
   check-dns; the watcher.

## The cut-over as it went (20260929)
The window ran as one script, `tools/rung6-cutover.sh`, on the agent box. It needs no internet, keeps a log
on the LAN, and runs the way back by itself (the owner's decision: an agent must not depend on the path it
is changing). It took four windows.

| window | UTC | what happened | the way back |
|---|---|---|---|
| 1 | 18:53 to 19:06 | **The access point's reload never started.** `config-tool apply --ap` imported the configuration and started `reload_config` in the background with `nohup`, which the router's busybox doesn't have; the error went to /dev/null. Nothing ever held 192.168.1.4. | The router's own 120 s rollback restored rung 5; the script logged the failure and one line for the owner. The internet was down 6 min 48 s. |
| 2 | 19:32 to 19:54 | Steps 2 and 3 worked: the access point at .4, the firewall at .1. The recabling was right, and the owner had the internet through the firewall. **Step 4 failed falsely:** it pinged the WAN gateway, and the upstream allows the site's address only DNS and NTP to its own addresses. Ping never answers. | Ran cleanly: the firewall back to .2 with main DHCP off, then the router to rung 5. The owner recabled. |
| 3 | 19:58 to 20:19 | Steps 1 to 3 worked. **The firewall's confirmation met an early recabling:** the owner moved the LAN cable during step 3, and the single ssh confirmation fell in the 9 s the port was down. | The way back raced: it waited 150 s for the firewall against the firewall's own 180 s rollback, then correctly refused to move the router while .1 might be taken, and stopped for a person. The orchestrator finished it from a laptop on the switch. |
| 4 | 20:39 to 20:45 | **The cut-over.** Unplug 20:42:00. The access point confirmed at .4 at 20:42:53, the firewall at .1 at 20:43:41. Recabled 20:44:38 (the trunk at 2.5 Gb/s). The gateway's DNS port answered at 20:44:57. The offline checks passed to 20:45:23. | Not needed. |

**The fixes between windows:**
- **After window 1:** the detached reload uses `setsid` and a start marker that config-tool must see before
  it lets the session go. The rollback window is 180 s when the address moves, and the wait always ends
  inside it. The dry run checks that the router and the firewall can run a process that outlives its ssh
  session.
- **After window 2:** the WAN check is a TCP connection to the gateway's port 53 from the firewall's WAN
  address, which can only succeed once the upstream has learned the firewall's MAC. The ping is kept as
  information. Proven first from the router, which held the WAN address then.
- **After window 3:**
  - every check over the LAN retries through short link losses;
  - the confirmation retries until 30 s before the firewall's own deadline;
  - every wait in the way back outlasts the rollback it waits for;
  - the way back returns the router to rung 5 by itself whenever 192.168.1.1 is proven free;
  - the firewall's move was rehearsed on a spare address (.3), with and without confirmation.

**The owner's decision in window 4: fail forward.** Once the internet was up, a check that wasn't critical
would be fixed forward, not rolled back. The orchestrator stopped the script before the wifi checks. Both
changes had been confirmed, so nothing was pending.

**Fixed forward, after window 4:**
- **The wifi test in cut-over mode** (the agent box's wifi on all three networks, through VLANs 20 and 30)
  found two faults, both fixed:
  - Lease names registered by the old router's hook blocked Kea's dynamic DNS updates (Kea won't replace
    a name it doesn't own). The two stale records were removed.
  - The firewall's default "allow LAN to any" let the LAN into the guest network; rung 5 never allowed
    that. A LAN rule now rejects LAN → guest ahead of it.

  Rerun: 0 fails.
- **infra lost DNS for 15 minutes:** its resolver had been the old router's address, and the firewall
  serves no DNS on the LAN.
  - First moved to ns1.
  - Then, by the owner's decision, to ns2 (itself) first and ns1 second, through Unraid's "Host access to
    custom networks", with `options timeout:1 attempts:2` set at every boot.
  - Proven with each DNS server stopped: with ns2 down a lookup takes about 1 s.
- **Re-pointed:**
  - the drift job (the router at .4, the firewall at .1);
  - the firewall's probe and the DNS names (`router` = .4, `fw` = .1);
  - the lan zone, which accepts updates from .1 only;
  - NetBox, hosts.md and config-tool's defaults (the access point).
- **The old router's lease-hook token** is revoked, and the hook removed.
- **The tailnet:** infra is the primary subnet router and the agent box the standby (the owner's decision).

**Throughput** (`evidence/20260929-rung6-throughput/`: iperf3, 30 s, 1 and 4 streams, both directions):

| path | result | load |
|---|---|---|
| LAN → the access point's bridge → the firewall itself | **937 to 941 Mbit/s**, the 1 GbE line rate, every test | the access point's busiest core at ~80%; the firewall 74 to 88% idle |
| LAN → the firewall (routed) → VLAN 30 → wifi | 477 to 491 Mbit/s, bounded by the wifi link (one stream, 600 Mbit/s PHY) | the firewall 92 to 94% idle |
| the internet through the firewall's NAT | 895 Mbit/s down and 577 up with 4 streams, bounded by the provider | the firewall 89 to 90% idle |

**The answer:** yes, the configuration carries 1 Gbit/s through the access point and the firewall. The
access point's software bridge is the tighter of the two. The firewall's one serial resource is its LAN
driver's single task-queue thread: 26 to 50% of a core at ~940 Mbit/s.

## Phase 4: after
- **The power test:** the orchestrator cuts plug3, restores it, and times the firewall's return to
  forwarding (ping through it from the LAN, and the tailnet from site2).
- **A day of the watcher** through the new edge; then rung-6's measurements for the page.
