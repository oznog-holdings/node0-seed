# The GPU agent path: turning it on and off

Hermes on Qwen3.8-27B served from a GPU node, reached through the site's gateway as the route `gpu-chat`. It ran
for the GPU day (20261006 to 08) and the re-test (20261009 to 12). **State since 20261012: OFF** (the owner's decision after
the re-test), with everything kept to turn it on again with the same config, setup and model key; the node's tailnet
auth key is the one exception: it was single-use, so turning on needs a new one under the same vault name. The record:
`evidence/20261006-gpu-day/`, `evidence/20261009-retest/`.

## What is kept while it is off

| part | where | while off |
|---|---|---|
| the switch | `site/infra/litellm/gpu-chat.switch` | `off` |
| the route | `site/infra/litellm/gpu-chat.yaml` | in the repo, not deployed |
| the probe and its alerts | `site/infra/monitoring/seed-metrics.sh` (section 8), `rules/inference.yml` (GpuChatDown, GpuChatFlapping, GpuChatStale) | the probe runs only while the route is deployed, so no series and no alert |
| the model key | vault item **"gpu-test model key"** | kept; not in the gateway's environment while off |
| the node's tailnet key | vault item **"tailscale authkey gpu-test"** | the name kept; its key is spent (single-use): turning on needs a new one (below) |
| the tailnet policy | `site/tailnet/acl.hujson`: `tag:gpu-test` in tagOwners; the acl `infra → tag:gpu-test:8080`; the policy tests' gpu-test entries (it reaches none of infra, the agent box or core; infra reaches its :8080, not its :22) | kept, live and in the repo |
| Hermes's config for it | `tools/gpu-day.sh hermes-gpu <ctx>` renders it from `nixos/modules/site-agents/hermes-config.yaml` | Hermes paused (its marker), still on gpu-chat |
| the switches | `tools/gpu-day.sh` (status, check, route-on, hermes-gpu, hermes-mac, route-off) | none |

## The node's server, as it ran for the fixed-server blocks (45, 52, 53)

Bosun's node (di3), on the tailnet as **`gpu-test`**, tag **`tag:gpu-test`**, ephemeral. The exact command line is
Bosun's record; the settings it must have:

- **llama-server**, llama.cpp build **b9190** (CUDA); its OpenAI API listened on **127.0.0.1:18080** on its host, and the
  tailnet node `gpu-test` forwarded its **:8080** to it. The route's address stays the node's tailnet address on 8080
  (as the ACL and gpu-chat.yaml say).
- **The model:** Qwen3.8-27B, Unsloth **UD-Q4_K_XL** (sha256 `3f227079003add2511437e5b1e94812e363385225bf6a9b47b0054a72bc8b01e`),
  served as the alias **`qwen3.8-27b-gpu`**.
- **Context 131072, `--parallel 1`** (one slot at 131072), KV cache q8_0.
- **`--no-cache-prompt`** (since 20261010 15:50:12Z): prompt-cache reuse aborted the server on Qwen3.8's hybrid layers
  every ~10 min (llama.cpp issue #28425; fix PR #28007). Re-enable only when that fix is merged, then re-prove: the
  gateway probe and GpuChatFlapping show a crash loop.
- **`--api-key`**: the value of the vault item "gpu-test model key".
- Thinking on (the server's template default); Hermes's main turns keep it, its compression turns it off.
- Speeds then: ~46 tok/s generation; prompt reading ~2.9k tok/s at ~18k context, ~2.2k at ~49k.

## Turning it on

1. **The node.** Bosun brings di3 up as `gpu-test` with the server above.
   - **Its tailnet key: always a new one.** The key last stored as **"tailscale authkey gpu-test"** is spent (it was
     single-use), and auth keys also expire. Mint a new **`tag:gpu-test`** key (single-use and ephemeral, as before) in
     the tailnet admin and store it under **the same vault name**, replacing the old value. The node, the tag, the ACL
     lines and the route stay the same.
   - **The server's address:** llama-server on 127.0.0.1:18080 on its host, the tailnet node forwarding :8080 to it
     (as before); nothing on the site changes for that.
2. **The tailnet policy:** check the gpu-test lines above are still in the live policy (they are kept; if someone
   removed them, restore them from `site/tailnet/acl.hujson`).
3. **From the agent box:** `tools/gpu-day.sh status`, then `tools/gpu-day.sh check` (the node's /health from infra,
   then /v1/models with the key: it must list `qwen3.8-27b-gpu`).
4. **The switch:** `on` as the last line of `site/infra/litellm/gpu-chat.switch`, with the date and the reason in its
   comment; reviewed and committed like any change.
5. **The route:** `tools/gpu-day.sh route-on`. It runs `site/bin/deploy-infra-config` (the route spliced in at the
   node's tailnet address, the key into the gateway's environment), recreates the gateway, adds gpu-chat to the
   gateway keys `tender` and `monitoring-probe`, and makes one real completion through the gateway (it must be 200).
6. **The probe:** within 5 minutes `seed_inference_probe_success{route="gpu-chat"}` is 1 on infra's Prometheus, and
   stays 1 (GpuChatFlapping watches for the crash loop's pattern).
7. **Hermes's config:** `tools/gpu-day.sh hermes-gpu 131072` (model gpu-chat, context 131072, compression at 0.65 of
   it, timeouts for ~40 tok/s), Hermes still paused. Any agent-box deploy re-runs tender-config, which puts the Mac's
   config back: re-render after each one (`--no-restart`, then restart the gateway while paused).
8. **Hermes working** (only on the owner's decision, which also says the active flag and whether it has hands):
   - its paused marker set aside, `tender-hermes-startup` and `tender-hermes` unmasked and started;
   - `hermes cron resume bd48b40e4847` (site-watch), and **check again after the gateway has settled that the job is
     still `[active]`**: a gateway that has just started can write its job list back over the resume (seen 20261011);
   - **its first periodic tick seen:** a site-watch run with a log line and a heartbeat (a quiet pre-check that skips
     the model also logs and pings), and hc hermes-work resumed by it.

## Turning it off

1. **Hermes first:** `hermes cron pause bd48b40e4847`, wait for a running site-watch run to end, its paused marker
   back, hc hermes-work paused. Its gpu-chat config stays (paused, it calls nothing): that is the config to turn it on
   with again. (`hermes-mac` would replace it with the Mac's; not part of turning it off.)
2. **The switch:** `off` in `site/infra/litellm/gpu-chat.switch`, with the date and the reason; reviewed and committed.
3. **The route:** `tools/gpu-day.sh route-off`: gpu-chat out of both gateway keys, `deploy-infra-config` (no route,
   no GPU_TEST_API_KEY), the gateway recreated; it prints that the route is no longer deployed.
4. **The alerts:** the probe stops at its next run, so GpuChatDown, GpuChatFlapping and GpuChatStale have no series
   (rules' test: `inference.test.yaml`, "the route switched off"). Check none is pending or firing.
5. **Keep** the vault item "gpu-test model key", the name "tailscale authkey gpu-test" (its spent value is replaced
   with a new key when it is turned on again), the ACL lines, `gpu-chat.yaml` and the probe's state file. Then the node can go back to
   Bosun's other use.

**Full removal** (`tools/gpu-day.sh teardown`, then the ACL lines removed live and from `acl.hujson`) deletes the model
key from the vault: only on the owner's word, and not the same as turning it off.
