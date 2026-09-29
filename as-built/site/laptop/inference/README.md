# Rung 4 on compute: the local model backend

compute (MacBook Pro M1 Max, 64 GB). The owner put rung 4 on it on 20260927, while it was still his
daily Mac, with three conditions: the model runtime stays inside the `seed` user; a memory ceiling
leaves the person's work room; that choice is recorded (this file). Later that day he made it
**dedicated to the seed**: he doesn't use it, and his desktop session is logged out. The runtime
stays inside seed, and the ceiling was recalculated for a dedicated machine (below).

## What runs (all pinned in `pins`)

**From 20260928, rung 4b (rung4b.md):** llama-server runs in **router mode**, with four models from
presets.ini: glm-4.7-flash (chat and coding, loaded at start), qwen3-embedding-4b, qwen3-reranker-0.6b
and qwen3-asr-1.7b. Each is loaded on its first request, and all four fit at once (working peak
44,680 MiB). The gateway names them local-chat, local-code, local-embed, local-rerank and local-stt;
only local-code falls back to hosted. The table below is the chat model, as chosen on 20260927.

| part | choice | where |
|---|---|---|
| runtime | llama.cpp v0.5.0 (build b11146), `llama-server`, the release's macOS arm64 binary, sha256 checked | `~seed/.local/share/seed/inference/llama.cpp/` |
| model | GLM-4.7-Flash (Z.ai; 30B-A3B MoE, MIT), unsloth Q8_0 GGUF, 31.84 GB, Hugging Face revision and sha256 pinned (UD-Q3_K_XL until the 48 GiB ceiling and the benchmark, 20260927) | `~seed/.local/share/seed/inference/models/` |
| address | `http://compute.seed.example.com:8080/v1` (the LAN address only), OpenAI-compatible; two slots of 32k tokens, no idle unload | |
| access | only callers with the key in vault item **compute llama api key** (the gateway); `/health` is open | `~seed/.config/seed/llama.key` (0600) |
| gateway name | `glm-4.7-flash-local` | `site/infra/litellm/config.yaml` |

Both directories carry `CACHEDIR.TAG`, so seed's backup skips them: they come back from the pins
(`install.sh`), not from a restore.

## Why this runtime (the pages name none: F-MAC)

Chosen against Ollama, LM Studio and MLX (`mlx_lm.server`), for what this machine needs:

1. **A ceiling that holds by construction.** llama-server loads one model with a fixed context and a
   fixed number of slots, and allocates its KV cache at start. So its size is known before it runs.
   Ollama loads and unloads models on demand, and sizes context per request. LM Studio's limits are
   set in its GUI.
2. **"Written in the repo, not clicked in a UI"** (index › Rung 4): one binary and one file, each
   pinned by sha256 in `pins`. There's no model registry with mutable tags (Ollama) and no GUI
   state (LM Studio, which is also closed source).
3. **No admin rights needed:** it runs from seed's home. No installer, no system service of its own.
4. **Built for being watched:** `/health` for the staleness probe (R4.11), and `--metrics` for Prometheus.
5. **It gives the memory back:** `--sleep-idle-seconds` unloads the model when idle. On a person's
   Mac, 14 GB held for nobody is the wrong default.

MLX is usually faster on Apple silicon, so the benchmark ran it as the challenger on the same
model at the same bits (20260927, `evidence/20260927-rung4-bench/summary.md`). It was equal on
short and medium prompts and faster on a 12k-token prompt (+24% generation, +58% prefill), but it
held 5 GB more. By the rule written before the run, llama.cpp stays; run MLX again if long prompts
come to dominate.

**Why this model:** it's 30B-class (R4.06) and a mixture of experts (about 3B active per token), so
it's fast on this GPU. Its licence is permissive, and it comes from the same family as the hosted
half (z.ai's GLM), which makes the local-vs-hosted comparison mean something. The quantisation
follows from the ceiling. Under 16 GiB only Q3 fitted. Under 48 GiB it's Q8_0 (near-lossless):
it's 8% slower than Q3, and the 20-task check can't see what Q3 loses.

## The ceiling: 48 GiB for the whole runtime (from 20260927, a dedicated Mac)

**Why it changed:** from 20260927 the owner doesn't use compute. His desktop session was logged out,
and with it his browser (about 14 GB) and his sync. The first ceiling, 16 GiB, was set beside that
person's work; its record is kept below.

**Measured 20260927 20:44Z, with the model held out and the owner logged out:**
- **macOS committed 9.4 GB:** 2.3 GB wired, 6.6 GB anonymous, 0.5 GB in the compressor. The
  resident sizes were root 6.3 GB and the `admin` account's leftover agents 0.5 GB.
- The file cache held 28 GB (reclaimable), and free showed 95%.
- **Metal's limit:** without an admin sysctl, it lets the GPU hold 53,084 MiB (about 51.8 GiB;
  `recommendedMaxWorkingSetSize` 55,662.79 MB). `iogpu.wired_limit_mb` is at its default.

