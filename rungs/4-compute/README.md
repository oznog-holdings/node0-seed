# Rung 4: compute

**In plain terms.** A computer strong enough to run AI models at home, so private work never
leaves the house and there is no per-use bill. It can also transcribe audio and search your own
documents. Your assistants reach it through the same address as the hosted models, and work
that needs a frontier model's capability or speed, and does not need to stay private, can go to
a hosted model instead.

## What you get

A machine that runs a capable model locally, behind the gateway every agent already uses:

- **A local model as one more gateway entry.** Agents keep their keys and their one address,
  and the gateway decides which callers may use it.
- **Private work stays in the house**, on the local model.
- **Fixed cost.** The machine is paid for once. After that it costs electricity, 62 W more at
  the wall while generating (see Costs and measurements).
- **Watched like everything else.** Every 5 minutes a probe sends one completion through the
  gateway, and an alert fires when no completion has succeeded for 20 minutes. The alert rules
  have unit tests
  ([`inference.test.yaml`](../../as-built/site/infra/monitoring/rules/inference.test.yaml));
  cause the alert once yourself by stopping the server.

**Buy one or several, as funds allow.**
- A used M1 Max MacBook Pro with 64 GB (about $1,800): the least money for 64 GB of unified
  memory in 2026, and silent. Docked, lid closed, never a daily driver.
- A new Mac mini or Mac Studio at 64 GB or more ($2,900 and up), the same silicon family new.
- A DGX Spark ($4,999 and up): 128 GB unified, small, quiet, Linux.
- A box with GPUs: the most capacity per dollar, and the only loud, hot thing in this design.

Hosted models are cheaper and better for most small businesses. Local inference is the step
toward privacy, sovereignty and learning.

**What still fails.** A laptop-class machine is much slower than a hosted model on long
prompts. A 12,452-token prompt took 84 s locally and 3.6 s hosted, so local suits short and
private work. [Rung 4b](../4b-models/) puts a hosted coding model behind the local coding
route as its fallback.

Stop here if you want private inference and your agents already work well enough.

## Decisions and options

**A used Apple-silicon laptop with 64 GB, dedicated to the Seed.** Apple silicon shares its
memory between CPU and GPU, so a 64 GB machine can hold a 30B-class model that would need an
expensive graphics card elsewhere. We used an M1 Max. Shared with a person's daily work, the
model was capped at 16 GiB. Dedicating the machine raised the cap to 48 GiB and allowed Q8_0,
the model's weights stored at 8 bits (a quant is such a reduced-precision copy).
*Would change it:* you already own a GPU box with 24 GB or more of video memory, or you want
several people using the model at once (a laptop serves one or two requests at a time).

**The runtime: llama.cpp's `llama-server`, one model, fixed context and slots.**
- It allocates its memory at start, so its size is known before it runs, and a ceiling holds
  by construction. Ollama loads and unloads models per request and sizes context per request,
  which makes a ceiling hard to guarantee.
- One binary and one model file, each pinned by sha256 in the repository.
- It runs from an unprivileged user's home, with no installer and no system service of its
  own, and exposes `/health` and metrics for monitoring.

