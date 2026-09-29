# UPS power test (R1.40, R1.81): prepared 20260923; run 20260927

**Run on 20260927 at 23:38Z** (the orchestrator cut plug1). The results are in
site/runbooks/power-protocol.md › "The power test (20260927, R1.40, R1.81)". This page is the
preparation as written before it.

index › Rung 1: "The UPS shuts the box down cleanly; the shutdown is tested by pulling the
plug, once." The orchestrator controls the UPS input remotely and schedules this with the
owner (two machines on the UPS cannot return from a power cut by themselves). Not run by
the builder; nobody is asked to pull a plug.

## What is configured (20260923)

- UPS: CyberPower, reports `MODEL CP1350AVRLCDa`, `SERIALNO SERIAL-PLACEHOLDER`, USB (HID) to
  infra. (`lsusb`'s ID database names 0764:0501 "CP1500 AVR"; the device's own string wins.)
- Unraid Settings › UPS Settings (apcupsd): USB/USB, **shut down at 25 % battery or 10
  minutes of runtime left**, whichever first (25 % is the owner's choice after the test of
  20260927; it was 50 %); no time-on-battery limit (`TIMEOUT 0`);
  **`KILLUPS no`** (the UPS output is not turned off after shutdown). Network server on
  :3551 (status for clients and the monitoring).
- Shutdown path: apcupsd → `apccontrol doshutdown` → `/sbin/shutdown -h now` → Unraid stops
  containers (10 s each), the VM agentvm (60 s, host shutdown = shutdown), the pool (overall
  90 s timeout, Settings › Disk Settings).
- Load at rest: about 4 % (`LOADPCT`). TIMELEFT reads about 280 minutes **on mains**, but that's
  the UPS's estimate; **on battery it read 124 minutes** at 100 % (20260927). With input cut, one of
  the two thresholds triggers after an hour or more.
- **For a test of reasonable length, don't raise the charge threshold toward 100 %.** On
  20260927 it was set to 95 %: the charge reading, a voltage-based estimate, fell from 100 % to
  79 % in about 40 s under load, and apcupsd shut infra down 40 s after the cut. That proves the
  shutdown path, but not a threshold. **The better lever is the runtime threshold:** raise MINUTES
  (for example to 115, a few minutes under the on-battery TIMELEFT) through the UI, and restore 10
  after. Either way, record both UI changes in the diary.

## Before (the builder runs these; read-only)

0. **The site must come back by itself:** Settings › Disk Settings › "Enable auto start" is
   Yes (`startArray="yes"` in `/boot/config/disk.cfg`), and a proving reboot has already shown
   it (F-ARRAY-AUTOSTART: on 20260924 the array stayed STOPPED after a reboot because this was
   off, and the whole site stayed down until a person started it). `site/bin/check-after-reboot`
   passes before the test.
1. `apcaccess` on infra: STATUS ONLINE, BCHARGE, TIMELEFT, the thresholds.
2. Nothing mid-write: no Backrest operation running (API `GetOperations`), no dump or
   maintenance job running (User Scripts status), no restic lock on any repository.
3. `zpool status data`: ONLINE, no errors. Note the last boot id (`/proc/sys/kernel/random/boot_id`).
4. The monitoring shows UPS state ONLINE, and the alert route to the phone works.

## During (the orchestrator)

- Cut the UPS input. Expect within 15 s: core's "Power: ONBATT" (it reads every 15 s, and any
  status but mains is an event, SHUTTING DOWN included: F-UPS-WATCH). Also expect apcupsd "Power
  failure", STATUS ONBATT, the
  UPS-state alert on the phone (the monitoring's UPS rule). Record the times.
- At the threshold: apcupsd "Remaining battery charge below limit … Doing shutdown", then a
  clean Unraid shutdown.
- Restore the input when the owner says so, then power the boxes on (they don't return
  by themselves).

## After (the builder)

1. infra's syslog from the previous boot, `/boot/logs/syslog-previous` (Unraid keeps it on the
   flash; present today), and `last -x`: the apcupsd lines, and "shutdown" not "unclean".
2. Unraid: no unclean-shutdown notice; `zpool status data` clean, no resilver or errors.
   **`site/bin/check-after-reboot` passes**: the array started by itself, the pool is mounted,
   every autostart container and agentvm are running, DNS and the HTTPS services answer,
   only the Watchdog fires, and the external dead-man is up. If the array is STOPPED: that
   is the failure this runbook exists to find. Start it from Main › Start, record the times.
3. The containers autostarted in order; agentvm autostarted; the monitoring's alert for
   UPS state has cleared, and the "on battery" alert is in its history (R1.81: caused once).
4. Record in the diary: timeline, thresholds, alerts received (with message ids), anything
   that didn't come back.
