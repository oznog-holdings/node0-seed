# Pitfalls

The things that cost us time building the Seed, and will cost you time. Each says what
happened, why, and what to do instead. The rung where you meet it is in brackets.

## After a reboot, the whole site stayed down (rung 1)

Unraid's array does not start after a boot unless "Enable auto start" (Settings, Disk
Settings) is on, and it is **off** by default. After a reboot or a power cut the pools stay
unmounted, so nothing that lives on them starts: no containers, no VMs, no DNS, no
password manager, no monitoring. On our bench, on 20260924, this was a 12-minute full outage the first
time we rebooted after building the pool, and only the external dead-man (a hosted check that
alarms when expected pings stop) noticed.

**Do instead:** turn auto start on as soon as the pool exists, and reboot once on purpose to
prove the site comes back with nobody touching it. Keep a post-reboot check that looks at the
array, the pool, every container, the VMs and each service's health endpoint.

## DNS moved off the router, except over IPv6 (rung 1)

Handing clients your own DNS server through DHCP covers IPv4 only. OpenWrt (and many other
routers) also announce themselves as a DNS server in IPv6 router advertisements, so any
IPv6-capable client asks the router for some names and skips your server.

**Do instead:** set the DHCP DNS option to your server **and** stop the router announcing
itself over IPv6 (on OpenWrt, `dhcp.lan.dns_service=0`).

## Exempting a client from ad filtering also removes your own names (rung 1)

In AdGuard Home, the site's names (rewrites) are part of the filtering engine. A client with
filtering turned off gets no rewrites, so your own servers stop resolving your own names.

**Do instead:** leave filtering on for every client, or test name resolution from the
exempted clients themselves, not from somewhere else.

## A self-hosted password manager holding the keys to its own backup (rung 1)

Vaultwarden's backup is encrypted with a restic password and uploaded with a bucket key.
If both live only inside Vaultwarden, and the box it runs on dies, the only copies of the
keys to the backup are inside the backup.

**Do instead:** keep a break-glass set, kept for emergencies only, somewhere else (a hosted password manager, paper, or
a recovery pack kept off the site): the password manager's own master and admin
credentials, the restic passwords, the bucket keys, the box's root password and the
recovery pack's passphrase.

## A test certificate blocked the real one for an hour (rung 1)

Getting a certificate by DNS-01 writes a TXT record. Resolvers cache it for the record's
time to live (an hour at many DNS providers). After a staging run, the production run
failed because resolvers still returned the staging token, and every retry uses up part of
the certificate authority's failure allowance.

**Do instead:** set a short TTL for the challenge record (Caddy: `dns_ttl 60s`), or wait out
the TTL between staging and production. Stop after the first failure.

## "Can't delete" shows up as success (rung 1)

With an append-only backup server, a client's `restic forget` is refused.
restic printed the refusal and **exited 0**, with nothing deleted. A job that checks only
the exit code reports a successful clean-up that never happened.

**Do instead:** judge by the result (count the snapshots afterwards), never by the exit code.

## Adding memory did not grow the ZFS cache (rung 1)

At first boot Unraid sets the ZFS cache ceiling to 20% of the memory installed, writes it to
the flash, and never recalculates it. Upgrade the memory later and the ceiling stays where
the smaller box put it.

**Do instead:** after adding memory, change the ZFS cache setting in Settings, Disk
Settings.

## `mem=16G` does not make a 16 GB box (rung 1)

If you limit memory on the boot line to emulate a smaller machine, `mem=` caps the highest
memory address, not the amount of usable memory. With firmware reserving about 2 GiB below
4 GiB, `mem=16G` gave 13.4 GiB.

**Do instead:** compare MemTotal with a real box of the size you want and raise `mem=` until
they match; for a 16 GB box of the same model that took `mem=18G`. Set the smaller box's ZFS
cache ceiling too.

## A deploy that died halfway looked finished (rung 1)

A deploy script copied new files, failed before restarting the service, and the next run
saw "no change" and left the old configuration running. The same failure had written an
empty secret file, which crashed the proxy when it was next recreated.

**Do instead:** end every deploy by asking the running service what it serves, and
restart on any difference. Check a secret file's shape before writing it.

## A comment broke the time server (rung 1)

chrony refuses a comment on the same line as a directive (`server ... iburst prefer  # note`)
and will not start. Checking the configuration language (here, evaluating NixOS) never runs
chrony's own parser, so it passed every check.

**Do instead:** check rendered configuration with the program's own parser before deploying
(`chronyd -p`, `caddy validate`, and so on). Keep comments on their own lines.

