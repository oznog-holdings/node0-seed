# What's left: for the owner and the orchestrator to resolve together (updated 20260928, 15:10Z)

The coverage table has **2 open rows**, and one holds the other:

| row | what | when |
|---|---|---|
| **R1.97** (rung 1) | the agent kit, with Telegram (the owner's choice of 20260928) | after our review |
| **X.01** (each rung a complete site) | rungs 0, 2, 3 and 4 have every row closed; rung 1 is held only by R1.97 | closes with R1.97 |

**Planned for the optional services phase** (the owner, 20260928; not open work now):

| row | what | gap to plan around |
|---|---|---|
| **R1.42** | Home Assistant on infra: installed, configured and documented on the running seed, alongside Paperless, Jellyfin and the others | no Zigbee coordinator or other home-automation radio on the bench: the HA guide is planned without radio hardware, and its Zigbee side is documented from material the orchestrator supplies |
| **R3.16** | environmental sensors to HA on core, their values to monitoring as metrics | no sensor hardware: the sensor side from supplied material; the metrics path shown with a simulated or network-only sensor |

Every other row is done, done with a stated deviation (R2.01, F-LARK), or excluded with a reason (R1.07: 48 GB fitted, no purchase).

## One conditional note (a closed row)

- **R1.21:** ProtonVPN isn't running on compute, and the site's routes are on the wired port. If it's
  ever used there again, turn its LAN exclusion on (ProtonVPN › Settings › "Allow LAN connections"),
  or remove it. check-laptop fails if the site's range leaves en9.

## Resolved on 20260928 (for the record)

- **R1.91:** done at the move: the development layout was recreated at rung 2 from the flake,
  not copied (move-builder-to-agent.md steps 2-4, rung2-agent-install.md).
- **R2.01:** a stated deviation (F-LARK), with the choice for a reader: agents only, 12-16 GB;
  agents and development, 32-64 GB, 8 cores, two NVMe. The bench's 12 GB cost nothing measurable
  in 4.2 days (2026-09-24T08:58:20Z to 2026-09-28T14:53:21Z, F-LARK).

- **R0.07:** the B2 admin key is kept by the owner outside the site's vaults. His
  `b2 key list --long` of 20260927 shows only the admin keys with deleteFiles.
- **R3.07:** restated by the owner and closed on the 3-hour test of 20260924. The last resort itself
  wasn't exercised.
- **R4.08 and R4.10:** the owner's admin settings on compute: Spotlight off, App Store auto-updates
  off, NTP from core. Checked as `seed`.
- **R1.12:** a YuanLey 8-port 10G unmanaged switch; in hosts.md.
- **N35:** dropped.
- **R2.30, R1.18, R1.22:** cite the orchestrator's record, lab diary/20260923-preparation.md, line
  267.
- **The data pool's 10 GB:** agentvm's retired /work image, discarded by mkfs.xfs.
- **The `admin` session on compute:** not logged in; a stale utmp line.
- **The tailnet route:** served by the agent box (primary). infra's advertisement is an unexercised
  standby; a note, not a row.