**MLX (Apple's machine-learning framework) ran as the challenger** on the same model at the
same bits, with the rule written down
before the run: MLX replaces llama.cpp if it generates at least 15% faster at the same or
lower peak memory, with the same task score. It tied on short and medium prompts. On a
12,452-token prompt it generated 24% faster and prefilled 58% faster, but its wired memory
peaked at 40.7 GB against 35.5 GB. That fails the memory condition, so llama.cpp stayed.
*Would change it:* your work is mostly long prompts. Then run MLX again.

**The model: GLM-4.7-Flash, Q8_0.** It is a 30B mixture of experts with about 3B active per
token, so it is fast on this GPU. Its licence is permissive, and it is the same family as the
hosted model in rung 4b, so the comparison there stays within one family. Q8_0 is
near-lossless. A 3-bit quant, which existed only to fit the old 16 GiB ceiling, generated 8%
faster. Twenty exact-answer tasks are too few to show what that quantisation loses, so its
one extra point (19 against 18) decides nothing.

**Other models worth trying.** We chose GLM-4.7-Flash for parity with the hosted model, not as
the best local model. In Christoph's own use, Qwen 3.8 has been one of the most capable local
models, and [Bonsai 2](https://huggingface.co/collections/prism-ml/bonsai-2) does well at
short tasks in very little memory, though not at long agentic work, programming or reasoning.
Neither has been measured on the bench.

**A memory ceiling, enforced by a supervisor.**
- Measure what the operating system needs with the model out, then set the ceiling below the
  GPU's own working-set limit. On the bench macOS committed 9.4 GB, and Metal let the GPU hold
  about 51.8 GiB (`recommendedMaxWorkingSetSize`). The ceiling is 48 GiB (49,152 MiB), which
  leaves macOS 16 GiB. The measurement is in
  [`as-built/site/laptop/inference/README.md`](../../as-built/site/laptop/inference/README.md).
- A small supervisor checks every 15 s. It stops the server if memory pressure leaves
  "normal" or free memory falls below 5%. It holds the server stopped if its resident size
  passes the ceiling, which means a configuration fault. It starts it again after 900 s of
  normal pressure with 60% free. The values are in
  [`pins`](../../as-built/site/laptop/inference/pins) and the script is
  [`supervise.sh`](../../as-built/site/laptop/inference/supervise.sh).
- Set the free-memory threshold below what the ceiling leaves free. At a 48 GiB ceiling on a
  64 GB machine, free memory is about 10% by arithmetic, so the first threshold of 20% stopped
  the server before the ceiling was reached. We lowered it to 5% on 20260928.
- Do not raise the GPU limit (`iogpu.wired_limit_mb`) to fit more. It needs admin rights and
  resets at every boot.

**Only the gateway may call it.** Every compute box is one more backend behind the gateway from
[rung 1](../1-infra/), and which model lives where is written in the repository instead of
clicked in a UI. The server requires a key, and only the gateway holds it. Agents reach the
model by the gateway's name, with their own keys, so spend and use stay metered in one place.
From rung 4b, one router process answers the gateway, on the network and with the key, and
starts a process per model behind it. Those listen only on the Mac itself (127.0.0.1), with no
key of their own, so the gateway on the infra box still reaches every model through the router.
Keep the Mac dedicated: any account logged in on it could call the model processes directly.

**Test every key class.** A key allowed a model must get an answer, and a key that is not
allowed must be refused by the gateway before the request reaches the backend. On 20260927 we
ran this for the hosted coding model: the agent key, allowed it, got an answer (HTTP 200), and
the monitoring key, not allowed it, was refused by the gateway (HTTP 403)
([data](../../data/rung4/hosted-benchmark-20260927.md)). The record does not show the same
test for the local model, so run it for each model you add. The steps are in
[`rung4-two-key-test.md`](../../as-built/site/runbooks/rung4-two-key-test.md).

## Costs and measurements

**Costs.** Estimated from the Seed's design prices (US, checked 20260920; [costs](../../costs.md)): $1,830 lean (a used
M1 Max plus an adapter) and $5,000 full (a Spark). A GPU box is its own budget.

Measured 20260927 on the M1 Max (64 GB), llama.cpp, GLM-4.7-Flash, one slot, 16k context,
temperature 0. Full data: [data/rung4](../../data/rung4/).

**Engine only (llama-bench, tokens per second, mean of 5):**

| Quant | Prompt 512 | Prompt 4096 | Generation 128 |
|---|---|---|---|
| Q3 (UD-Q3_K_XL) | 679 | 331 | 39.4 |
| Q8_0 | 791 | 379 | 36.2 |

**Through the server** (streamed, timed at the client; first-token time from the first run of
each prompt, because later runs hit the prompt cache):

| Runtime and quant | Prompt | First token | Generation | Total |
|---|---|---|---|---|
| llama.cpp Q8_0 | 15 tokens | 0.21 s | 35.3 tok/s | 6.4 s |
| llama.cpp Q8_0 | 2,062 tokens | 5.1 s | 31.0 tok/s | 13.2 s |
| llama.cpp Q8_0 | 12,452 tokens | 70.4 s | 18.1 tok/s | 84.4 s |
| MLX 8-bit | 12,452 tokens | 44.4 s | 22.5 tok/s | 55.6 s |

- **Memory.** Q8_0 peaked at 31,408 MiB resident in the benchmark (64% of the ceiling), with
  no swap. In production, with 64k of context in two 32k slots, it used 33,328 MiB resident
  with 43% free.
- **Tasks.** 20 short tasks with one exact answer each: Q3 19, Q8_0 18, MLX 18.
- **The gateway's overhead.** 2.5% on a short request.
- **Power** (20260928, [data](../../data/README.md#power-draw)): 5.9 W DC with nothing loaded; 61.7 W DC, and
  62 W more at the wall, with two chat requests generating. The idle draw at the wall was not
  measured.

**Check your own.** Measure first-token time from a cold prompt. A benchmark that repeats the
same prompt measures the prompt cache instead of the model. Our first pass reported 0.04 s
first tokens that were all cache hits.

## Runbooks

Not yet written as runbooks. Until they are, the bench's own versions are in
[as-built](../../as-built/site/laptop/inference/):
1. Dedicate the machine: its own user for the runtime, the person logged out, the machine set
   to stay awake on power. Not yet written; the as-built
   [`README.md`](../../as-built/site/laptop/inference/README.md) covers the user and the
   logged-out session, not the stay-awake setting.
2. Measure macOS with the model out; set the ceiling. As built: the ceiling section of the
   same file.
3. Install the pinned runtime and model; start the supervisor as a launch daemon. As built:
   [`install.sh`](../../as-built/site/laptop/inference/install.sh) and
   [`inference-admin-setup.sh`](../../as-built/site/laptop/inference/inference-admin-setup.sh).
4. Add the backend to the gateway; the key-class test. As built:
   [`rung4-two-key-test.md`](../../as-built/site/runbooks/rung4-two-key-test.md).
5. The benchmark: engine, server, tasks and memory, with the decision rule written first. As
   built: [`rung4-benchmark.md`](../../as-built/site/runbooks/rung4-benchmark.md).
6. The probe and its alert; cause the alert once by stopping the server. Not yet written.

## Configuration

Templates are not yet written. As built: the pins file
[`pins`](../../as-built/site/laptop/inference/pins), the supervisor
[`supervise.sh`](../../as-built/site/laptop/inference/supervise.sh), the launch daemon
[`co.oznog.seed.inference.daemon.plist`](../../as-built/site/laptop/inference/co.oznog.seed.inference.daemon.plist),
the gateway entry in [`config.yaml`](../../as-built/site/infra/litellm/config.yaml), the probe
in [`seed-metrics.sh`](../../as-built/site/infra/monitoring/seed-metrics.sh) and its rule in
[`inference.yml`](../../as-built/site/infra/monitoring/rules/inference.yml), and the benchmark
scripts in [`bench/`](../../as-built/site/laptop/inference/bench/).