## Switching Unraid's clock to manual moved it back (rung 1)

Handing infra's clock to a chrony container means turning Unraid's own NTP off. The Manual
setting's form submits the date and time it showed when the page opened, so applying it a
few seconds later set the clock back by those seconds. chrony's first step corrected it.

**Do instead:** expect the step, and check the clock (`date -u`) after the change.

## A stick labelled UNRAID next to an Unraid box (rung 1)

A spare USB stick given for the recovery pack still held an old Unraid install labelled
`UNRAID`, the label Unraid looks for to find its boot drive. Left in during a reboot, it
could have been booted from or mounted as the system drive.

**Do instead:** before any reboot, check every stick in the box; only the boot drive may
carry the `UNRAID` label.

## A Raspberry Pi as the time server has no clock of its own (rung 3)

A Pi 4 has no real-time clock. After a cold start during an internet outage its time is a
guess, and a time server told to serve its local clock (`local stratum 10`) would hand that
guess to the whole site as if it were right.

**Do instead:** use a Pi with a clock (a Pi 5, or a clock HAT), or tell chrony to serve its
local clock only after it has synchronised once since starting
(`local stratum 10 orphan activate 0.1`), with the infra box (which has a clock) as a
source.

## A Mac as the laptop (rungs 0 and 2)

- **Headless agent logins cannot use the keychain.** An agent account on a Mac that nobody
  logs into at the screen has no unlocked login keychain, so Claude Code could not save its
  login ("couldn't save your login"). Use its long-lived token instead (`claude setup-token`),
  kept in a file only that account can read, loaded only for the agent's own commands.
- **A scheduled job cannot read Desktop, Documents or Downloads** until it is allowed to,
  even the user's own, because of macOS privacy protections. Those folders hold ordinary user
  data, so grant the backup program Full Disk Access (System Settings, Privacy & Security),
  then prove it by restoring one file from each of the three folders. An upgrade that replaces
  the program can drop the grant, so repeat the check after one. Exclude a folder only if you
  move its data somewhere that is backed up, and have the readiness check fail if an excluded
  folder holds a file.
- **A new USB network adapter may need approval.** macOS asked before letting a new USB
  accessory connect; the adapter showed up as a USB device with no network interface until
  the prompt was accepted and it was plugged in again.

## Account connectors come with an agent's login (every rung)

Logging an agent tool in with a person's account also brings that account's connectors:
mail, documents, calendars. On our bench they showed as connected for the builder.

**Do instead:** switch them off for every agent you install: for Claude Code, `ENABLE_CLAUDEAI_MCP_SERVERS=false`
in the account's settings; for Codex, its `apps` feature off. Check with `claude mcp list`
and `codex mcp list`.

## A reinstall that would have erased the work it was meant to keep (rung 2)

The agent box's disk layout, declared with disko, listed every partition as one to format,
`/work` included. The standard reinstall command would have erased `/work`, the one thing the
design says survives every rebuild. We caught it by reading the layout before the first
rebuild.

Also outside `/work`, and lost by a reinstall unless you keep them: the agent tools' logins
and session history, the agent's ssh key (a new key has to be added on every machine it reaches), its
password-manager login, the box's Tailscale identity (it rejoins as a new machine, and the
subnet route needs approving again), and the box's forge deploy key.

**Do instead:** format only boot and root, mount `/work` as it is, and refuse to continue if
its filesystem UUID changed. Keep the agent's state on `/work` through bind mounts declared in
the configuration, and keep the machine identities (ssh host key, Tailscale state, deploy key)
in an identity store off the box, restored before the first boot.

## A stick pulled from the box can press its power button (rung 1)

On the bench's infra box (a TerraMaster F8 SSD Plus) the power button is at the back edge of
the top panel and the USB ports are at the top of the back panel, just below it; there are no
front ports. A hand reaching over to a stick meets the button. On 20260927, moving a USB
stick out of the running box pressed the button, and Unraid did what a short press means: a
clean shutdown. Nothing was lost, but everything on the box went away without warning.

**Do instead:** on a box laid out like this, move sticks with the box shut down, or keep a
finger clear of the button.

## A UPS shutdown can be faster than your power alert (rung 3)

On the bench, core read the UPS state once a minute. The UPS went on battery, crossed the
shutdown threshold and began shutting the box down inside one of those minutes. By the next
read the status said `SHUTTING DOWN`, which the watcher did not count as a power event, so the
phone never got "on battery". Since 20260927 core reads it every 15 s.

**Do instead:** treat every status other than `ONLINE` as a power event, and send the first
alert from the UPS daemon's own event hook rather than from a poll.

