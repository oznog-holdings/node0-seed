# The multi-host power protocol (rung 3; written and dry-run only, not power-tested)

**Pages:** index › Rung 3: core "is the box that handles power events, so a power event must
not be able to kill it"; design › Services: "UPS monitoring: infra as server, every box a
client"; design › Monitoring: "verify every alarm once by causing the condition: pull the
UPS plug". The pages don't give the order, the thresholds, or what each client does (F-UPS,
F-POWER). The orchestrator asked for the protocol under Unraid's own UPS support, written and
dry-run only; **the power test itself waits for the owner** (`ups-power-test.md`).

## Who is on what

| box | power | role in a power event |
|---|---|---|
| UPS | CyberPower CP1350AVRLCDa (USB to infra), 815 W nominal; 4 % load, about 281 min at full charge (20260924) | the source of truth |
| infra | UPS | **the server**: Unraid's apcupsd (Settings › UPS Settings) drives the UPS over USB and serves its state on :3551 (`NETSERVER on`, `NISIP 0.0.0.0`). **Shuts itself down** at 25 % charge or 10 min left (whichever first; 25 % from 20260927, the owner's choice; it was 50 %), `TIMEOUT 0`, `KILLUPS no`. Unraid's shutdown gives agentvm 60 s (domain.cfg `TIMEOUT 60`), then stops containers and the array (disk shutdown timeout 90 s) |
| agentvm | inside infra | stopped by Unraid as above; no client of its own |
| agent box | a UPS **battery** outlet (the owner, 20260928) | **rides** (orchestrator: rides the UPS and is not told to shut down; warm restarts only). No client |
| core | plug4, behind the UPS | **rides and reports, never halts.** Reads infra's apcupsd every 15 s (`seed-power-watch`; every minute until 20260927). Any status but mains (ONLINE, alone or with TRIM/BOOST) is a power event: ONBATT, LOWBATT, SHUTTING DOWN, COMMLOST, and so on. One ntfy line per change, with apcupsd's status text and its thresholds; metrics for the monitoring. The apcupsd daemon is installed (for `apcaccess`) but **masked** |
| router, switch | wall outlet (deviation D.07) until 20260929; **UPS battery outlets from 20260929** (rung 6) | go dark at the cut (until 20260929); ride the UPS since |
| compute | the UPS's **surge-only** (non-battery) outlet (the owner, 20260928): behind plug1, not battery-backed | **rides on its own battery**: at a cut it loses AC and the MacBook's battery carries it. Not a UPS client |

## Which alert reaches the phone in a power cut (20260928)

**On this bench it's core's watch** (`seed-power-watch`).
- (Until 20260929.) The switch and the router are on a wall outlet (D.07); from 20260929 on the UPS (rung 6), with the firewall. At the cut, nothing from infra reaches core's
  ntfy or the internet.
- core, on the UPS, keeps running but can't read infra either. After 3 minutes of misses it sends
  **"Power: UPS state unreadable"**: that's the power alert (it reached the phone on 20260927 at
  23:42:22Z, ntfy id RJxN3uW7kaDG).
- If the switch ever sits on the UPS, core's first read after the cut sends **"Power: ONBATT"** (or
  SHUTTING DOWN) within 15 s.

**infra's own rule** (`UpsOnBattery`, site/infra/monitoring/rules/power.yml) is fast enough for a fast
shutdown:
- apcupsd is read every 10 s (`seed-ups-metrics.sh`), scraped and evaluated every 10 s, with
  `for: 10s` and `group_wait: 0s`, so about 40 s in the worst case. The UPS test's shutdown came
  97 s after the cut.
- Its unit tests (promtool) cover the incident's case, ONLINE straight to SHUTTING DOWN.
- It carries UPS events that keep the LAN up (a self-test, a brownout, a battery fault), and every
  power event once the switch is on the UPS.

## Why core never shuts itself down

1. **A halted Pi 4 cannot start itself again while its power stays on.** It has no power
   button, and with `KILLUPS no` the UPS output does not drop after a shutdown. A core that
   halted on battery would stay dead after the mains came back, until someone pulled its
   plug: exactly the "power event that kills it".
2. **A Pi that loses power starts again by itself** when power returns. So if an outage
   outlasts the battery, core goes down hard with the rest and comes back first.
3. **The cost is the SD card**, which a hard power loss can damage. It is kept small: few
   writes (query log in memory, restores in tmpfs, journal capped and synced every 15 min),
   ext4's journal and a filesystem check at boot, the ext4 error count watched
   (CoreFilesystemErrors), and nothing on core that a rebuild from the repo doesn't restore.
4. At about 4 W, core costs the battery almost nothing once infra is off.

## A long outage, step by step

1. **Mains fails.** The router and the switch go dark at once (D.07). **On this bench no box
   hears anything from here on:** core reads infra's apcupsd through the switch. core's watch
   reports "UPS state unreadable" after 3 minutes, but only into its own journal, because the
   internet is gone too. infra's apcupsd still sees the UPS over USB.
   On a site with the switch and router on the UPS (the recommendation), core sends "Power:
   on battery" to the phone and keeps reading the charge.
2. **Charge reaches 25 % (or 10 min left).** infra shuts down cleanly: agentvm, then
   containers, then the array. DNS and NTP stay up on core, the primary, which is why core
   is the primary. The agent box and core ride on.
