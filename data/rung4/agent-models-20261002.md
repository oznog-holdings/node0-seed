# Agent models on the compute Mac, 20260930 to 20261002

The compute Mac is an Apple M1 Max with 64 GB, serving through llama.cpp b11146 behind the site's
gateway, with a 48 GiB memory ceiling. The question was whether a local model could run the
site's long-running agent (the faults and the grading are on [the agents](../../agents/) page).
The answer at this tier was no; the summary is in [rung 4](../../rungs/4-compute/).

## Speed

Measured 20260930 to 20261001, one slot, through llama-server. "Reading" is prompt processing,
"writing" is generation, both in tokens a second.

| model | quantisation, file | KV cache, context | reading | writing |
|---|---|---|---|---|
| Qwen3.8-27B (dense) | Q8_0, 29.0 GB | f16, 32k | 100.0 | 6.89 |
| Qwen3.8-27B | Q8_0 | f16, 128k | 63.2 | 5.49 |
| Qwen3.8-27B | Q8_0 | q8_0, 128k | 63.3 | 2.06 |
| Qwen3.8-27B, in service | Q8_0 | f16 | 87 to 95 | 6.4 to 6.8 |
| Qwen3.8-27B | Q5_K_M, with MTP | | | 5.1 (7.0 without MTP) |
| Qwen3.6-35B-A3B (about 3B active) | UD-Q6_K_XL, 32.6 GB, with MTP | | 375 to 461 | 33 to 40 |
| Qwen3.6-35B-A3B | the same, without MTP | | 540 | 40.3 |
| Ternary Bonsai 2 27B | PQ2_0, 7.2 GB, PrismML's fork of llama.cpp | | 91 to 106 | 12.6 to 15.1 |

- **The same 26-call fault run, replayed against each.** The 27B took 2,699 s, Bonsai 2
  1,430 s, the 35B-A3B 420 s.
- **MTP** (the model's own draft head). The 27B accepted 77% of drafted tokens and the 35B-A3B
  76%, and both were still slower on this chip, with 8 to 12 GiB more memory.
- **A cold 128k prompt** took 34 minutes on the 27B.
- **Bonsai 2's footprint** was 18.3 GiB.

## Correctness, on the site's faults

Graded 20261001 to 20261002, from a clean slate where noted.

| model | a stopped container | an alert with nothing behind it | a probe reporting success on a dead target |
|---|---|---|---|
| Qwen3.8-27B | right, 40 to 47 min | facts right, cause wrong (21 min); right from a clean slate (36 min) | wrong uncapped (it repeated another model's wrong answer from the log); the real cause found from a clean slate |
| Qwen3.6-35B-A3B | wrong, then shallow with an explicit "run every read-only check" line | wrong | wrong |
| Ternary Bonsai 2 27B | right, 66 min with a 2,048-token reasoning cap (128 min without) | facts right, a wrong action proposed | wrong uncapped (the same repeated answer); not re-run clean |

- **A reasoning cap** (llama.cpp's `--reasoning-budget`, 1,024 tokens) limited reasoning as
  intended but did not speed the 27B up. It cut in on 8 to 17% of calls.
- **A clean slate matters.** Each model's earlier conclusions sat in the agent's log; the second
  model read the first one's wrong answer and repeated it. Clear the agent's log and memory
  before each test run.

## The prompt cache

- The 27B's own KV cache at f16: 64 KiB a token (2 GiB at 32k).
- A saved prompt in the RAM cache: about 92 KiB a token (a 16k-token prompt took 1,453 MiB).
- An evicted 19k-token prompt came back in 0.3 s against 185 s cold.
- 6 GiB and 3 GiB of cache pushed memory pressure to "warn" with the other models loaded; 2 GiB
  held through a full fill with pressure normal and 20% free.

## What it decided

On 20261002 the Mac stopped running agent models (Christoph). The site agent runs on a hosted
model with redaction in front of it, and the Mac serves the utility models of
[rung 4b](../../rungs/4b-models/).