## Shortening a UPS test with a high charge threshold trips at once (rung 1)

The charge a UPS reports is estimated from battery voltage, which sags as soon as it takes the
load: ours fell from 100% to 79% in 40 seconds. A 95% threshold, set to keep the test short,
shut the box down within a minute, on 20260927. That test proves the box shuts down, but not
how long the battery holds it up.

**Do instead:** to shorten a test and still see the minutes on battery, raise the runtime
threshold (`MINUTES`) for the test so the shutdown starts earlier, then set it back to 10; or
accept a longer test.

## A portable SSD on a Raspberry Pi 4 can drop off mid-write (rung 3)

Moving the core Pi from its SD card to a USB SSD, the SSD went offline while its root
filesystem was being grown: the kernel's fast USB storage driver (UAS) aborted a command and
could not bring the disk back. Many portable SSDs' USB bridges misbehave under UAS on a Pi 4.

**Do instead:** add one kernel parameter that makes that device use plain usb-storage:
`usb-storage.quirks=<vendor>:<product>:u` (from `lsusb`) on the kernel command line, in both
the SD card's and the SSD's `cmdline.txt`. On the Pi's kernel both drivers are built in, so
`modprobe.d` cannot reach them. Stress the disk before trusting it (we wrote 32 GiB, read it
all back by hash, and formatted the whole disk while watching the kernel log). If it still
drops out, suspect power: all four USB ports share 1.2 A. A powered hub is the usual remedy
(not tested here).

Keep the SD card untouched and set the boot order to USB first, then SD. The way back is then
to unplug the SSD and cycle the power. On the bench, core served no DNS for 27 s during the
switch, and infra answered as the second DNS server.

## A 10GBASE-T link can flap after a cold start and never settle (rung 1)

After the bench's infra box was powered off for a few minutes (to remove drives) and started
again on 20260928, Unraid booted normally but its 10 GbE link came up and dropped 125 times in
17 minutes, never long enough to be reached. The box drew its normal running power, so from
outside it looked powered but did not answer. Nobody touched the cable; a second power cycle
brought a stable link. Later that day the same link also flapped twice while the box was
running, so it is not only a cold-start problem.

**Do instead:** on a box that boots but never reaches the network, power-cycle it once before
chasing cables or switch ports. An alert on link changes (`node_network_carrier_changes_total`, ours fires on 4 in
10 minutes) catches a link that flaps while it partly works; a link that never settles can only
be caught from outside the box, by another box's watcher and the external dead-man.

## A spare box's clock was hours off during a rebuild (rung 1)

Rebuilding the infra box on a spare mini PC on 20260928, its hardware clock was 7 hours off,
because a previous operating system had kept local time. Nothing on a restored Unraid box sets
the time until the array runs, and a wrong clock breaks the licence check, backup times, TLS
and the password manager's tokens.