3. **The battery runs out** (hours at this load), if the outage lasts that long. core and
   the agent box lose power.
4. **Mains returns.**
   - If the battery ran out: the UPS switches its output back on, core boots by itself; the
     agent box boots if its firmware powers on after a power loss (not checked; Needs hands).
   - If it didn't: core and the agent box never stopped. core sends "Power: mains back".
   - **infra is halted either way** and needs its power button (hands), unless its
     firmware powers on after power loss *and* the UPS output actually dropped. Then:
     `site/bin/check-after-reboot`.
   - **If infra boots but never reaches the network** (no ping; the router's ARP for 192.168.1.10
     stays INCOMPLETE), **and plug2 shows running-level draw** (about 15 to 22 W, not the 2.5 W of
     standby), **power-cycle it first**: a clean shutdown from its button (a short press), then on.
     On 20260928 its 10 Gb link flapped 125 times in 17 minutes after a power-on, and one cycle cured
     it without touching the cable (F-INFRA-LINK-FLAP). Look at the cable and the switch port only if
     a second boot flaps too. The evidence is in `/boot/logs/syslog-previous`
     (`grep "link status definitely" …`).

## Not implemented (proposals for the owner)

- **Router and switch on the UPS.** Without them no client hears the server, the phone hears
  nothing, and the protocol runs blind (F-UPS).
- **infra powers on by itself.** Set its firmware to power on after AC loss, and consider
  `KILLUPS yes` so the UPS drops its output after infra's shutdown and brings everything back
  when the mains returns. That is a change to Unraid's UPS settings and to firmware, so it is
  the owner's call, and it needs the power test.
- **core read-only at the very end.** At a few minutes of runtime left, core could remount
  its root read-only rather than halt (safe for the SD card if power then goes, and still
  alive if it doesn't), and reboot once mains has been back for 10 minutes. Not built: it
  only helps with the switch on the UPS, since today core can't read the runtime then.

## The dry run (20260924, nothing shut down)

- **infra's side, read only:** Unraid's settings as above (from
  `/boot/config/plugins/dynamix.apcupsd/dynamix.apcupsd.cfg` and `/etc/apcupsd/apcupsd.conf`).
  The `doshutdown` path in `apccontrol` is `/sbin/shutdown -h now`, with no event script
  overriding it on infra. **Not executed.**
- **core reads the server:** `apcaccess status 192.168.1.10:3551` from core → `UPSNAME infra`,
  `STATUS ONLINE`, `BCHARGE 100`, `TIMELEFT 281.1`, `MBATTCHG 50`, `MINTIMEL 10`. Metrics
  `seed_power_ups_readable 1`, `seed_power_on_battery 0` scraped by infra's Prometheus.
- **core's reactions, simulated:** `SEED_POWER_TEST=ONBATT|ONLINE|UNREACHABLE
  seed-power-watch` sent the four lines (on battery, mains back, unreadable, readable again),
  each marked DRY-RUN, to core's ntfy. They were read back as the phone's user. The real state
  file was untouched.
- **No halt path on core:** `apcupsd` masked; no `shutdown`, `poweroff`, `halt` or `reboot`
  in core's scripts (grep: one match, a comment saying so).
- **Still to prove, by the power test:** that infra really shuts down at its threshold, what
  the UPS does after, whether infra and the agent box power on by themselves, and core's SD
  card after a real loss of power (if the test runs the battery down).

## The power test (20260927, R1.40, R1.81)

- **The cut:** at 23:38:20Z the orchestrator cut the UPS input (plug1); router, switch, the agent box
  and compute stayed on: the router and the switch on mains (the wall); the agent box on the UPS's
  battery; compute, on the UPS's surge-only outlet, on its own battery (the owner, 20260928). At 23:38:22 the UPS was ONBATT, 100 %, TIMELEFT 124 min.
- **The shutdown:** the threshold was 95 % for the test. The charge estimate sagged from 100 to
  79 % in about 40 s, and at 23:39:02 apcupsd logged "Battery charge below low limit", then
  "Initiating system shutdown". sync 23:39:22, unmount 23:39:23, standby draw by 23:39:57: clean.
- **Mains back:** at 23:42:28 mains returned, and infra stayed off (`KILLUPS no`), as designed. The
  plug2 cycle at 23:43:05 powered it on. It booted at 23:43:23, and the array, 16 containers,
  syncthing and agentvm came up by themselves. check-after-reboot was all ok: pool healthy, no
  unclean shutdown.
- **Alerts (ntfy on core):** 23:40:27 watcher FAILING (infra unreachable); 23:42:22 "UPS state
  unreadable"; 23:44:15 "readable again" (ONLINE, 73 %); 23:44:35 watcher FAILING (DNS on infra:
  a dig artefact, F-UPS-DNS); 23:49:32 watcher OK.
- **No "on battery" was sent** (F-UPS-WATCH). core's one read inside the 97 s between the cut and
  the shutdown, 23:39:19, saw STATUS "SHUTTING DOWN", which the old watch took for mains. Fixed:
  every non-mains status is an event, reads every 15 s, proven by dry run including SHUTTING DOWN.
- **Considered, not done:** apcupsd's own event hooks on infra (`apccontrol onbattery` pushing to
  core's ntfy). Unraid rebuilds /etc at every boot, so a hook needs its own persistence on the
  flash. At 15 s with a 25 % threshold, a read always lands between the cut and the shutdown.
