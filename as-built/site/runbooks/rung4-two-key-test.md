# Rung 4: the two-key test (prepared 20260927; run 20260927 22:51Z, in the form below)

## The run (20260927, 22:51 to 22:52Z; evidence/20260927-rung4b-hosted.txt)

The hosted half came as the owner's GLM Coding Plan key, so the test ran with the site's real keys and
z.ai's coding model, not the throwaway keys and `glm-4.7` the steps below were written for:
- **agent key → `glm-5.3-coding`: 200,** served by z.ai (`x-litellm-model-api-base:
  https://api.z.ai/api/coding/paas/v4`). The key's models are `glm-5.3-coding` and
  `glm-4.7-flash-local`, with 60 an hour on `glm-5.3-coding`.
- **monitoring-probe key → `glm-5.3-coding`: 403,** "key not allowed to access model" (its models
  are `seed-selftest` and `glm-4.7-flash-local` only).
- **The gateway's own limit falls back to the local model:** a temporary key with 1 an hour on
  `glm-5.3-coding`. Request 1 was served by z.ai; request 2 was served by compute
  (`http://compute.seed.example.com:8080/v1`). The key was then deleted.

**Not run as written:** the spend rows and z.ai's usage page (steps 5 to 6) and the budget stop (step 8):
the Coding Plan is a subscription with a request limit, not metered spend, so the limit above
stands in for the budget. Around the gateway (step 7), the Mac answering only the gateway's key
was shown with the local half on 20260927 (coverage R4.04).

## The test as prepared

**What it proves** (R4.04, R4.05; index › "a model gateway from rung 1 … spend metered per key"):
- **Metering:** one gateway meters two keys separately, across both halves of rung 4: the local
  Mac and hosted z.ai.
- **Access:** each key reaches only the models it's allowed.
- **No way around:** nothing reaches the Mac except through the gateway.
- **Budget:** a key's budget stops hosted spend.

"Two keys" here means two **virtual keys** on the gateway, one local-only and one local plus
hosted. If the owner meant something else by the name, the steps change, not the method.

**Runs when:** the vault item `zai api key` exists, and the z.ai entries in
`site/infra/litellm/config.yaml` are enabled by a pull request (model ids first checked against z.ai's
model list with that key). The owner's cap for hosted spend is recorded, and compute's `status`
says `state=running`.
**Cost:** under 1,000 hosted tokens, well under 0.01 USD at z.ai's list prices.
**Where:** the agent box; the gateway on infra's loopback over ssh (as `/tmp/gw.sh` did on 20260927), and
the master key from the vault, in memory only.

| step | action | pass |
|---|---|---|
| 0 | `deploy-infra-config` (adds `ZAI_API_KEY` to litellm.env), then recreate litellm (`tools/ui/run.sh edit-container.js litellm`); `GET /v1/models` | the list is exactly `seed-selftest`, `glm-4.7-flash-local` and the enabled z.ai names |
| 1 | `POST /key/generate`: **A** `twokey-local`, models `[glm-4.7-flash-local]`, max_budget 0.01, duration 2h; **B** `twokey-hosted`, models `[glm-4.7-flash-local, glm-4.7]`, max_budget 0.10, duration 2h | two keys returned; kept in memory only |
| 2 | A → `glm-4.7-flash-local`, B → `glm-4.7-flash-local`: the same fixed prompt ("Reply with the single word: ready"), max_tokens 200 | both 200, content "ready" |
| 3 | A → `glm-4.7` | **403** (model not allowed for this key), and nothing reaches z.ai |
| 4 | B → `glm-4.7`, the same prompt | 200; usage returned |
| 5 | wait for the spend batch (≤ 2 min), then `GET /spend/logs` for today, and `GET /key/info` for A and B | A: 1 row (local, tokens > 0, spend 0); B: 2 rows (local spend 0; hosted spend = tokens × z.ai's price, as LiteLLM's price map has it); key spend A = 0, B = the hosted row |
| 6 | the same hosted call's tokens in z.ai's usage page (the owner, or z.ai's API if the key can read usage) | the token counts match step 5 |
| 7 | around the gateway: `curl http://compute.seed.example.com:8080/v1/models` with no key, with key A, with key B | **401** three times (the Mac accepts only its own key, which only the gateway holds) |
| 8 | budget: `POST /key/update` B max_budget = its current spend; B → `glm-4.7` | refused with a budget error; no new row in z.ai's usage |
| 9 | `POST /key/delete` A and B; `GET /key/list` | neither alias listed |
| 10 | evidence `evidence/<date>-rung4-two-key/` (status codes, spend rows without content: the gateway logs no prompts) and the diary | |

**Failure means stop:**
- **Step 3 or 8 passes when it shouldn't:** hosted spend isn't under control. Disable the z.ai
  entries (a pull request) before anything else.
- **Step 7 answers 200:** the Mac is open around the gateway. Stop the server
  (`touch …/held`), then fix it.
