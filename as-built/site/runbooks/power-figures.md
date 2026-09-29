# Power figures, per box (20260928; R4.09 and the bench at rest)

**Measured on 20260928, 05:37 to 06:38Z.**
- **The plugs:** the orchestrator logged the four plug meters every 10 s
  (lab: 20260928-power-windows-plugs.csv).
- **compute:** it reported its own DC input every 5 s (`ioreg` AppleSmartBattery `SystemPowerIn`,
  battery full and not charging). Evidence: evidence/20260928-power/.
- **The windows:** run by `site/laptop/inference/bench/power-windows.sh`, 10 minutes each. The other
  boxes were at rest throughout.
- **The UPS:** ONLINE, BCHARGE 100%, LOADPCT 4% at 05:35Z and at 06:23Z, so no recharging went into
  these figures.

## What each plug feeds (the owner confirmed, 20260928)

- **plug1, the UPS's input:** the UPS, and everything on its outlets.
  - **Battery outlets:** infra (plug2), Larkbox one (plug3), core (plug4) and **the agent box**.
  - **The surge-only (non-battery) outlet: compute.** In a cut, compute runs on its own battery, and
    the agent box on the UPS's.
- **On the wall, on no plug:** the switch and the router.
- **plug1 therefore measures both the agent box and compute.** plug1 minus plugs 2 to 4 is the agent box,
  plus compute at the wall, plus the UPS's own loss. With the agent box unmeasured, those three can't
  be separated.
- The measurement had shown compute behind plug1 (its chat load raised plug1 by 62.2 W, and its own
  DC input by 55.8 W) before the owner confirmed it.

## The windows (means, W)

| window | UTC | plug1 (UPS input) | plug2 infra | plug3 Larkbox one | plug4 core | plug1 − 2..4 | compute DC (ioreg) |
|---|---|---|---|---|---|---|---|
| R rest: every box idle, compute with all four models loaded | 05:37:33 to 05:47:13 | 54.6 | 21.8 | 5.9 | 3.8 | 23.2 | 6.1 |
| H compute's backend held (no model loaded) | 05:47:54 to 05:57:54 | 54.2 | 21.9 | 5.9 | 3.7 | 22.7 | 5.9 |
| C compute: both chat slots generating | 05:59:33 to 06:09:33 | 116.6 | 22.7 | 5.9 | 3.7 | 84.3 | 61.7 |
| rest after C | 06:12 to 06:23 | 55.6 | 21.7 | 5.9 | 3.7 | 24.3 | 6.1 to 7.4 |
| M compute: the rung-4b mix (two chats, embeddings, reranking, speech at once) | 06:26:37 to 06:38:08 (the loads stopped starting requests at 06:36:37; the last finished at 06:38:08) | the orchestrator's log (not yet received) | | | | | 54.1 |

## Per box

| box | condition | figure | how |
|---|---|---|---|
| **infra** (TerraMaster F8 SSD Plus, Unraid, 16 containers and agentvm, pool `data`) | at rest | **21.8 W** (21.7 to 22.7 in every window) | plug2 |
| **core** (Raspberry Pi 4, root on the USB SSD) | at rest | **3.7 to 3.8 W** | plug4 |
| **Larkbox one** (the live installer, idle; wifi off) | at rest | **5.9 W** | plug3 |
| **compute** (MacBook Pro M1 Max 64 GB, lid open, display on) | rest, all four models loaded | **6.1 W** DC | ioreg |
| | held, nothing loaded | **5.9 W** DC | ioreg |
| | chat, both slots | **61.7 W** DC (59.9 to 69.6); **+62.2 W at the wall** over rest | ioreg; plug1 C − (R+H)/2 |
| | the rung-4b mix | **54.1 W** DC, *less* than chat alone: the four kinds share one GPU, so each chat slot gets a smaller share of it | ioreg (plug1 for M: the orchestrator's log) |
| **the agent box** (Larkbox X, NixOS) | none | **not measured** | on no plug of its own, and its RAPL counter is root-only (mode 0400), which the builder can't read |
| **agent box + compute at the wall + the UPS's loss** | at rest | **23 W** together (22.7 to 24.3) | plug1 − plugs 2 to 4 |
| **switch, router** | none | not measured | on the wall, on no plug |

**Readings:**
- **The Mac's adapter** is about **90% efficient under load**: 55.8 W more on the DC side against
  62.2 W more at the wall. At rest its efficiency isn't known, so the Mac's wall draw at rest is about
  6 to 7 W, not measured.
- **Loaded but idle models cost nothing measurable:** R − H is 0.2 W on the DC side and 0.4 W on
  plug1. The 4b idle state is free; work is what costs.
- **R4.09 ("a Mac adds 10 to 60 W"):** this one adds about 6 W at rest and about 62 W at the wall with
  both chat slots busy (54 W DC with all four kinds at once). The upper end of the pages' range, from one busy model.
- **The bench at rest behind the UPS** is about 55 W at its input: infra 22, the agent box + compute +
  the UPS loss 23, Larkbox one 6, core 4.
- **The UPS's own LOADPCT (4%) is too coarse to split that remainder.** It's an integer percentage of
  815 W, so 33 to 41 W of output. The measured boxes behind it (infra, Larkbox one, core and compute's
  estimated 6 to 7 W) already come to about 38 W before the agent box. The agent box's own figure is
  what's missing.
