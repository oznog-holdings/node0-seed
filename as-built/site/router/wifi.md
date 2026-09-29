# The router's wifi: three networks (R1.24)

The owner's decision of 20260927: three networks on the router, configured, tested and documented,
then switched off with the configuration kept. Built and tested 20260928. **Today the radios are
off.** `tools/router-wifi.sh on` brings all three back; `off` switches them off again.

## What there is

| network | SSID | segment | clients get | may reach | may not reach |
|---|---|---|---|---|---|
| main | `seed` | the seed LAN (bridged into br-lan) | the LAN's DHCP, AdGuard as DNS | everything a wired LAN box may, including the site's names | what the LAN can't: the upstream's containment |
| guest | `seed-guest` | 192.168.20.0/24, br-guest (wifi only) | the router's DHCP (2 h leases), the router as DNS | the internet | the LAN, the router (except DHCP and DNS), IoT, every other guest, any private, link-local or tailnet address |
| IoT | `seed-iot` | 192.168.30.0/24, br-iot (wifi only) | the router's DHCP (12 h leases), the router as DNS | the internet | the same as guest. The LAN may open connections *into* IoT; IoT may open none into the LAN |

- **All three on the 5 GHz radio** (channel 36, 80 MHz, country US), WPA2/WPA3 mixed (`sae-mixed`,
  protected management frames optional). The 2.4 GHz radio stays off with no network on it.
- **The passphrases** are in Vaultwarden (`wifi seed`, `wifi seed-guest`, `wifi seed-iot`; the
  username is the SSID). They go to the router by stdin, never on a command line. The router's
  config export (`seed-config-export`) redacts them.
- **The configuration** is written by `tools/router-wifi.sh apply`. It is idempotent, and every
  section is named, so it is easy to find:
  - wifi: `wifi_*`;
  - network: `br_guest`, `br_iot`, `guest`, `iot`;
  - DHCP: `main`, `wifi`, `guest`, `iot`;
  - firewall: `zone_*`, `fwd_*`, `seed_wifi_*`.


## The options, and what we chose

