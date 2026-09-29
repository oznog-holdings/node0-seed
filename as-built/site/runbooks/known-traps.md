# Known traps: the lines to reach for first

## restic: 403 on every retry means orphan packs (design › Backups; R1.56)

Against the append-only rest-server, a client that gave up after a pack had already landed
retries the same upload and is refused as an overwrite, every time. Ordinary interruptions
resume by themselves; **a 403 on every retry** is this one.

1. Make sure no restic runs against the repository: on the client, stop its backup job
   (agent box `restic-backups-work`, compute `co.oznog.seed.backup`); on infra, nothing from
   `rest-maint` (02:00) or `weekly-verify` (Sunday 05:00).
2. On infra, directly on the repository directory (the one writer; never through the
   append-only server), with that machine's password from `restic-rest.env`:
   `restic -r /mnt/data/backups/rest/<machine> unlock`, then
   `restic -r /mnt/data/backups/rest/<machine> repair index --read-all-packs`.
3. `restic check`, then let the client back up again.

Exercised 20260924 on a scratch repository on the agent box (packs left without an index, as
after an interrupted upload): `check` → "repository contains errors"; `unlock`,
`repair index --read-all-packs`; `check` → "no errors were found".

## ssh: three facts that look like something else (design › Secrets; R1.76)

- **A timeout can be OpenSSH ≥ 9.8 penalising the source** after failed logins
  (`PerSourcePenalties`). Several wrong keys in a row from one address, and the next
  connection times out. Wait, or use `-o IdentitiesOnly=yes -i <the right key>` from the start.
- **A correct key refused can be permissions:** sshd ignores keys under a group- or
  world-writable path; `/etc/ssh` must be 0755 (checked 20260924: infra, the agent box, core
  and compute 0755; the router's dropbear dir 0755).
- **`ssh-keygen -R <host>` removes the whole line**, including every other name on it
  (`192.168.1.12,core.seed.example.com,core`). Re-add the full line from the pinned record,
  not just the name you removed.

## infra: the power button is just above the USB ports (20260927)

- **Move a stick only with the box shut down.** The TerraMaster has no front ports: the power button
  is at the back edge of the top panel, and the USB ports are at the top of the back panel, just
  below it (the owner, 20260927). Pulling a stick pressed the button: a clean shutdown began at 16:19:42, the
  same second as the USB disconnect, and infra stayed off until plug2 was cycled (off 15 s, on).
- **It looks like a hang from the network** (no ping, ARP INCOMPLETE), but it's a shutdown. The
  plug's draw tells them apart: about 2.5 W in standby.
- **infra up but off the network after a power-on** (20260928, F-INFRA-LINK-FLAP): eth0 (atlantic,
  10GBASE-T) flapped 125 times in 17 minutes, with ARP INCOMPLETE and plug2 at a steady 14.9 W. A
  clean power cycle cured it. Running-level draw with no network means power-cycle first
  (power-protocol.md, step 4).
