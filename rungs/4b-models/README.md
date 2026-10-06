# Rung 4b: many kinds of models behind one gateway

**In plain terms.** The compute box from [rung 4](../4-compute/) searches your own documents,
transcribes audio, and cleans what your agents send to hosted models, and your assistants reach
every kind of model through the address they already use. Private audio and documents never leave the house. Work that needs a
frontier model's capability or speed, and does not need to stay private, can go to a hosted
model instead.

## What you get

The compute box from rung 4 becomes the house's utility box: small, private models, each a named
route at the gateway every agent already uses (as built from 20261002):

- **Search over your own files.** Embeddings turn documents and queries into vectors, and a
  reranker puts the right document first: 95% of the time on the bench, against 80% for
  embeddings alone.
- **Speech to text**, without the audio leaving the house.
- **Redaction and screening for your agents.** A secret scanner and PII-Tracer clean what the
  site agent, [Tender](../../agents/), is handed before it goes to a hosted model; injection
  screens are built and measured, and left off on purpose: the best combination caught 10 of 12
  planted instructions with 6 false alarms in 15 clean texts, and labelled none of those that
  reached the agent, while the agent's own refusal held in every run (below).
- **One general text model on demand** (Qwen3.6-35B-A3B) for drafts, digests and summaries a
  person checks, and Qwen3.8-27B loaded overnight for careful work such as the morning report.
- **A supervisor that sheds the large models first** under memory pressure, so search,
  transcription and redaction keep answering.

A hosted model sits behind the same gateway for work that benefits from a frontier model's
capability and speed and does not need to stay private. On the bench that is a coding plan, so
only the coding route falls back to it; with a general plan, more routes could.

**Each kind says what happens when the local box cannot answer.** It falls back to a hosted
model, or it fails closed (has no fallback). Private audio, documents and the agent's redaction
always fail closed: with redaction down, the agent's text is withheld, not sent raw. With the
local server held on 20260928, the fail-closed routes returned errors and the spend log showed no
hosted request for them; the coding route answered from the hosted model, and the gateway
metered it.

**What still fails.** Every model shares one GPU and one memory budget: the two large models do
not fit together, so they take turns. This box is too slow to run an agent itself
([rung 4](../4-compute/)).

**Built first as four models at once (20260928).** Before the utility tier, the box served the
rung 4 chat model beside embeddings, the reranker and speech to text; the decisions and figures
below from that day still hold for those three.

## The utility tier (from 20261002)

When the agent moved to a hosted model ([rung 4](../4-compute/)), this Mac became the box for
every model that is small, fast and private, so the agent's data is cleaned here before it
leaves. As the optional services arrive, their models join it here.

**Rule: small models stay resident, one large model at a time loads on demand, and the
supervisor unloads the large ones first.** A box that stops its whole server under memory
pressure loses every route at once; one that sheds its biggest model first keeps search,
transcription and redaction answering.

| model | what it does | route | memory |
|---|---|---|---|
| Qwen3-Embedding-4B, Q8_0 | embeddings | `local-embed` | 5.2 GiB, resident |
| Qwen3-Reranker-0.6B, Q8_0 | reranking | `local-rerank` | 1.2 GiB, resident |
| Qwen3-ASR-1.7B, Q8_0 | speech to text | `local-stt` | 3.3 GiB, resident |
| gitleaks with the site's rules | secrets, deterministic | `/utility/secrets` | one encoder service, 3.6 to 4.5 GiB in all |
| PII-Tracer | personal data | `/utility/pii` | in the same service |
| Qwen3Guard-Gen-0.6B and a DeBERTa classifier | prompt injection | `/utility/injection` | in the same service |
| Qwen3.6-35B-A3B, Q4 | drafts, summaries, digests | `local-text` | 22.4 GiB, on demand |
| Qwen3.8-27B, Q8_0, 40k context | careful overnight work, the morning report | on demand | about 30 GiB with its context |

- **Memory, measured 20261002 against a 48 GiB ceiling.** Everything resident plus the 35B-A3B
  idles at 35.6 to 36.9 GiB and peaked at 37.9 GiB under a realistic load, with pressure normal
  in all 29 samples and no swap. With the 27B in its place, about 43 GiB. The two large models
  together, about 65 GiB, do not fit, so they take turns.
- **The unload order, tested under pressure.** With 16 GiB held outside the server, the supervisor
  unloaded the 27B within 10 s; with 24 GiB, the 35B-A3B too. The server never stopped.
- **The large models split the work.** The 35B-A3B wrote a morning report in 9 s and got it
  wrong (resolved alerts listed as firing); the 27B took 85 s and got it mostly right. On a
  weekly digest both found 8 of 10 events, in 79 s against 463 s. So the 27B writes the morning
  report overnight and the 35B-A3B drafts digests and summaries that a person checks.
- **The encoders need their own small service.** llama.cpp serves the language models, but not
  classifiers like PII-Tracer; they run in one Python service behind the gateway
  ([`encoders.py`](../../as-built/site/laptop/inference/encoders.py)).

**What each new model caught**, on sets written before any model ran (20261002):

| check | result |
|---|---|
| gitleaks alone, on secrets | 6 of 9 planted found, 0 false findings in 8 clean texts |
| gitleaks and PII-Tracer's secret class together, on secrets | 20 of 20 on a second set (gitleaks alone 5, PII-Tracer alone 1, both 14) |
| personal data: PII-Tracer | 14 of 14 planted; it also masked 10 harmless spans (times, hashes) in 8 clean texts |
| prompt injection: Qwen3Guard / DeBERTa / Prompt Guard 2 | 7, 9 and 4 of 12 caught; 1, 4 and 1 false alarms in 15 |
| prompt injection: any of the three | 10 of 12, 6 false alarms |
| classifying alerts: GLiNER2.5 | type 22 of 50, then 45 with label descriptions; urgency 15, then 16 |

- **No injection screen is a gate.** The best combination missed 2 of 12 and raised 6 false
  alarms, and none labelled the instructions planted in the agent's own intake. The screen is
  built and off; the agent's own refusal is what held ([the agents](../../agents/)).
- **GLiNER waits for documents.** Urgency is beyond it without training, so it is out of the
  agent's path and comes back with a document service, where sorting by type is its job.

**The server: llama.cpp, against oMLX, measured 20261002.** llama.cpp's router read prompts 17%
faster, embedded 25% faster and reranked 18% faster, and its memory peaked at 33.1 GiB against
oMLX's 38.5 GiB, a peak 10.6 GiB above its idle, which is what counts against a ceiling. Their outputs matched
(embeddings at a cosine of 0.9995). oMLX shed models by memory by itself, which is the feature a
box of many models needs; our supervisor now does the same.
*Would change it:* a later oMLX release with a steady peak; it was two days into 0.7.0.

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