**Chosen: 48 GiB (49,152 MiB).**
- **macOS keeps 16 GiB:** its measured 9.4 GB, plus about 6.5 GB for what comes and goes (Spotlight,
  software update, flow 2's backup, ssh sessions) and a file cache worth having.
- **Under Metal's limit:** 3.8 GiB below it, so the runtime never runs at the point where Metal
  starts refusing or evicting allocations.
- **Not higher:** going higher would mean raising `iogpu.wired_limit_mb` (admin, and reset at every
  boot) and taking memory from macOS.
- **The supervisor adds up the whole tree** (the router and every model it loaded) against the
  ceiling (rung 4b). **Its free-% backstop is 5% from 20260928, down from 20%:** at the ceiling,
  free is about 10% by arithmetic, so 20 yielded before the ceiling could be reached.
- **The supervisor's thresholds** (in `pins`) stay as a guard for macOS itself. It yields below
  5% free (`YIELD_FREE`; 20% until 20260928) or off "normal" pressure, and resumes at 60% free
  after 15 calm minutes (with the model unloaded, free is about 95%). On a dedicated Mac a yield means macOS is short of memory, so the
  probe's alert (R4.11) fires on it like any outage.
- **Model and context** within the ceiling are chosen by the benchmark (`site/runbooks/rung4-benchmark.md`).

### The first ceiling (20260927, a person's Mac): 16 GiB, superseded

- **Measured before install:** the person's apps held 38.8 GB anonymous, with 3.5 GB wired, 1.2 GB
  in the compressor and no swap. That left about 20 GB.
- **Chosen:** 16 GiB. This was one 16k slot, the prompt cache off, `--fit off`, idle unload after
  15 min, and the UD-Q3_K_XL quant, because Q4 didn't fit.
- **Measured loaded:** 14,141 MiB; free went from 91% to 68%.

**Enforced by `supervise.sh`**, the one process launchd runs as seed. Every 15 s it checks:
- **yield:** memory pressure leaves "normal", or free falls below `YIELD_FREE` → the server stops;
- **hold:** the server's resident size passes the ceiling → stopped and held for a person (a config fault);
- **resume:** `CALM_S` of normal pressure with `RESUME_FREE`% free → it starts again.

Each change is one line in `~seed/.local/state/seed/inference/events.log`; the current state is in
`status` in the same directory. **To pause it:** `sudo -u seed touch
/Users/seed/.local/state/seed/inference/held` (resume: remove the file).

## Running it

- **Install or update** (as seed): copy this directory to `~/.local/share/seed/laptop/inference/`,
  then `bash install.sh`.
- **The service:** LaunchDaemon `co.oznog.seed.inference` (as seed, Nice 5, from boot), installed
  20260927 by `inference-admin-setup.sh` through the owner's admin account (sha256 5183721b…d46f
  checked). seed restarts it with `sudo -n /bin/launchctl kickstart -k system/co.oznog.seed.inference`,
  its only sudo rule. The interim nohup start is retired: the admin script stopped it, and
  nothing starts the supervisor any other way.
- **Rotate the key:** change vault item "compute llama api key", then run `site/bin/deploy-infra-config`
  and recreate litellm (`tools/ui/run.sh edit-container.js litellm`: env files are read at creation).
  Then stream the key to `~seed/.config/seed/llama.key` and restart the server.

## Monitoring (R4.11)

Every 5 minutes infra's `seed-metrics.sh` (section 8) sends one real completion through the
gateway, using the `monitoring-probe` key, which is allowed `seed-selftest` and `glm-4.7-flash-local`.
It writes:
- `seed_gateway_selftest_success`;
- `seed_inference_probe_success`, `seed_inference_probe_duration_seconds`;
- `seed_inference_last_success_timestamp_seconds`, which survives failed runs in a state file.

The alerts are in `site/infra/monitoring/rules/inference.yml` (unit-tested):
- **InferenceBackendStale:** no completion for 20 minutes. This covers a yield or a hold, which on
  a dedicated Mac should page too.
- **GatewaySelftestFailing:** the gateway fails its own self-test.
- **InferenceProbeNeverSucceeded:** the probe has never succeeded.

## Not done yet

- R4.10: compute as a node_exporter target and UPS client (both need an admin on the Mac).
- The two-key test and the benchmark's phase E (both wait for the z.ai key), and phase G (power: a meter).
