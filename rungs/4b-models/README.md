# Rung 4b: many kinds of models behind one gateway

**In plain terms.** The compute box from [rung 4](../4-compute/) also searches your own
documents and transcribes audio, and your assistants reach every kind of model through the
address they already use. Private audio and documents never leave the house. Work that needs a
frontier model's capability or speed, and does not need to stay private, can go to a hosted
model instead.

## What you get

The compute box from rung 4 serves four kinds of models at once, each as a named route at the
gateway every agent already uses:

- **Chat and coding.** The rung 4 model.
- **Embeddings.** They turn documents and queries into vectors, for search over your own files.
- **A reranker.** It reorders search results by relevance, and on the bench put the right
  document first 95% of the time, against 80% for embeddings alone.
- **Speech-to-text.** It transcribes audio without the audio leaving the house.

A hosted model sits behind the same gateway for work that benefits from a frontier model's
capability and speed and does not need to stay private. On the bench that was a coding plan, so
only the coding route falls back to it; with a general plan, more routes could.

**Each kind says what happens when the local box cannot answer.** It falls back to a hosted
model, or it fails closed (has no fallback). Private audio always fails closed. With the local server held on 20260928,
the four fail-closed routes returned errors and the spend log showed no hosted request for
them; the coding route answered from the hosted model, and the gateway metered it.

**What still fails.** All four kinds share one GPU and one memory budget. Two chat requests at
once reached 48 tokens/s in total, so size the machine for one household's agents.

## Decisions and options

**The switcher: llama.cpp's own router mode.** One `llama-server` process loads each model on its
first request and unloads the least recently used when a cap is reached, with per-model arguments
from a presets file. The same binary serves chat, `/v1/embeddings`, `/v1/rerank` and
`/v1/audio/transcriptions`. It adds nothing to download, and every model's memory stays in one
process tree the supervisor can add up.
*Would change it:* your runtime lacks a router mode, or you mix runtimes. Then put llama-swap in
front; it was our next candidate.

**Only the router faces the network.** The gateway reaches every model through the one router
process, which listens on the network and requires the key. The process the router starts for
each model listens only on the Mac itself (127.0.0.1), and the router does not pass the key on,
so those processes have none. Nothing off the Mac can reach them; any account logged in on the
Mac can, which is one more reason to keep the Mac dedicated.

**Lower the supervisor's free-memory threshold before loading four models.** With all four
working, free memory was 17 to 18% with pressure normal. Rung 4's first threshold was 20%, and a
test that left 19% free stopped the server. Ours is 5% from 20260928 (rung 4, and
[`pins`](../../as-built/site/laptop/inference/pins)).

