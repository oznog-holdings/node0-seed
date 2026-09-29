# Data

What we measured on the bench from 20260923 to 20260928, with the conditions each figure was
taken under. Every row gives its conditions, so you can compare your own box to it.

## Memory (rung 1)

Host: the infrastructure box (a TerraMaster F8 SSD Plus with an Intel i3-N305). "16 GB" is
the same box limited on the boot line to match a stock 16 GB box of the same model
(`mem=18G`, MemTotal within 0.03% of the real one). All readings at rest, at least 30
minutes after boot, with every rung 1 service running. All four rows were measured on
20260924, the 8 and 16 GiB rows last. The VM's share is its resident memory on the host.

| Host | Agent VM | Host available | ZFS cache | Host memory the VM holds |
|---|---|---|---|---|
| 16 GB | 4 GiB | 5.5 GB | 2.1 GiB | not recorded |
| 48 GB | 4 GiB | 42.2 GB | 0.85 GiB (cold) | 1.14 GiB |
| 48 GB | 8 GiB | 41.3 GB | 2.5 GiB | 1.15 GiB |
| 48 GB | 16 GiB | 41.2 GB | 2.5 GiB | 1.26 GiB |

- Unraid plus the rung 1 services: a steady 3.7 to 3.9 GiB.
- A VM that had worked for hours held 4.34 GiB of a 4 GiB allocation: the host keeps what the
  guest has touched.
- "Cold" means the cache had not yet been warmed by a nightly cycle. All these readings are
  cold; only the one where it matters is marked.
- Not yet measured: a working day with the agent busy; a warm cache after a nightly cycle; the
  cache during a scrub.

## Storage (rung 1)

| What | Figure | Conditions |
|---|---|---|
| Burn-in fill | 790 GB, 80% of usable | 20260923; raidz1 of three 512 GB NVMe (two PCIe 4 SK hynix, one KIOXIA), random data |
| Scrub of that fill | 11 min 18 s, 0 errors | same pool, idle otherwise |
| Agent box NVMe write | 16 GiB in 52 s with fsync, read back hash-equal | a 512 GB NVMe in a Chuwi LarkBox X |

## Recovery times

| Event | Figure | Conditions |
|---|---|---|
| infra reboot to every service answering | about 2 min | 20260924; array auto start on; 16 containers and the agent VM |
| infra powered off, power cut and restored, to every service answering | 1 min 39 s from power return | 20260924; firmware set to power on after AC loss |
| the same, after an accidental press of the power button (a clean shutdown, 20260927) | 16 containers and the agent VM up 1 min 34 s from power return; ping at 45 s | firmware set to power on after AC loss, so it starts even though it was off when power went |
| Agent box warm restart to ssh | 27 to 33 s | 20260924; NixOS, NVMe |
| Agent box, a deploy that breaks the network, to back on the last good generation without anyone touching it | 22.5 min | 20260928; systemd-boot boot counting, 3 tries; each try boots, runs a 5 min post-boot check, fails and reboots (about 7 min 20 s) |
| Agent box, a normal boot to marked good | 29 s to ssh; marked good as ssh came up | 20260928; the post-boot check proves network, sshd, the forge and /work |
| Agent box, boot into the fixed rescue entry | 27 s to ssh | 20260928; a RAM system on the boot partition, its own host key, independent of every deploy |
| Agent box rebuild, restart to answering | 12 min 13 s, of which 8 min was a wait of ours on the wrong network port; about 4 min without it | 20260927; installer from a USB stick by one-time boot entry, /work kept |
| core (Raspberry Pi 4) cold start to ssh | 32 s | 20260924; Debian, SD card (before the move to an SSD on 20260928) |
| core cold start to serving correct time | 45 s after power; 10 s after its first sync | 20260924; chrony, no real-time clock, the public NTP pool preferred |

## Power (UPS test, rung 1)

A 1350 VA line-interactive UPS at about 4% load, input cut on 20260927. On its battery outlets:
the infra box, the agent box, a spare mini PC and the core Pi; on a surge-only outlet, the
compute laptop, which has its own battery. The router and switch stayed on mains.

| What | Figure | Conditions |
|---|---|---|
| Runtime estimate | 281 min on mains, 124 min two seconds after the cut | the UPS's own figure; trust the one read on battery |
| Charge estimate under load | 100% to 79% in about 40 s | voltage based; it recovers when the load stops |
| Cut to shutdown started | 42 s | threshold set to 95% for the test, so it tripped at once |
| Shutdown started to box at standby draw | under 55 s | Unraid: the VM, 16 containers, the pool |
| Power back to every service answering | about 1.5 min from the box powering on | unless the battery runs out, the UPS keeps its outlets on after the shutdown, so the box stays off until its power is cycled or its button pressed |

## Alert timing

| Event | Figure | Conditions |
|---|---|---|
| infra fully down, to the email from the external dead-man (a hosted check that alarms when expected pings stop) | about 6 min | 20260924; Healthchecks.io, set to a 3 min period plus 3 min grace, so the figure is what the settings allow |
| core powered off, to the alert on the hosted ntfy topic | 5 min 7 s | 20260924; sent by the watcher script on the agent box; Alertmanager followed 1 min later |
| core's ntfy blocked for 2 minutes | alert delivered 46 s after the block lifted | Alertmanager retries; nothing lost |

## Time (rung 3)

- Three hours with the internet's time servers blocked: the site stayed within a few
  milliseconds (core +1.3 ms against the agent box's best source when the block lifted).
- A separate cold start of a Pi with no clock: it came up 9 hours behind and corrected by 32,534 s in one
  step 22 s after boot; it never served the wrong time as good.

## Power draw

Measured 20260928 from smart plugs with power metering (read every 10 s, means over 10-minute
windows) and the Mac's own reported input power (its DC side, every 5 s). The UPS was online and
fully charged throughout.

| Box | Figure | Conditions |
|---|---|---|
| Infrastructure box (8-bay all-flash NAS, i3-N305, 48 GB, 16 containers and a VM) | 21.7 to 22.7 W | at rest, in every window |
| Core (Raspberry Pi 4, USB SSD) | 3.7 to 3.8 W | at rest |
| A spare N100 mini PC, idle on a live installer | 5.9 W | at rest |
| Compute (M1 Max, 64 GB), nothing loaded | 5.9 W DC | the model server running, no model loaded |
| Compute, four models loaded, idle | 6.1 W DC | loaded models cost 0.2 W |
| Compute, two chat requests generating | 61.7 W DC; 62 W more at the wall | the adapter is about 90% efficient under load |
| Compute, the rung 4b mix (chat, embeddings, reranking, speech) | 54.1 W DC; 58 W more at the wall | less than chat alone: the four kinds share one GPU, so each chat gets a smaller share of it |
| Everything behind the UPS at rest | 54 to 56 W at the UPS input | infra, core, the agent box, the Mac, the UPS's own loss, and a spare mini PC (5.9 W) that is not part of the site; about 49 W for the site itself |

- The agent box has no meter of its own. The agent box, the Mac and the UPS's own loss together
  draw about 23 W at rest, so the agent box draws at most about 16 W.
- About 55 W with the spare plugged in is about 480 kWh a year; the site alone, about 49 W, is about 430 kWh. Multiply by your price per kWh.
- The router and the switch are on the wall and not measured.