**Do instead:** set the firmware clock to UTC before the first boot. The rebuild's order is in
[the recovery pack runbook](runbooks/recovery-pack.md#the-whole-infra-box-on-other-hardware-20260928).

## The old box's array record does not belong on new hardware (rung 1)

The flash backup holds the array and disk configuration (`super.dat`, `disk.cfg`, `pools/`)
and hardware state such as a ZFS memory cap sized for the old box. Restored onto new hardware,
they describe disks that are not there.

**Do instead:** restore only what moves: the network settings and identity, users and shares,
the Docker templates, the plugins' settings and the scheduled scripts. Create the pool
afresh.

## A full restore overwrites the new boot stick (rung 1)

The site's backup includes `/boot`, the Unraid flash. The rehearsal's plan caught that
`restic restore latest --target /` would overwrite the new stick's licence and network port
settings with the old box's.

**Do instead:** restore with `--exclude /boot`, and `--no-lock` when the key can only read.

## Unraid refused a trial on a restored stick (rung 1)

With the old array record (`super.dat`) restored, Unraid refused the new stick's trial: "It is
not possible to use a Trial key with an existing Unraid OS installation". With only the
configuration that moves, the trial was accepted. A paid licence moved to a new stick retires
the old stick for good.

**Do instead:** decide how a new stick will be licensed before the day you need it, and never
move the licence off a working box for a rehearsal.

## The memory supervisor stopped the model before its ceiling (rung 4)

The supervisor stops the model server when free memory falls below a threshold. At a 48 GiB
ceiling on a 64 GB machine about 10% stays free, so our first threshold of 20% stopped the
server before the ceiling was reached.

**Do instead:** set the free-memory threshold below what the ceiling leaves free (ours is 5%
since 20260928). See [rung 4](rungs/4-compute/README.md#decisions-and-options).

## A benchmark that repeats its prompt measures the cache (rung 4)

Our first benchmark sent the same prompt again and again and reported first tokens in
0.04 s. Every one was a prompt-cache hit.

**Do instead:** take first-token time from a cold prompt, the first run of each. See
[rung 4](rungs/4-compute/README.md#costs-and-measurements).

## The prompt cache grew the small models and hurt reranking (rung 4b)

llama-server keeps a prompt cache of up to 8 GiB of memory per model by default. With it on,
the small models grew by about 0.5 GB per request until the supervisor
stopped them at the ceiling, and the reranker put the right document first 40% of the time
instead of 95%.

**Do instead:** set `cache-ram = 0` for every model you do not chat with. See
[rung 4b](rungs/4b-models/README.md#what-cost-us-time).

## The gateway rejected llama.cpp's transcription reply (rung 4b)

LiteLLM's `openai/` transcription parser rejects llama.cpp's usage object
(`input_tokens_details`, where OpenAI's is `input_token_details`).

**Do instead:** use LiteLLM's `mistral/` parser with the Mac as `api_base`; nothing goes to
Mistral. See [rung 4b](rungs/4b-models/README.md#what-cost-us-time).

## The building agent printed its own secrets (the agents)

In four days Keel, the building agent, printed three secrets into its own session while reading
configuration: an encryption key in an error message, part of an API key in a process listing,
and five notification tokens from a file it had filtered with `grep -v`, whose lines did not
contain the word it filtered on. A session goes to the model provider, so each counted as
exposed and was rotated.

**Do instead:** read a configuration through a list of named keys, never by filtering lines out.
Then make it structural. Pass every command's output through a redactor before the agent sees
it, refuse the command if the redactor is missing, and scan each turn's transcript afterwards for
anything that got through ([the agents](agents/)).

## A scheduled deploy that switched every 15 minutes, changed or not (rung 2)

The agent box's pull-deploy rebuilt and switched every 15 minutes even when nothing had changed.
Each switch reloaded the system's service manager and re-executed every user's. That re-based
relative timers: a test window meant to last 60 minutes ran 75, and one of 40 ran 51. It also
touched the agents' own services every quarter hour.

**Do instead:** switch only when the build differs from what is running, what will boot, or what
was last switched; and give any timer that must hold a deadline an absolute time, not "in 40
minutes".

## The agents read an old rulebook from their own branches (the agents)

Each agent loaded its rulebook from its own working branch. Those branches still held the
version from before four days of fixes, so none of the new rules reached the running agents.
Found on 20261006.

**Do instead:** deploy the rulebook as a read-only file owned by root, from the branch that
deploys, and point the agents at that path. It then always matches what is deployed, and an agent
cannot edit its own rules. To make a running agent reload it, exit the agent and start it again;
restarting its terminal pane left the running agent alone.

## A deploy restarted the agent under test (the agents)

Between two test blocks, with the agent deliberately stopped, a deploy restarted the agents'
user services, and that started the agent again with its start task. A check that failed during that
switch made it exit with an error, so the next scheduled pull switched again, and start it a second time.

**Do instead:** stop an agent for a window only after the last deploy's pull reports "no change",
and check it is still stopped before the window starts. A guarded root step that refuses to run
while the agent is running caught it here.

## Alertmanager lost notifications to an intermittent 403 (rung 3)

ntfy 2.28 refused a valid access token now and then under concurrent publishes: 4 of 200 with a
token, 0 of 200 with a password. Alertmanager does not retry a 4xx, so two notifications were
lost on 20261003.

**Do instead:** have Alertmanager sign in to ntfy with a password, and route its own
notification failures (NotifierFailing) to a second, hosted topic.

## Critical alerts reached the owner but not the agent (rung 3)

Core's own alerts went only to the hosted topic, by design, so the owner hears of core's absence
even when core's ntfy is down with it. The agent cannot read the hosted topic, so it saw a
critical alert about core only later, in Prometheus's history.

**Do instead:** send those alerts to both topics. The owner gets a duplicate while core is up,
and the agent sees them at once.

## A prompt cache uses more memory than the process size shows (rung 4)

With llama.cpp's RAM prompt cache on, the server's resident size understated what it used,
because macOS compresses part of it. A supervisor that read the process size let memory pressure
reach "warn" and then had to stop the server.

**Do instead:** measure with macOS's footprint, which counts compressed memory, and budget about
92 KiB a token for each saved prompt on a model like Qwen3.8-27B.