**Choose each model by a rule written before measuring.** Ours, for the three new models (the
chat model was chosen at rung 4, from Unsloth's conversion, before this rule):
1. a permissive licence (Apache-2.0 or MIT);
2. GGUF files (llama.cpp's model format) from the model's authors or from ggml-org, never a
   third party's conversion, pinned by revision and sha256;
3. runs on the pinned llama.cpp;
4. quantisation Q8_0 or better;
5. all four models loaded together fit the memory ceiling with at least 4 GiB to spare, measured at
   the working peak, not at idle;
6. then the best published score on the kind's usual benchmark, from the model card;
7. a tie goes to the smaller model.

**What the rule chose** (model cards read 20260928):

| Kind | Model | Why it won |
|---|---|---|
| Embeddings | Qwen3-Embedding-4B, Q8_0 | MTEB multilingual 69.45 (the 0.6B: 64.33); the 8B would not leave 4 GiB spare (all four about 44.5 GiB, estimated from file sizes) |
| Reranking | Qwen3-Reranker-0.6B, Q8_0 | MTEB-R 65.80 (bge-reranker-v2-m3: 57.03); the 4B and 8B exist only as third-party files |
| Speech-to-text | Qwen3-ASR-1.7B, Q8_0, with its projector | LibriSpeech other 3.38% word error rate (Whisper large-v3: 3.97%) |
| Chat and coding | GLM-4.7-Flash, Q8_0 | unchanged from rung 4 |

**Fallback or fail closed, per kind:**

| Route | When the local box cannot answer | Why |
|---|---|---|
| coding | falls back to the hosted coding model, for keys allowed to use both models | coding is what the hosted plan is for |
| chat | fails closed | the hosted plan covers coding tools only |
| embeddings | fails closed | vectors from another model do not match the stored ones, so a fallback would quietly corrupt the search index |
| reranking | fails closed | no hosted reranker, and the documents are private |
| speech-to-text | fails closed | private audio never leaves the house |

"Fails closed" means the route has no fallback and no hosted model shares its name. That held
in the tested configuration: with the local server stopped on 20260928 these routes returned
errors and the spend log showed no hosted request. A later routing change can undo it, so
re-run that test after any change to the routes.

**The hosted half: a subscription coding plan behind the gateway.** We used z.ai's GLM Coding Plan
for GLM-5.3, from the same family as the local model. The gateway allows it 2 requests in flight
and enforces the plan's 60 requests an hour on the one key allowed to use it. Our plan covers
coding tools. Putting it behind a gateway was Christoph's decision, so read your own plan's terms
before you do the same. Since the local GLM model was retired on 20260929 (rung 4), the hosted
model has no local fallback: a refusal from the plan now fails the request rather than quietly
running locally.

## Costs and measurements

Measured 20260928 on the M1 Max (64 GB), llama.cpp b11146, through the gateway, except the hosted
row. The test data was public (paragraphs of the node0 pages) or synthetic (speech made with macOS
`say`). Full data: [data/rung4](../../data/rung4/).

| What | Result |
|---|---|
| All four loaded, idle | 44,102 MiB (chat 33,910; embeddings 5,365; reranker 1,281; speech 3,468; router 78) |
| All four working at once, peak | 44,680 MiB, 4,472 MiB under a 48 GiB ceiling; free 17 to 18%, pressure normal, no swap |
| Chat | 35.8 to 39.6 tokens/s for one request, 48.0 tokens/s in total for two |
| Embeddings | 5.6 documents/s (541 tokens/s); recall on 20 queries: 0.80 at 1, 0.90 at 5 |
| Reranking | 20 documents/s; the right document first 95% of the time, against 80% for embeddings alone |
| Speech-to-text | 19.4 minutes of audio per minute; 6.5% word error rate after stripping the `language <L><asr_text>` tag every transcript carries |
| Swapping a model | unload 0.4 s; first answer from a model loaded again, with the file cache warm, 0.5 to 3.0 s; a cold load was not measured |
| Hosted coding model (20260927, through the gateway and the internet) | 125 to 256 tokens/s; a 12,452-token prompt answered in 3.6 s, against 84 s locally |
| Power | the mix draws about 58 W more at the wall than the machine at rest |

### What cost us time

- **llama-server's prompt cache defaults to 8 GiB of memory per model.** With it on, the small
  models grew by about 0.5 GB per request until the supervisor stopped them at the ceiling, and
  reranking put the right document first 40% of the time instead of 95%. Set `cache-ram = 0` for
  every model you do not chat with.
- **LiteLLM's `openai/` transcription parser rejects llama.cpp's usage object**
  (`input_tokens_details`, where OpenAI's is `input_token_details`). Use its `mistral/` parser with
  the Mac as `api_base`; nothing goes to Mistral.

## Runbooks

Not yet written as runbooks. The bench's own record is
[`rung4b.md`](../../as-built/site/laptop/inference/rung4b.md):
1. Write the model rule, read the model cards, choose, and pin every file by sha256. As built:
   `rung4b.md` and [`pins`](../../as-built/site/laptop/inference/pins).
2. The presets file and the router's cap on loaded models; the prompt cache off. As built:
   [`presets.ini`](../../as-built/site/laptop/inference/presets.ini).
3. One gateway route per kind; fallback or fail closed, stated in the configuration. As built:
   [`config.yaml`](../../as-built/site/infra/litellm/config.yaml).
4. The checks: every route answers; with the backend stopped, the fail-closed routes stay closed
   and the gateway's spend log shows no hosted request; the coding route falls back and is
   metered. As built: the checks table in `rung4b.md`.
5. The measurements above, on your own public or synthetic data. As built:
   [`rung4b-bench.py`](../../as-built/tools/rung4b-bench.py).

## Configuration

Templates are not yet written. As built: the presets file
[`presets.ini`](../../as-built/site/laptop/inference/presets.ini), the pins
[`pins`](../../as-built/site/laptop/inference/pins), and the gateway's routes in
[`config.yaml`](../../as-built/site/infra/litellm/config.yaml).