**Segments without VLANs.** design › Decisions says "no VLANs" at this rung. Guest and IoT are
therefore routed segments whose bridges hold only their wifi interface. Nothing is tagged on a
wire, and a wired IoT device would need a port of its own later (rung 5's VLAN step).

**Guest.** A guest needs the internet and nothing else. The router hands out addresses and answers
DNS. The firewall's `guest` zone rejects everything else:
- input: only DHCP, and DNS at 192.168.20.1;
- forwarding: only to the WAN.

Clients are isolated at the access point (`isolate=1`). On OpenWrt that means `ap_isolate` in
hostapd, plus hairpin off on the bridge port. The bridge has no other port, so a guest's frames can
reach only the router.

**IoT: what the LAN may reach in it.** The options were:
- **(a) nothing:** IoT fully one-way, like guest;
- **(b) everything, initiated from the LAN:** chosen;
- **(c) named LAN hosts to named ports.**

We chose (b):
- **Why:** the reason to have IoT devices at all is to control them from the LAN (a phone on
  `seed`, later a controller box). Replies come back through the connection tracking, and an IoT
  device can never open a connection into the LAN.
- **What that costs:** a compromised IoT device can answer, and lie to, a LAN client that talks to
  it. It can't reach one that doesn't.
- **When to narrow it to (c):** when there is a real controller to name. The change is one
  forwarding (`fwd_lan_iot`) replaced by rules.
- **IoT clients are isolated from each other too.** A compromised device can't scan its
  neighbours. Devices that must talk to each other locally (casting, hubs) would need
  `wireless.wifi_iot.isolate=0`.

**DNS for guest and IoT.** The router's main dnsmasq forwards the site's zone (`seed.example.com`)
to AdGuard on core and infra. That would be a path from guest and IoT into LAN services, and it
would tell them the site's names.
- A second dnsmasq instance (`wifi`) serves only br-guest and br-iot, and forwards only to the
  WAN's resolver.
- It has no site zone and no hosts file, and rebind protection drops private answers.
- The firewall accepts DNS from each segment only at that segment's own router address, not at
  192.168.1.1 or the WAN address, where the main dnsmasq listens. The first version accepted
  port 53 at any router address; I narrowed it before the tests.

**Private addresses beyond the WAN.** Guest and IoT leave through the WAN, masqueraded exactly as
the LAN is (`srcnat_wan`: one masquerade for all).
The router also rejects, for both, every destination in:
- 10/8, 172.16/12 and 192.168/16;
- 100.64/10 (the tailnet);
- 169.254/16.

That's belt and braces, and it means a guest gets a fast "refused"

**Encryption.** WPA3-only (`sae`) would exclude many IoT devices and older phones. Mixed mode lets
WPA3 clients use SAE with management-frame protection, and WPA2-only devices still join (tested).

**The band.** The router's 5 GHz radio carries all three networks, as asked. Many IoT devices are
2.4 GHz only. For them, the same `seed-iot` can be added on `radio0`: one wifi-iface with
`device=radio0`, the rest the same. It's not done, since nothing here needs it yet.

## The tests (20260928, evidence/20260928-wifi/)

**The client.** Larkbox one (nixos@192.168.1.128, a live installer), using its Intel wifi
(`wlp0s20f3`), driven by `site/router/wifi-client.sh`:
- the wifi phy is moved into its own network namespace, so the wired link (how we reach the box)
  never changes;
- the wired link is checked before and after every network: always up;
- it joins each network in turn: WPA3-SAE with PMF required, and IoT once more with WPA2-PSK.

`tools/wifi-test.sh` runs everything. **Result: 93 checks, 0 failed** (tests.txt). A first run
had 6 failures, all mistakes in the harness (tests-first-run-harness-bugs.txt).

| | main | guest | IoT |
|---|---|---|---|
| associates, 5 GHz, SAE, CCMP | yes | yes | yes (and WPA2-PSK) |
| DHCP: address, router, DNS | 192.168.1.x, .1, AdGuard .12 and .10 | 192.168.20.x, .1, .1 | 192.168.30.x, .1, .1 |
| DNS (example.com), internet (https 200) | yes, yes | yes, yes | yes, yes |
| the site's names (vault.seed.example.com) | 192.168.1.10, https 200 | NXDOMAIN; no answer from 192.168.1.1 or 192.0.2.4 | the same as guest |
| the LAN (infra :443, agent :22, core :53, router :22/:443), the upstream gateway | reached (it's the LAN) | refused | refused |
| the router's own address on the segment, :22/:80/:443 | - | refused | refused |
| the other segment | - | refused | refused |
| from the LAN (the agent box) to the client | - | not open | **open** (as chosen) |
| the home network above the router, and the tailnet | not reached | refused at the router | refused at the router |

**Other guests: tested on the access point's side only.** The test card can't be two stations at
once: its driver allows one managed interface, and wpa_supplicant turns a second (P2P-client)
interface into a managed one and fails. So the isolation evidence is the AP's side:
- hostapd runs `ap_isolate=1` on guest and IoT;
- their bridge ports have hairpin off;
- each bridge has one port.

A station's frames can therefore go only to the router, and the router doesn't forward within a
segment (guest → guest isn't among the zone's forwardings). A two-client test is two minutes with
a phone and the Larkbox, both on `seed-guest`: the phone's address, from `/tmp/dhcp.leases.wifi`
on the router, must not answer `arping` or `ping` from the Larkbox.

## Operating it

```
tools/router-wifi.sh status        # radios, SSIDs, running access points
tools/router-wifi.sh on            # 5 GHz on: all three networks
tools/router-wifi.sh off           # both radios off; configuration and passphrases stay
tools/router-wifi.sh apply         # (re)write the configuration from this repo
tools/wifi-test.sh                 # the tests above (needs the radio on and Larkbox one on the LAN)
tools/router-fixture-hash.sh       # before and after any change: must not move
```

- **Rotating a passphrase:** change the vault item, then run `apply`.
- **The pre-change config** (20260928) is on the router: `/root/seed-backup-20260928-wifi/`.
