# Rung 4 benchmark, .

L3 llama.cpp UD-Q3_K_XL; L8 llama.cpp Q8_0; M8 MLX 8-bit. All on compute, 127.0.0.1, 16k context, one slot, temperature 0.

## Phase A: llama-bench (engine only; tokens/s, mean ± sd of 5)

| config | pp512 | pp4096 | tg128 |
|---|---|---|---|
| L3 | 679.0 ± 1.5 | 330.9 ± 4.3 | 39.4 ± 0.5 |
| L8 | 791.4 ± 2.1 | 379.3 ± 7.0 | 36.2 ± 0.6 |

## Phase B: through the server (streamed, client-timed; median of 5)

Time to first token from run 0 of each prompt only: runs 1-4 repeat the same prompt and both servers
reuse the previous run's prompt cache (their TTFT, 0.04-0.2 s, is a cache hit, not a prefill).

| config | prompt (tokens) | time to first token, cold (s) | prefill tokens/s (tokens ÷ TTFT) | generation tokens/s (median of 5) | total, cold (s) |
|---|---|---|---|---|---|
| L3 | short (15) | 0.31 | 48 | 38.3 | 6.3 |
| L3 | medium (2062) | 6.03 | 342 | 33.9 | 13.6 |
| L3 | long (12452) | 73.50 | 169 | 19.8 | 86.4 |
| L8 | short (15) | 0.21 | 72 | 35.3 | 6.4 |
| L8 | medium (2062) | 5.07 | 407 | 31.0 | 13.2 |
| L8 | long (12452) | 70.43 | 177 | 18.1 | 84.4 |
| M8 | short (15) | 0.29 | 52 | 34.5 | 7.4 |
| M8 | medium (2062) | 4.50 | 459 | 31.2 | 12.5 |
| M8 | long (12452) | 44.42 | 280 | 22.5 | 55.6 |

## Tasks (20, exact match of the last ANSWER line)

| config | correct | wrong (expected → got) | median generated tokens |
|---|---|---|---|
| L3 | 19/20 | t06 balbdees → baldes | 342 |
| L8 | 18/20 | t06 balbdees → baldes; t17 17:15 → 17:55 | 332 |
| M8 | 18/20 | t06 balbdees → baldes; t17 17:15 → 17:55 | 312 |

## Phase C: memory (sampled every 5 s over the whole configuration)

| config | peak resident (MiB) | vs ceiling 49,152 MiB | min free % | max pressure level | swapouts |
|---|---|---|---|---|---|
| L3 | 14,185 | 29% | 73 | 1 | 0 |
| L8 | 31,408 | 64% | 46 | 1 | 0 |
| M8 | 30,792 | 63% | 38 | 1 | 0 |

## Gateway overhead (the chosen configuration, from the agent box, short prompt, median of 5)

direct to compute: time to first token 0.23 s, 37.3 tok/s, total 7.07 s; through the gateway: 0.23 s,
36.3 tok/s, total 7.25 s (+2.5%).

## Decisions (20260927)

- **Runtime: llama.cpp stays.** The rule written before the run: MLX becomes the standard if its
  generation is at least 15% faster at the same or lower peak memory, with the same task score
  (±1). M8 vs L8: short and medium prompts equal (34.5 vs 35.3, 31.2 vs 31.0 tok/s), the long
  prompt faster (generation 22.5 vs 18.1, +24%; prefill 280 vs 177 tok/s, +58%), wired peak 5 GB
  higher (40.7 vs 35.5 GB), tasks 18 vs 18. Not a 15% win overall, and more memory. Recorded:
  if long prompts come to dominate the use, run M8 again.
- **Quantisation: Q8_0** (L8) over UD-Q3_K_XL (L3). Q3 existed only to fit the old 16 GiB ceiling.
  L3 is 8% faster at generation (39.4 vs 36.2 tok/s in llama-bench) and scored 19 vs 18 here, but
  20 exact-answer tasks can't see what 3.5-bit quantisation loses. Q8 is the near-lossless choice,
  and it fits the 48 GiB ceiling with room.
- **Context:** 64k in two slots of 32k (production, measured after restart: resident 33,328 MiB,
  free 43%, pressure normal).
- **Method notes:** runs 1 to 4 of each prompt were prompt-cache hits in the first pass, so time to
  first token is taken from run 0 only. M8's first speed pass (`speed-M8-cached.jsonl`) was all
  cache hits, because its warm-up ran the same prompts; it was rerun with `--prompt-cache-size 0`.
  bench.py now sends `cache_prompt: false`, and run-bench.sh starts MLX with the cache off.
- **Not run:** E (hosted; waits for the z.ai key), F (excluded: the Mac is dedicated), G (power;
  needs a plug meter).
