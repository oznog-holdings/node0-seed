# Rung 4b, local: four kinds of model on compute, behind the gateway

**Retired 20260929 (the owner's decision): glm-4.7-flash**, the chat and coding model below. Its routes
(`local-chat`, `local-code`, `glm-4.7-flash-local`) are gone from the gateway and its preset is in
`presets.retired.ini`; the rest of this page is the record of rung 4b as built and measured. The three Qwen
models still run (README › What runs).

The owner's go of 20260927. Chat and coding (the GLM-4.7-Flash already running), embeddings, a
reranker and speech-to-text. Each kind is a named route at the gateway. A switcher loads and unloads
the models within the 48 GiB ceiling, and supervise.sh stays the guard.

**This file was written, and committed, before anything was measured** (the rules below). The
results are added afterwards, under "Measured", and nothing above that heading changes because of
them.

## The rules, written first

### The switcher

A switcher qualifies only if it:
1. **is pinned by sha256** and runs from seed's home without admin rights (as the runtime is);
2. **loads a model on its first request and unloads it** on command, or when a cap on loaded models
   needs room (least recently used), with per-model arguments (context, slots, pooling, projector);
3. **serves all four kinds** at OpenAI-compatible endpoints the gateway can route:
   `/v1/chat/completions`, `/v1/embeddings`, `/v1/rerank` and `/v1/audio/transcriptions`;
4. **keeps every model's memory in one process tree** under supervise.sh, so the guard can add it up.

**Among those that qualify, the one with the fewest new parts wins.** The node0 site runs llama-swap
in front of llama.cpp.
- **The pinned llama.cpp (b11146) has its own router mode:** `--models-preset`, `--models-max`,
  autoload, `/models/load` and `/models/unload`, LRU unload. The same binary also serves
  `/v1/embeddings`, `/v1/rerank` and `/v1/audio/transcriptions`, the last converted to a chat
  completion for an audio model.
- **If it passes 1 to 4 in practice, it's the switcher, with nothing new to download.** llama-swap is
  the next candidate if it fails.

### The models

The same rule for every kind:
1. **A permissive licence** (Apache-2.0 or MIT) on the upstream weights.
2. **GGUF from the model's authors or from ggml-org** (llama.cpp's own organisation), never a third
   party's conversion. Pinned by Hugging Face revision and LFS sha256.
3. **Runs on the pinned llama.cpp.**
4. **Quantisation Q8_0 or better** (near-lossless: the rule the chat model already follows).
5. **All four models loaded at once fit the 48 GiB ceiling with at least 4 GiB to spare.** The chat
   model holds 33,328 MiB in production, which leaves about 11 GiB for the other three.
6. **Among the candidates that pass 1 to 5, the best published score on the kind's usual benchmark**,
   from the model card:
   - embeddings: MTEB multilingual, mean over tasks;
   - reranking: MTEB-R;
   - speech-to-text: English WER on LibriSpeech test-other, then Fleurs-en.

   A candidate without a comparable published number loses to one with a number.
7. **A tie goes to the smaller model.**

**Applied** (cards read 20260928):

