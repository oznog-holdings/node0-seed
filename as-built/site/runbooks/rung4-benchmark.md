# Rung 4: the benchmark protocol (prepared 20260927; revised the same day for a dedicated Mac)

**Revision 20260927 (owner):** compute is dedicated to the seed and nobody works on it. So the window
needs nobody off the Mac, phase F (coexistence) is **excluded**, and the ceiling is 48 GiB
(`site/laptop/inference/README.md`). Within it, the configurations are **L3** (llama.cpp, the
UD-Q3_K_XL chosen under the old 16 GiB ceiling), **L8** (llama.cpp, Q8_0, 31.8 GB) and **M8** (MLX,
mlx-community 8-bit, 31.8 GB: the same bits as L8, so L8 vs M8 decides the runtime, and L3 vs L8
decides the quantisation). Phases B to D run on compute against 127.0.0.1, so nothing but the runtime
differs (`bench/run-bench.sh`). The gateway's overhead is measured once, for the chosen configuration.
Phase E waits for the z.ai key; phase G needs a plug meter.
**Run 20260927:** `evidence/20260927-rung4-bench/summary.md` (decisions: llama.cpp stays, Q8_0, 64k in
two slots). To run M8 again, rebuild what was deleted after the run: `python3 -m venv
~/.local/share/seed/inference/mlx-venv`, then `pip install mlx==0.32.2 mlx-lm==0.31.3`, then
mlx-community/GLM-4.7-Flash-8bit at revision b3a202c6df57f7297fb351486938952352dcd25a (sha256 per
file against the revision's LFS oids). L3's file is in `pins` history.

**Questions:**
- **Local:** how fast and how large is the local model inside its ceiling (R4.06: "30B-class models
  run comfortably")?
- **Runtime:** does MLX beat llama.cpp on this Mac (design: "benchmark before the first instance of
  a class, record the result, and make the winner the standard")?
- **Hosted:** how does local compare with the hosted half on speed and cost?
- **Coexistence:** what does the person's work feel?

**When:** any time (the Mac is dedicated). The production server is held for the run and resumes after.
**Where:** everything on compute runs as seed. Requests go through the gateway, from the agent box.

## Fixed inputs (committed with the scripts before the first run)

- **Prompts:** `site/laptop/inference/bench/prompts.jsonl`, three sizes: short (~100 tokens),
  medium (~2,000) and long (~12,000, under the 16k context). Each has max_tokens 256,
  temperature 0 and a fixed seed.
- **Checkable tasks:** `site/laptop/inference/bench/tasks.jsonl`, 20 tasks with one right answer each
  (arithmetic, extraction from a given text, a small code output), scored by exact match. This is a
  sanity check, not a quality ranking.
- **Record** before each phase: `sw_vers`, the pins, AC power (`pmset -g ps`), thermal state
  (`pmset -g therm`), lid state, uptime, and memory as in the README (anonymous, wired, compressor,
  free %, pressure level).
- **The sampler** (`bench/sample.sh`, every 5 s, to CSV): llama-server's resident size, free %,
  pressure level, swapouts, compressor pages. It runs through every phase.

## Phases

| phase | what | measures | notes |
|---|---|---|---|
| A | `llama-bench -m <model> -p 512,4096 -n 128 -r 5` (the pinned build), server held first (`touch held`) so only one copy is in memory | prompt and generation tokens/s, median and spread | the raw engine speed |
| B | through the gateway, `glm-4.7-flash-local`, each prompt 5 times, streaming | time to first token, generation tokens/s (the server's `timings`), end-to-end time; the first request after an idle unload measured on its own (cold load) | the speed a caller sees |
| C | the sampler's maxima over A and B | peak resident size vs the ceiling (48 GiB); minimum free %; any pressure change or swapout | **pass:** peak ≤ 16 GiB, pressure stays 1, no swapouts |
| D | challenger: `mlx_lm.server` (pinned mlx-lm version, in a venv under the cache-tagged inference directory), the mlx-community GLM-4.7-Flash quant nearest to 3.5 bits that fits the ceiling, bound to 127.0.0.1, prompts sent over ssh; phases A to C repeated | the same measures | **decision:** MLX becomes the standard if its generation tokens/s is at least 15% higher at the same or lower peak memory, with the same task score (±1 of 20); otherwise llama.cpp stays. Recorded either way |
| E | hosted: the same prompts and tasks through the gateway to z.ai (`glm-4.7-flash-hosted`, `glm-4.7`), 3 runs each | time to first token, tokens/s, cost per run (spend logs), task score | after the two-key test; cost capped by a budgeted test key (under 0.50 USD) |
| F | ~~coexistence with a person working~~ | | **excluded** (owner, 20260927: the Mac is dedicated, nobody works on it) |
| G | power (R4.09): a plug meter at idle, while loaded, and while generating; `powermetrics` needs root, so it's the meter or nothing | watts | hands |

## Output

- **Where:** `evidence/<date>-rung4-bench/`, with the raw CSV and JSON and a `summary.md` (one table
  per phase, and the decision in phase D).
- **Records:** coverage R4.06 (tokens/s and memory), R4.09 (watts), and a diary entry.
- **If MLX wins:** a pull request changes `pins`, `serve.sh` and the gateway entry together. The
  old runtime stays pinned in history.
