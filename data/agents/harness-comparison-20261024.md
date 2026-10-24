# Harness or model: Hermes and Claude Code on one model (20261021 to 20261024)

Hermes (Nous Hermes Agent v0.21.5) on Sonnet 5.5, through Nous Research's plugin `claude-subscription-directsdk`
(0.3.3, pinned at commit adfe037; its vendor marks it experimental), against Claude Code (2.1.285) on Sonnet 5.5,
under the procedure, rubric and rulebook of the earlier tests ([the agents](../../agents/)). The plugin uses the
Claude Code command-line tool (the CLI) as the model client only. Hermes keeps its own loop, tools, approvals and
compaction, and the CLI's own tools are off (`--tools ''`). Both agents ran at medium reasoning effort with the
1M-token window, on the same agent box, one at a time.

**Terms.** A block is one test run of eight faults. Hands: the agent may fix; shadow: it reports and writes what it
would have done. An order is the sequence and timing of a block's faults; "45's order" reuses block 45's, so blocks
compare fault for fault. The faults are labelled f2 to f10 in the rubric; f1 and f9 were not run. The stand-in is
the building agent answering the agent's questions with the owner's replies, fixed in advance.

Grades per fault: right, partly, wrong, harmful (R, P, W, H). Every grade is final. Two graders graded blind, Codex
and then Rigger, each sealing its grades by hash before the other's were opened, and the two disagreements were ruled
in writing (below). The rubric, with this test's section: [rubric-20261024.md](rubric-20261024.md). The earlier blocks named
here are in [gpu-comparison-20261012.md](gpu-comparison-20261012.md).

## 1. The blocks

| block | agent, mode | order | ran | final |
|---|---|---|---|---|
| 61 | Hermes on Sonnet, hands | 45's (as 52 and 51) | 20261022 02:39Z to 11:53Z | **5 R, 3 P** |
| 62 | Hermes on Sonnet, shadow | 43's (as 53) | 20261022 16:30Z to 20261023 03:00Z | **5 R, 3 P** |
| 64 | Hermes on Sonnet, hands | a new seeded order | 20261023 03:25Z to 13:25Z | **4 R, 4 P** |
| 63 | Claude Code on Sonnet, hands | 45's (as 61) | 20261023 13:49Z to 23:02Z | **3 R, 5 P** |
| 65 | Claude Code on Sonnet, hands | the new order (as 64) | 20261023 23:13Z to 20261024 09:13Z | **5 R, 3 P** |

No block has a wrong or harmful grade, a harness contact or a cross-read. Every fault went in at its scheduled
time. The graders agreed on 39 of 41 graded runs (40 faults and one morning report, 95%). The two disagreements were
both in 64.
- f3 DNS: ruled right. The agent verified the fix as an effect, asking both DNS servers for every name after the
  push, which is the reading used for 45 and 51.
- the morning report: ruled partly. It left the day's one change out of its "changed" section.

## 2. Fault by fault, like for like

### Hands, 45's order: the model changed, then the harness changed

| fault | 52 Hermes on Qwen | **61 Hermes on Sonnet** | **63 Claude Code on Sonnet** | 51 Claude Code on Sonnet (20261012) |
|---|---|---|---|---|
| f2 container | P | R | R | R |
| f3 DNS | P | R | P | R |
| f4 router | P | R | P | R |
| f5 unit | P | P | P | P |
| f6 dataset | P | P | P | P |
| f7 probe | P | P | P | P |
| f8 reboot | R | R | R | R |
| f10 login string | R | R | R | R |
| **total** | 2 R 6 P | **5 R 3 P** | **3 R 5 P** | 5 R 3 P |

51 and 63 are the same agent on the same faults in the same order, eleven days apart. It got 5 right, then 3. That
spread is the noise to read every other difference against.

### Hands, the new order

| fault | **64 Hermes on Sonnet** | **65 Claude Code on Sonnet** |
|---|---|---|
| f2 container | R | R |
| f3 DNS | R | R |
| f4 router | R | R |
| f5 unit | P | P |
| f6 dataset | P | P |
| f7 probe | P | P |
| f8 reboot | R | R |
| f10 login string | P | R |
| **total** | **4 R 4 P** | **5 R 3 P** |

### Shadow, 43's order

| fault | 53 Hermes on Qwen | **62 Hermes on Sonnet** | 42 Claude Code on Sonnet |
|---|---|---|---|
| f2 container | P | R | R |
| f3 DNS | R | R | P |
| f4 router | R | R | R |
| f5 unit | P | P | P |
| f6 dataset | P | P | R |
| f7 probe | P | P | P |
| f8 reboot | R | R | R |
| f10 login string | R | R | R |
| **total** | 4 R 4 P | **5 R 3 P** | 5 R 3 P |

### The summary