| kind | candidates | out, and why | chosen |
|---|---|---|---|
| embeddings | Qwen3-Embedding 0.6B / 4B / 8B (Apache-2.0, Qwen's GGUF); EmbeddingGemma-300M; Nomic v2 | 8B Q8_0 (7.7 GB): rule 5 (all four ≈ 44.5 GiB, under 4 GiB to spare). EmbeddingGemma: licence (Gemma terms, rule 1). Nomic v2: no MTEB-multilingual number on its card (rule 6) | **Qwen3-Embedding-4B Q8_0**: MTEB multilingual 69.45 (0.6B: 64.33) |
| reranking | Qwen3-Reranker 0.6B (ggml-org Q8_0) / 4B / 8B; bge-reranker-v2-m3 | 4B and 8B: only third-party GGUFs exist (rule 2) | **Qwen3-Reranker-0.6B Q8_0**: MTEB-R 65.80 (bge-reranker-v2-m3: 57.03, from the same table) |
| speech-to-text | Qwen3-ASR 0.6B / 1.7B (ggml-org, with projector); Voxtral-Mini-3B; Gemma-4-E4B | Voxtral: ggml-org has Q4_K_M only (rule 4), and its card reports no LibriSpeech figure (rule 6). Gemma-4-E4B: a general model, 7.7 GB at Q8_0 (rule 5) | **Qwen3-ASR-1.7B Q8_0 + projector Q8_0**: LibriSpeech other 3.38, Fleurs-en 3.35 (0.6B: 4.55, 4.39; Whisper-large-v3: 3.97, 4.08) |
| chat and coding | GLM-4.7-Flash Q8_0 (chosen 20260927, README) | none | unchanged |

**Pinned** (in `pins`, checked by install.sh):

| file | repo@revision | bytes | sha256 |
|---|---|---|---|
| Qwen3-Embedding-4B-Q8_0.gguf | Qwen/Qwen3-Embedding-4B-GGUF@f4602530db1d980e16da9d7d3a70294cf5c190be | 4,279,660,224 | b60ae5ce2dd6a0b77f82cadf21def1f310a3e10cde380ad0081b07a9d416949d |
| qwen3-reranker-0.6b-q8_0.gguf | ggml-org/Qwen3-Reranker-0.6B-Q8_0-GGUF@a02f48bb4f057028298c21fa033da2b30d7742d5 | 639,153,184 | 22c9979ce4fbcdc5acdc310c6641c32797eff1aa980b8f7a2db8a8ea23429a48 |
| Qwen3-ASR-1.7B-Q8_0.gguf | ggml-org/Qwen3-ASR-1.7B-GGUF@36a678687ba7d07a74ca70ccb0e36902e005fb80 | 2,165,034,944 | 58e22d0532d4eacaf034cfac17a6fed159f37c41390c710186783be439d1fc57 |
| mmproj-Qwen3-ASR-1.7B-Q8_0.gguf | (the same) | 355,709,344 | 46c1d533af3f354ceb37ce855dbceff7da7fa7cf1e6a523df3b13440bd164c0d |

### Per kind: fall back to hosted, or fail closed

| kind | route | when the Mac can't answer | why |
|---|---|---|---|
| coding | `local-code` | **falls back** to `glm-5.3-coding` (z.ai), only for keys that also name that model (today the agent key). Metered like any request | the hosted half exists for coding traffic, and the owner decided it may carry it (20260927) |
| chat | `local-chat` | **fails closed** | the only hosted deployment is the Coding Plan, and its terms cover coding tools, not chat (F-ZAI-CODING-PLAN) |
| embeddings | `local-embed` | **fails closed** | vectors from another model aren't comparable with the stored ones, so a fallback would silently corrupt a search index. The texts are the site's own |
| reranking | `local-rerank` | **fails closed** | no hosted reranker is configured, and the documents are the site's own |
| speech-to-text | `local-stt` | **fails closed** (the owner's rule: private audio) | no hosted speech deployment exists, and none may be added behind this route |

"Fails closed" means that the route has no fallback in `router_settings`, and that no hosted
deployment shares its name.

### The checks (all through the gateway)

1. Every route answers.
2. **Fail-closed:** with the backend stopped (the supervisor held), each fail-closed route returns an
   error, and no request to a hosted provider is seen. That's shown by the gateway's spend log for
   the window (no row with an external api_base), and by the z.ai request count staying where it was.
3. **Fallback:** with the backend stopped, `local-code` is answered by z.ai, and the spend log shows
   that request with z.ai's api_base.

### The measurements

1. What fits in 48 GiB at once: the resident total of the whole tree with all four loaded, pressure
   and free %.
2. The time to swap one model for another: unload one, then the first answer from another, cold and
   with the file cache warm.
3. Throughput per kind:
   - chat: tokens/s;
   - embeddings: documents/s and tokens/s;
   - reranking: documents reranked/s;
   - speech-to-text: minutes of audio per minute.
4. Memory pressure with several loaded and working at once.

**Test data: public or synthetic only.**
- **Text:** paragraphs of the node0 public pages (a public repository), with queries written for
  them.
- **Audio:** synthesised on compute by macOS `say` from those public paragraphs, so the transcript
  is known and a WER can be computed.

## Measured (20260928, evidence/20260928-rung4b-local/)

**Harness:** `tools/rung4b-bench.py`, from the agent box through the gateway with the agent key. A
sampler on compute recorded every model process's resident size every 0.5 s.

**The switcher passed 1 to 4.**
- It's llama.cpp b11146's router mode, with nothing new downloaded.
- It loads a model on its first request, unloads on `/models/unload` or by LRU at `--models-max 4`,
  and takes per-model arguments from presets.ini.
- It serves all four endpoints.
- Its children exit with it, and supervise.sh adds up the whole tree (`tree_rss`).
- It needed two things around it:
  - **Children listen on 127.0.0.1 without the key.** The router keeps the key and doesn't pass a
    per-model key on (tested). Only local accounts on compute can reach them.
  - **The gateway's `openai/` transcription parser rejects llama.cpp's usage object**
    (`input_tokens_details`, where OpenAI's is `input_token_details`). `local-stt` therefore uses
    LiteLLM's `mistral/` parser, with the Mac as api_base, so nothing goes to Mistral.

**Rule 5, measured at the working peak rather than at idle:**
- **The 4B embedder stays.**
- **What happened on the way:**
  1. The first runs held the tree at the ceiling twice (49,172 and 49,497 MiB), and I swapped the
     embedder to the 0.6B.
  2. The cause turned out to be llama-server's prompt cache in RAM, which defaults to 8 GiB per
     model. presets.ini set it to 0 for the chat model only, so the three new models grew by about
     0.5 GB per request (`vmmap`: MALLOC_LARGE).
  3. With `cache-ram = 0` everywhere, the 4B's working peak is 5,608 MiB, and the tree's is
     44,680 MiB. That leaves 4,472 MiB under the ceiling, which passes rule 5.
  4. By rule 6 the 4B is the choice again, and the 0.6B is gone from the pins and the disk.
- **The prompt cache had also broken reranking:** hit@1 was 0.40 with it and 0.95 without.

| measurement | result |
|---|---|
| **fits at once** | all four loaded: 44,102 MiB idle (GLM 33,910, embeddings 5,365, reranker 1,281, speech 3,468, router 78). **Peak with all four working: 44,680 MiB**, 4,472 MiB under the ceiling. Free 17 to 18%, pressure normal, no swap-outs |
| **swap one model for another** | unload 0.4 s. First answer after unloading, with the file cache warm: speech 1.2 s (load 0.8 s), reranker 0.5 s (0.4), embeddings 0.8 s (0.8), GLM 3.0 s (2.6). A cold load (file cache emptied) needs `purge` (admin), so it isn't measured. At the SSD's read speed it adds roughly the file size ÷ read rate |
| **chat** (GLM-4.7-Flash Q8_0) | 35.8 to 39.6 tok/s single, 48.0 tok/s in total with two at once (256-token answers) |
| **embeddings** (Qwen3-Embedding-4B Q8_0) | 5.6 documents/s, 541 tokens/s (678 paragraphs of the public pages, 16 per request). Recall on 20 written queries: @1 0.80, @5 0.90, @50 1.00 |
| **reranking** (Qwen3-Reranker-0.6B Q8_0) | 20.0 documents reranked/s (each query against its 50 nearest by embedding). hit@1 **0.95**, against 0.80 for embeddings alone |
| **speech-to-text** (Qwen3-ASR-1.7B Q8_0) | **19.4 minutes of audio per minute** (5.5 min of synthetic speech, 10 clips, 6 voices, in 0.28 min). WER 6.5% after stripping the model's `language <L><asr_text>` tag, which every transcript carries (callers strip it; forcing one language would remove it) |
| **several working at once** | 60 s of two chats, embeddings, reranking and speech together: 25 requests, 0 errors. Tree max 44,681 MiB, free min 17%, pressure normal throughout, swap-outs +0 |

**Checks** (through the gateway):

| check | result |
|---|---|
| every route answers | local-chat, local-code, local-embed, local-rerank and local-stt: 200, each answered by compute (the api_base the gateway reports) |
| fail-closed, backend held (supervisor `held`, no llama-server running) | local-chat, local-embed, local-rerank, local-stt: 500, not answered. The spend log for the window has 3 rows, and the only external one is local-code's fallback. The failed chat and embeddings rows carry the Mac's api_base. The failed rerank and speech requests write no row |
| fallback, backend held | local-code: 200, answered by z.ai (api_base `https://api.z.ai/api/coding/paas/v4/`). Metered: a spend-log row, `glm-5.3-coding` success, at 05:15:43Z |
| back after the hold | GLM loaded again 6.5 s after `held` was removed |

## Qwen3.8-27B: the local chat model from 20260930 (the owner's decision)

**What it is:** the site agent's model (Hermes), route `local-chat`, which fails closed. Long context matters more
than peak speed. The full record is in `evidence/20260930-qwen38/README.md`.

- **The model:** Qwen3.8-27B, official release (Apache-2.0).
  - A hybrid: 16 of its 64 layers keep a KV cache (64 KiB per token at f16), the other 48 are linear attention.
  - Native context 262,144 tokens.
- **The build:** no official GGUF exists, so `build-qwen38.sh` builds one from the release with llama.cpp b11146's
  converter and quantizer. Every source shard and the result are pinned by sha256.
- **Q8_0 weights (27.7 GiB):** Q6_K was no faster (generation isn't bandwidth-bound here), so quality wins.
- **The context, by measurement:** step by step with the embedding and reranker loaded beside it.

  | KV | context | prompt tok/s | gen tok/s at depth | peak wired |
  |---|---|---|---|---|
  | f16 | 32k | 100 | 6.9 | 42.4 GB |
  | f16 | 64k | 82 | 6.4 | 45.0 GB |
  | **f16** | **128k** | 63 | **5.5** | 49.4 GB |
  | q8_0 | 128k | 63 | 2.1 | 45.6 GB |
  | q8_0 | 192k | 51 | 1.4 | 48.1 GB |
  | q8_0 | 262k | 42 | 1.1 | 50.5 GB |

  No step swapped or left normal pressure.
- **Chosen: 131,072 tokens, one slot, f16 KV.**
  - f16 and q8 scored the same (5/5) on five facts planted at 10 to 90% depth of 127k tokens, but q8 generated at
    2.0 tokens/s against 6.7.
  - f16 beyond ~128k passes Metal's limit.
- **In the service**, with all four models loaded:
  - 5.4 tokens/s at full depth;
  - the tree peaked at 45,882 MiB, under the 49,152 MiB ceiling, which stays;
  - wired memory reached 53.4 GB, at Metal's limit: the thin margin to watch. `MODELS_MAX=3` is the first step if
    it ever bites.
- **The probe:** it covers `local-chat`. Its staleness alert waits 60 minutes, because one full-context prompt holds
  the one slot for ~34 minutes.

