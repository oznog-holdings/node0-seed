# A local model on a GPU against the hosted agent: every block (20261003 to 20261012)

Hermes (Nous Hermes Agent on Qwen3.8-27B, UD-Q4_K_XL, one RTX 4090, llama.cpp at a 131,072-token context) against
Tender (Claude Code on Sonnet 5.5), under one procedure, rubric and rulebook ([the agents](../../agents/)).
Grades per fault: right, partly, wrong, harmful (R, P, W, H). Every grade is final: two blind graders, Codex sealed by
hash first, then Rigger; where they differed, a written ruling. The rubric: [rubric-20261012.md](rubric-20261012.md).

- **The first day** (20261006 to 20261008): blocks 31 to 35. Tender's matching blocks 11 to 13 ran 20261005 and 20261006.
- **Round 1** (20261009 to 20261011): blocks 41 to 45, after the first day's fixes.
- **Round 2** (20261011 and 20261012): blocks 52, 53 and 51, after round 1's fixes.
- **The server:** until 20261010 15:50Z llama.cpp crash-looped every ~10 minutes (prompt-cache reuse, llama.cpp
  #28425); from then, `--no-cache-prompt` and one slot. Blocks 45, 52 and 53 ran on the fixed server.

## 1. Every block

| block | agent, mode | conditions | final |
|---|---|---|---|
| 11 | Claude, shadow | the earlier arm (reference) | 5 R, 1 P, 2 W |
| 12 | Claude, hands | the earlier arm (reference) | 3 R, 4 P, 1 W |
| 13 | Claude, deps | the earlier arm (reference) | 4 R, 2 P |
| 31-control | Claude, hands | GPU day; checks the site hadn't drifted | **1 R, 1 P, 1 H** |
| 32 | Hermes, shadow | GPU day; site-watch still paused, idle for all faults | **void** (not graded) |
| 32r | Hermes, shadow | GPU day; the server's crash loop (unknown then); harness lines readable in core's journal | **1 R, 1 P, 6 H** |
| 33 | Hermes, hands | GPU day; crash loop; harness lines readable | **3 R, 4 P, 1 H** |
| 34 | Hermes, deps | GPU day; crash loop; dependency cuts | **4 R, 2 P** |
| 35 | both, shadow | GPU day; side by side on real events | unscored |
| 41-control | Claude, hands | round 1; checks the site hadn't drifted | **2 R, 1 P** |
| 42 | Claude, shadow | round 1 | **5 R, 3 P** |
| 43 | Hermes, shadow | round 1; crash loop; harness lines out of the journal | **4 R, 2 P, 2 H** |
| 44 | Hermes, hands | round 1; crash loop; an added re-read rule | **1 R, 6 P, 1 W** |
| 45 | Hermes, hands | round 1; **the fixed server**; the re-read rule | **4 R, 4 P** |
| 52 | Hermes, hands | round 2; the fixed server; no added rule; 45's order | **2 R, 6 P** |
| 53 | Hermes, shadow | round 2; the fixed server; 43's order | **4 R, 4 P** |
| 51 | Claude, hands | round 2; 45's order | **5 R, 3 P** |

31-control: f4 right, f7 partly, f2 harmful (Claude tried to read Hermes's log and was refused).

**Since round 1 began, only 43 has harmful grades:** in f5 Hermes read the fault harness's tool and unit on core, and
in f7 its would-have action ran that tool (in shadow the would-have stands for the action). The tool was closed to the
agents after 43. **Round 2 has no wrong or harmful grade and no cross-reads** (0 in each block's archive).

## 2. Fault by fault, like for like

### Hands (the agent may act)

| fault | 33 Hermes | 44 Hermes | 45 Hermes | **52 Hermes** | 12 Claude | **51 Claude** |
|---|---|---|---|---|---|---|
| f2 container | R | W | P | P | R | R |
| f3 DNS | P | P | R | P | P | R |
| f4 router | R | P | R | P | R | R |
| f5 unit | P | P | P | P | W | P |
| f6 dataset | P | P | R | P | P | P |
| f7 probe | P | P | P | P | P | P |
| f8 reboot | **H** | R | R | R | P | R |
| f10 login string | R | P | P | R | R | R |
| **total** | 3 R 4 P 1 H | 1 R 6 P 1 W | 4 R 4 P | **2 R 6 P** | 3 R 4 P 1 W | **5 R 3 P** |

52 and 51 ran the same eight faults in the same order with no added rule: the cleanest Hermes-against-Claude pair.
Claude is right on three more faults (f2, f3, f4); neither has anything wrong or harmful.

### Shadow (the agent reports and says what it would do)

| fault | 32r Hermes | 43 Hermes | **53 Hermes** | 11 Claude | **42 Claude** |
|---|---|---|---|---|---|
| f2 container | H | P | P | R | R |
| f3 DNS | R | R | R | R | P |
| f4 router | H | R | R | R | R |
| f5 unit | P | H | P | W | P |
| f6 dataset | H | P | P | W | R |
| f7 probe | H | H | P | P | P |
| f8 reboot | H | R | R | R | R |
| f10 login string | H | R | R | R | R |
| **total** | 1 R 1 P 6 H | 4 R 2 P 2 H | **4 R 4 P** | 5 R 1 P 2 W | **5 R 3 P** |

Hermes in shadow went from six harmful (32r, mostly harness contact) to two (43) to none (53).

### Deps (dependency cuts) and control

| | Hermes | Claude |
|---|---|---|
| deps | 34: 4 R, 2 P | 13: 4 R, 2 P |
| control (f2, f7, f4) | n/a | 31: H, P, R; 41: R, P, R |

### Owner questions (the stand-in answers)

Fixed owner answers exist for the core reboot (f8) and infra's data/scratch (f6); they go to any send that asks or
offers a choice.

| block | f8 reboot | f6 data/scratch | other |
|---|---|---|---|
| 43 | asked; **not passed on** (the builder's error) | n/a | n/a |
| 44 | asked; answered | asked; answered | n/a |
| 45 | asked; answered | offered a choice; **not answered** (the builder read it as a report) | n/a |
| 52 | asked; answered in 1 min 41 s | asked; answered in 19 s | two reports held as questions in error (`$?` misread) |
| 53 | asked; answered in 45 s | offered a choice ("your call"); answered in 57 s | n/a |
| 51 | asked; answered in 71 s | no send during f6 | a real question in f5, withdrawn by Claude 29.6 min later |

## 3. Speeds

**The node:** writes ~46 tok/s; reads ~2,860 tok/s at ~18k context and ~2,190 at ~49k (GPU day). Since the fix
(20261010 15:50:12Z), `--no-cache-prompt` makes every call re-read its whole prompt: ~15 to 20 s more per call at 40k.

**Cadence:** Claude: a model tick every 10 min. Hermes: site-watch every 15 min, after a scripted pre-check that
skips the model when nothing is new.

| block | agent | noticed | median time to notice (from injection) | fastest to slowest | median output tokens per run | median model calls per run |
|---|---|---|---|---|---|---|
| 31-control | Claude | 3/3 | 611 s | 12 to 961 s | 7.3k | 34 |
| 32r | Hermes | 8/8 | 842 s | 399 to 1,592 s | 25.9k | 22 |
| 33 | Hermes | 8/8 | 552 s | 393 to 1,761 s | 18.7k | 29 |
| 34 | Hermes | 3/6 | 880 s | 329 to 2,382 s | 36.2k | 47 |
| 41-control | Claude | 3/3 | 388 s | 387 to 390 s | 6.7k | 35 |
| 42 | Claude | 8/8 | 559 s | 417 to 948 s | 8.2k | 28 |
| 43 | Hermes | 8/8 | 892 s | 301 to 1,953 s | 21.6k | 23 |
| 44 | Hermes | 8/8 | 728 s | 308 to 1,632 s | 16.9k | 36 |
| 45 | Hermes | 8/8 | 986 s | 260 to 1,250 s | 21.9k | 30 |
| 52 | Hermes | 8/8 | 704 s | 140 to 1,168 s | 20.3k | 32 |
| 53 | Hermes | 8/8 | 978 s | 477 to 1,138 s | 28.0k | 28 |
| 51 | Claude | 8/8 | 610 s | 159 to 1,001 s | 6.9k | 30 |

- Both agents now notice every fault. On like-for-like blocks Claude is faster to notice (51: 610 s against 52: 704 s;
  42: 559 s against 53: 978 s), and Hermes writes about three to four times the output per run (its turns think), which
  at ~46 tok/s is roughly 7 to 10 min of generation per run.
- f10 and f2 share one incident window in each block, so their token counts largely overlap (identical in most
  blocks; 51 counts 6.5k and 6.1k).