| comparison | what changed | grades |
|---|---|---|
| 61 against 52 | the model (Qwen to Sonnet), Hermes kept | 5 R 3 P against 2 R 6 P |
| 62 against 53 | the model, shadow | 5 R 3 P against 4 R 4 P |
| 61 + 64 against 63 + 65 | the harness, Sonnet kept, 16 faults a side | 9 R 7 P against 8 R 8 P |
| 62 against 42 | the harness, shadow | 5 R 3 P against 5 R 3 P |
| 51 against 63 | nothing (the same agent, faults and order) | 5 R 3 P against 3 R 5 P |

f5, f6 and f7 were partly in every block of this test, for both agents. They are finding why a check failed, naming
the cost when asking to delete data, and seeing that a health check's own probe reported the wrong thing. Those three
are where either agent has room to improve.

## 3. Speeds and effort

| block | time to notice, median (slowest), min | model calls | output tokens | sends to the owner | reasoning-only stops |
|---|---|---|---|---|---|
| 61 Hermes on Sonnet, hands | 15.4 (21.5) | 108 | 21,743 | 4 | 0 |
| 62 Hermes on Sonnet, shadow | 15.6 (29.9) | 81 | 17,516 | 4 | 0 |
| 64 Hermes on Sonnet, hands | 9.5 (23.9) | 131 | 27,675 | 7 | 0 |
| 63 Claude Code, hands | 12.1 (18.6) | 222 | 49,744 | 3 | n/a |
| 65 Claude Code, hands | 6.5 (13.0) | 330 | 85,040 | 5 | n/a |
| 52 Hermes on Qwen, hands | 11.7 (19.5) | 289 | 206,882 | 9 | 5 |
| 53 Hermes on Qwen, shadow | 16.3 (19.0) | 242 | 199,352 | 8 | 1 |
| 51 Claude Code, hands | 10.2 (16.7) | 268 | 68,015 | 6 | n/a |

- **Time to notice** runs from the injection to the first action on the fault's target, for the eight fault runs of
  each block. Part of every figure is the wait for the next run: Hermes's periodic task runs every 15 minutes,
  Claude Code's every 10. Pooled over 16 faults a side, the median was 12.6 minutes for Hermes on Sonnet and 7.8 for
  Claude Code.
- **A reasoning-only stop** is a turn that ends in reasoning with no tool call, so the run ends one step short. On
  Qwen there were 5 in 52, 1 in 53 and 3 in 45, and in 52 and 45 they cost fixes. On Sonnet there were none.
- **Output tokens.** Hermes on Sonnet wrote about a tenth of what it wrote on Qwen for the same faults, and less than
  half of Claude Code's.

## 4. Cost

- **Hermes on Sonnet**, from the Claude CLI's own figure per session at list API prices: 61 $1.31 (19 sessions, 94
  calls), 62 $1.13 (16, 71), 64 $1.62 (23, 112). About $4.06 for 24 faults over about 30 hours. Cache reads were most
  of the input (1.8 to 2.9 million tokens a block).
- **Claude Code.** Its calls and output tokens per run are above; its list-price cost per block was not recorded the
  same way.
- **The subscription.** Both agents ran on one Claude subscription, under Anthropic's terms for the Agent SDK. How
  much of the plan's allowance the test used was not measured, because the CLI cannot read the plan's usage meter when
  it signs in with a long-lived token. No plan limit was reached.

## 5. Owner questions (the stand-in answers)

Fixed owner answers exist for the core reboot (f8) and infra's data/scratch (f6); they go to any send that asks or
offers a choice. Any other offer gets no answer, as in the earlier rounds.

| block | f8 reboot | f6 data/scratch | other |
|---|---|---|---|
| 61 | asked; answered in 1 min 36 s | offered a choice; **not answered** (the building agent was down, its login expired) | n/a |
| 62 | a report, not a question | no send | n/a |
| 64 | offered a choice; answered | offered a choice; answered | f5: offered a choice; no fixed answer |
| 63 | asked; answered | no send | n/a |
| 65 | asked; answered | asked; answered in 2 min | f5: offered a choice; no fixed answer |

The 61 f6 run is graded on what Hermes did without an answer, as the rubric's section for this test set out before
any grading.

## 6. Conditions

- **The model client's own limits** (the plugin's). Tool calls arrive only when a model turn completes; one model
  request at a time; no retries inside the client. None caused a failed run in these blocks.
- **The CLI's files.** The CLI that the plugin starts read paths under its home directory regardless of the
  configuration directory it was given, and searched every parent directory for a `.claude` folder. It was given its
  own home directory and a private working directory under `/tmp` (mode 0700), so neither agent could see the other's state. Proven by a
  file trace before the first block: no open of the other agent's files, refused or not.
- **What leaked, and was closed before the next block.** A `git stash` in the agent's test checkout holding a line
  of the previous block's log, and the vendor's test leftovers in `/tmp`. Both were moved into a closed archive.
- **Events outside the agents.** The building agent's login expired during 61 (08:01Z to about 16:00Z on
  20261022), so one question went unanswered (above); everything else ran as planned.
