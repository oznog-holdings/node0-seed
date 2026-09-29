#!/usr/bin/env python3
"""rung4b-bench.py: rung 4b's checks and measurements (site/laptop/inference/rung4b.md), through the gateway.

Run on the agent box: AGENT_KEY and MASTER_KEY in the environment (from the vault, never printed), the
synthetic audio in $AUDIO (site/laptop/inference/bench/4b/make-audio.sh). Phases:
  routes    every route answers through the gateway (and which backend answered)
  fit       all four models loaded at once: resident per model, the tree's total, pressure, free %, swap
  swap      per model: unload, then the first answer (the load) against a warm answer; file cache warm
  thru      throughput per kind: chat tok/s, embeddings docs/s and tok/s, rerank docs/s, speech audio-min/min
            (and quality on the public set: retrieval recall, rerank hit@1, speech WER)
  load      several models working at once for 60 s: pressure, free %, swap sampled every 3 s
  closed    the backend held: fail-closed routes stay closed, local-code falls back to z.ai; the gateway's
            spend log for the window shows which api_base answered each request
Writes one JSON with everything to the path in $OUT, and prints a summary. Prints no key, no text of any
request beyond ids and counts.
"""
import warnings; warnings.filterwarnings("ignore", category=DeprecationWarning)
import json, os, re, subprocess, sys, threading, time, urllib.request, uuid, random, math, datetime

GW = "https://gw.seed.example.com"
KEY = os.environ["AGENT_KEY"]; MASTER = os.environ["MASTER_KEY"]
DIRECT = os.environ.get("DIRECT") == "1"          # the router itself, with the Mac's key: memory measurements only
if DIRECT: GW = "http://compute.seed.example.com:8080"; KEY = os.environ["MAC_KEY"]
AUDIO = os.environ.get("AUDIO", "/dev/shm/r4b")
B = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "site", "laptop", "inference", "bench", "4b")
DOCS = json.load(open(os.path.join(B, "docs.json"))); QUERIES = json.load(open(os.path.join(B, "queries.json")))
MAC = "seed@192.168.1.20"
ROUTER_MODEL = {"local-chat": "glm-4.7-flash", "local-code": "glm-4.7-flash", "local-embed": os.environ.get("EMBED_MODEL", "qwen3-embedding-4b"),
                "local-rerank": "qwen3-reranker-0.6b", "local-stt": "qwen3-asr-1.7b"}
R = {"started": datetime.datetime.utcnow().isoformat() + "Z"}

def call(path, body=None, files=None, key=KEY, method=None, timeout=900):
    """POST json or multipart to the gateway; returns (status, json, headers, seconds)."""
    url = GW + path; hdr = {"Authorization": "Bearer " + key}
    if DIRECT and body and body.get("model") in ROUTER_MODEL: body = dict(body, model=ROUTER_MODEL[body["model"]])
    if files is not None:
        bnd = uuid.uuid4().hex; parts = []
        for k, v in (body or {}).items():
            parts.append(f'--{bnd}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode())
        for k, (fn, data, ct) in files.items():
            parts.append(f'--{bnd}\r\nContent-Disposition: form-data; name="{k}"; filename="{fn}"\r\nContent-Type: {ct}\r\n\r\n'.encode() + data + b"\r\n")
        data = b"".join(parts) + f"--{bnd}--\r\n".encode(); hdr["Content-Type"] = "multipart/form-data; boundary=" + bnd
    elif body is not None:
        data = json.dumps(body).encode(); hdr["Content-Type"] = "application/json"
    else:
        data = None
    req = urllib.request.Request(url, data=data, headers=hdr, method=method or ("POST" if data else "GET"))
    t = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read(); dt = time.time() - t
            return r.status, json.loads(raw or b"{}"), dict(r.headers), dt
    except urllib.error.HTTPError as e:
        raw = e.read(); dt = time.time() - t
        try: j = json.loads(raw)
        except Exception: j = {"raw": raw[:200].decode(errors="replace")}
        return e.code, j, dict(e.headers), dt
    except Exception as e:
        return 0, {"exception": type(e).__name__, "msg": str(e)[:200]}, {}, time.time() - t

def mac(cmd, timeout=60):
    return subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "LogLevel=ERROR", MAC, cmd], capture_output=True, text=True, timeout=timeout).stdout

def router(path, body=None):
    """The router's own API on compute (load/unload/models), with the key read there."""
    b = "" if body is None else f"-H 'Content-Type: application/json' -d '{json.dumps(body)}'"
    out = mac(f"curl -s -H \"Authorization: Bearer $(cat ~/.config/seed/llama.key)\" {b} http://192.168.1.20:8080{path}")
    try: return json.loads(out)
    except Exception: return {"raw": out[:200]}

def status():
    return {m["id"]: m["status"]["value"] for m in router("/v1/models").get("data", [])}

def memory():
    """Resident per model child and the tree, system free %, pressure level, swap, compressor."""
    out = mac(r"""ps -A -o pid=,ppid=,rss=,command= | grep 'llama-server' | grep -v grep | cut -c1-400
      echo "---"; sysctl -n kern.memorystatus_vm_pressure_level; memory_pressure -Q | awk -F': ' '/free percentage/ {print $2}'
      vm_stat | awk -F: '/Swapouts|Pages occupied by compressor/ {gsub(/[ .]/,"",$2); print $1"="$2}'; sysctl -n vm.swapusage""")
    parts = out.split("---")
    procs = {}
    for line in parts[0].strip().splitlines():
        f = line.split()
        if len(f) < 4: continue
        m = re.search(r"--alias (\S+)", line)
        procs[m.group(1) if m else "router"] = round(int(f[2]) / 1024)
    tail = parts[1].strip().splitlines() if len(parts) > 1 else []
    d = {"per_process_mib": procs, "tree_mib": sum(procs.values())}
    try:
        d["pressure_level"] = int(tail[0]); d["free_pct"] = int(tail[1].strip().rstrip("%"))
        kv = dict(l.split("=", 1) for l in tail[2:] if "=" in l and not l.startswith("total"))
        d["swapouts"] = int(kv.get("Swapouts", 0)); d["compressor_pages"] = int(kv.get("Pages occupied by compressor", 0))
        d["swapusage"] = [l for l in tail if l.startswith("total")][0] if any(l.startswith("total") for l in tail) else ""
    except Exception as e:
        d["parse_error"] = str(e)
    return d

def backend(h):
    b = {k.lower(): v for k, v in h.items()}.get("x-litellm-model-api-base", "")
    return "compute" if "compute" in b else ("z.ai" if "z.ai" in b else (b or "-"))

# ---- the small requests, one per route --------------------------------------------------------------
WAV = sorted(f for f in os.listdir(AUDIO) if f.endswith(".wav"))
def small(route):
    if route in ("local-chat", "local-code"):
        return call("/v1/chat/completions", {"model": route, "max_tokens": 16, "temperature": 0,
                    "messages": [{"role": "user", "content": "Reply with the single word: ready"}]})
    if route == "local-embed":
        return call("/v1/embeddings", {"model": route, "input": ["one address for every model"]})
    if route == "local-rerank":
        return call("/v1/rerank", {"model": route, "query": "What is the capital of France?",
                    "documents": ["Paris is the capital of France.", "Bananas are yellow."]})
    if route == "local-stt":
        f = os.path.join(AUDIO, "doc209.wav")
        return call("/v1/audio/transcriptions", {"model": route, "response_format": "json"},
                    files={"file": ("doc209.wav", open(f, "rb").read(), "audio/wav")})
ROUTES = ["local-chat", "local-code", "local-embed", "local-rerank", "local-stt"]

def ok(route, st, j):
    if st != 200: return False
    if route in ("local-chat", "local-code"): return bool(j.get("choices"))
    if route == "local-embed": return len(j.get("data", [{}])[0].get("embedding", [])) > 0
    if route == "local-rerank": return len(j.get("results", [])) == 2
    if route == "local-stt": return len(j.get("text", "")) > 10
    return False

def phase_routes():
    out = {}
    for r in ROUTES:
        st, j, h, dt = small(r)
        out[r] = {"status": st, "ok": ok(r, st, j), "backend": backend(h), "seconds": round(dt, 2)}
        print(f"  route {r:13} {st} ok={out[r]['ok']} backend={out[r]['backend']} {dt:.1f}s", flush=True)
    return out

def phase_fit():
    for r in ROUTES: small(r)            # all four loaded
    st = status(); m = memory()
    print(f"  loaded: {st}\n  resident: {m['per_process_mib']} tree {m['tree_mib']} MiB; free {m.get('free_pct')}%, pressure level {m.get('pressure_level')}, swapouts {m.get('swapouts')}", flush=True)
    return {"status": st, "memory": m}

def wait_status(model, want, limit=120):
    t = time.time()
    while time.time() - t < limit:
        if status().get(model) == want: return time.time() - t
        time.sleep(0.5)
    return None

def phase_swap():
    out = {}
    for route in ["local-stt", "local-rerank", "local-embed", "local-chat"]:
        m = ROUTER_MODEL[route]
        small(route); warm = [small(route)[3] for _ in range(3)]; w = sorted(warm)[1]
        t = time.time(); router("/models/unload", {"model": m}); gone = wait_status(m, "unloaded"); unload_s = time.time() - t
        mem_after_unload = memory()["tree_mib"]
        st, j, h, cold = small(route)
        out[route] = {"model": m, "warm_s": round(w, 2), "unload_s": round(unload_s, 2), "first_after_unload_s": round(cold, 2),
                      "load_s": round(cold - w, 2), "ok": ok(route, st, j), "tree_mib_after_unload": mem_after_unload}
        print(f"  swap {m:22} unload {unload_s:.1f}s; first answer {cold:.1f}s vs warm {w:.2f}s -> load {cold - w:.1f}s (ok={out[route]['ok']})", flush=True)
    # one swap as a pair: speech out, embeddings in (the switcher's everyday move)
    for r in ("local-stt", "local-embed"): small(r)
    t = time.time(); router("/models/unload", {"model": "qwen3-embedding-4b"}); wait_status("qwen3-embedding-4b", "unloaded")
    small("local-embed"); out["pair_embed_reload_s"] = round(time.time() - t, 2)
    return out

def words(s):
    s = s.lower(); s = re.sub(r"[^a-z0-9' ]+", " ", s); return s.split()

def wer(ref, hyp):
    r, h = words(ref), words(hyp); d = list(range(len(h) + 1))
    for i in range(1, len(r) + 1):
        prev, d[0] = d[0], i
        for j in range(1, len(h) + 1):
            cur = d[j]; d[j] = min(d[j] + 1, d[j - 1] + 1, prev + (r[i - 1] != h[j - 1])); prev = cur
    return d[len(h)], len(r)

def cos(a, b):
    return sum(x * y for x, y in zip(a, b)) / (math.sqrt(sum(x * x for x in a)) * math.sqrt(sum(y * y for y in b)) + 1e-12)

def phase_thru():
    out = {}
    # chat: 3 runs of up to 256 tokens, then 2 at once
    runs = []
    for i in range(3):
        st, j, h, dt = call("/v1/chat/completions", {"model": "local-chat", "max_tokens": 256, "temperature": 0,
            "messages": [{"role": "user", "content": "Explain in about 200 words why a small site puts one model gateway in front of every model."}]})
        n = j.get("usage", {}).get("completion_tokens", 0); runs.append({"tokens": n, "s": round(dt, 2), "tok_s": round(n / dt, 1)})
    par = []
    def one():
        st, j, h, dt = call("/v1/chat/completions", {"model": "local-chat", "max_tokens": 256, "temperature": 0,
            "messages": [{"role": "user", "content": "List ten checks for a backup system, one line each."}]})
        par.append((j.get("usage", {}).get("completion_tokens", 0), dt))
    t = time.time(); th = [threading.Thread(target=one) for _ in range(2)]; [x.start() for x in th]; [x.join() for x in th]; wall = time.time() - t
    out["chat"] = {"sequential": runs, "two_at_once_total_tok_s": round(sum(p[0] for p in par) / wall, 1)}
    print(f"  chat: {[r['tok_s'] for r in runs]} tok/s single; {out['chat']['two_at_once_total_tok_s']} tok/s total with 2 at once", flush=True)
    # embeddings: all documents in batches of 16
    vecs = {}; toks = 0; t = time.time()
    for i in range(0, len(DOCS), 16):
        batch = DOCS[i:i + 16]
        st, j, h, dt = call("/v1/embeddings", {"model": "local-embed", "input": [d["text"] for d in batch]})
        toks += j.get("usage", {}).get("prompt_tokens", 0)
        for d, e in zip(batch, j.get("data", [])): vecs[d["id"]] = e["embedding"]
    dt = time.time() - t
    inst = "Instruct: Given a question, retrieve the passage of a site's documentation that answers it\nQuery: "
    st, j, h, _ = call("/v1/embeddings", {"model": "local-embed", "input": [inst + q["q"] for q in QUERIES]})
    qv = [e["embedding"] for e in j["data"]]
    ranks = []; top50 = []
    for q, v in zip(QUERIES, qv):
        order = sorted(vecs, key=lambda k: -cos(v, vecs[k])); ranks.append(order.index(q["doc"]) + 1); top50.append(order[:50])
    out["embed"] = {"docs": len(vecs), "seconds": round(dt, 1), "docs_s": round(len(vecs) / dt, 1), "tokens": toks, "tok_s": round(toks / dt),
                    "recall_at_1": sum(r == 1 for r in ranks) / len(ranks), "recall_at_5": sum(r <= 5 for r in ranks) / len(ranks),
                    "recall_at_50": sum(r <= 50 for r in ranks) / len(ranks)}
    print(f"  embed: {out['embed']['docs_s']} docs/s, {out['embed']['tok_s']} tok/s; recall@1 {out['embed']['recall_at_1']:.2f} @5 {out['embed']['recall_at_5']:.2f} @50 {out['embed']['recall_at_50']:.2f}", flush=True)
    # rerank: each query against its 50 nearest by embedding (how rerank is used)
    hits = 0; n = 0; t = time.time()
    for q, cand in zip(QUERIES, top50):
        st, j, h, _ = call("/v1/rerank", {"model": "local-rerank", "query": q["q"], "documents": [DOCS[c]["text"] for c in cand]})
        res = sorted(j.get("results", []), key=lambda r: -r["relevance_score"]); n += len(cand)
        if res and cand[res[0]["index"]] == q["doc"]: hits += 1
    dt = time.time() - t
    out["rerank"] = {"queries": len(QUERIES), "docs": n, "seconds": round(dt, 1), "docs_s": round(n / dt, 1), "hit_at_1": hits / len(QUERIES)}
    print(f"  rerank: {out['rerank']['docs_s']} docs/s; hit@1 {out['rerank']['hit_at_1']:.2f} (embedding alone {out['embed']['recall_at_1']:.2f})", flush=True)
    # speech: every clip, sequentially
    audio_s = 0; wall = 0; errs = 0; refw = 0; tag = 0
    for f in WAV:
        dur = os.path.getsize(os.path.join(AUDIO, f)) / 32000        # 16 kHz, 16-bit mono (header negligible)
        st, j, h, dt = call("/v1/audio/transcriptions", {"model": "local-stt", "response_format": "json"},
                            files={"file": (f, open(os.path.join(AUDIO, f), "rb").read(), "audio/wav")})
        text = j.get("text", ""); m = re.match(r"^language \w+<asr_text>", text); tag += bool(m)
        text = text[m.end():] if m else text
        ref = open(os.path.join(AUDIO, f[:-4] + ".txt")).read()
        e, nw = wer(ref, text); errs += e; refw += nw; audio_s += dur; wall += dt
    out["stt"] = {"clips": len(WAV), "audio_min": round(audio_s / 60, 2), "wall_min": round(wall / 60, 2),
                  "audio_min_per_min": round(audio_s / wall, 1), "wer": round(errs / refw, 4), "language_tag_present": tag}
    print(f"  stt: {out['stt']['audio_min']} min of audio in {out['stt']['wall_min']} min = {out['stt']['audio_min_per_min']} audio-min/min; WER {out['stt']['wer']:.3f} ({tag}/{len(WAV)} with the language tag, stripped)", flush=True)
    return out

def phase_load(seconds=60):
    stop = time.time() + seconds; samples = []; counts = {"chat": 0, "embed": 0, "rerank": 0, "stt": 0, "errors": 0}
    def loop(kind, fn):
        while time.time() < stop:
            st, j, h, dt = fn()
            counts[kind if st == 200 else "errors"] += 1
    fns = {"chat": lambda: call("/v1/chat/completions", {"model": "local-chat", "max_tokens": 200, "messages": [{"role": "user", "content": "Describe a UPS test in 150 words."}]}),
           "embed": lambda: call("/v1/embeddings", {"model": "local-embed", "input": [d["text"] for d in random.sample(DOCS, 16)]}),
           "rerank": lambda: call("/v1/rerank", {"model": "local-rerank", "query": QUERIES[0]["q"], "documents": [d["text"] for d in random.sample(DOCS, 50)]}),
           "stt": lambda: call("/v1/audio/transcriptions", {"model": "local-stt", "response_format": "json"}, files={"file": ("a.wav", open(os.path.join(AUDIO, WAV[0]), "rb").read(), "audio/wav")})}
    th = [threading.Thread(target=loop, args=(k, fns[k])) for k in ["chat", "chat", "embed", "rerank", "stt"]]
    base = memory(); [x.start() for x in th]
    while time.time() < stop:
        m = memory(); samples.append({k: m.get(k) for k in ("tree_mib", "free_pct", "pressure_level", "swapouts", "compressor_pages")}); time.sleep(3)
    [x.join() for x in th]
    out = {"seconds": seconds, "requests": counts, "base": {k: base.get(k) for k in ("tree_mib", "free_pct", "pressure_level", "swapouts")},
           "tree_mib_max": max(s["tree_mib"] for s in samples), "free_pct_min": min(s["free_pct"] for s in samples),
           "pressure_levels": sorted({s["pressure_level"] for s in samples}), "swapouts_delta": samples[-1]["swapouts"] - base["swapouts"], "samples": samples}
    print(f"  load 60 s (2 chat, embed, rerank, stt at once): {counts}; tree max {out['tree_mib_max']} MiB, free min {out['free_pct_min']}%, pressure {out['pressure_levels']}, swapouts +{out['swapouts_delta']}", flush=True)
    return out

def spend_since(t0):
    # summarize=false: one row per request (with a date range alone, this version sums per day)
    st, j, h, _ = call(f"/spend/logs?start_date={t0[:10]}&end_date={(datetime.datetime.utcnow() + datetime.timedelta(days=1)).strftime('%Y-%m-%d')}&summarize=false", key=MASTER)
    rows = j if isinstance(j, list) else j.get("data", []) if isinstance(j, dict) else []
    out = []
    for r in rows:
        s = r.get("startTime") or ""
        if s and s.replace(" ", "T")[:19] >= t0[:19]:
            out.append({"t": s[:19], "model_group": r.get("model_group"), "model": r.get("model"), "api_base": r.get("api_base"),
                        "status": r.get("status"), "call_type": r.get("call_type")})
    return out

def phase_closed():
    t0 = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%S")
    mac("touch ~/.local/state/seed/inference/held")
    t = time.time()
    while time.time() - t < 90:
        if "state=held" in mac("cat ~/.local/state/seed/inference/status") and not mac("pgrep -f llama-server").strip(): break
        time.sleep(2)
    held_after = round(time.time() - t, 1); procs = mac("pgrep -fl llama-server | wc -l").strip()
    res = {}
    for r in ROUTES:
        st, j, h, dt = small(r)
        res[r] = {"status": st, "backend": backend(h), "answered": ok(r, st, j), "seconds": round(dt, 1),
                  "error_type": (j.get("error") or {}).get("type") if isinstance(j.get("error"), dict) else None}
        print(f"  backend held: {r:13} -> {st} answered={res[r]['answered']} backend={res[r]['backend']}", flush=True)
    time.sleep(20)                                   # spend logs are written in batches
    rows = spend_since(t0)
    mac("rm -f ~/.local/state/seed/inference/held")
    t = time.time()
    while time.time() - t < 180:
        if status().get("glm-4.7-flash") == "loaded": break
        time.sleep(3)
    back = round(time.time() - t, 1)
    ext = [r for r in rows if r["api_base"] and "z.ai" in r["api_base"]]
    print(f"  spend log since {t0}Z: {len(rows)} rows; with z.ai's api_base: {len(ext)} ({[r['model_group'] for r in ext]}); back to loaded in {back}s", flush=True)
    for r in rows: print(f"    {r['t']} {r['model_group']:15} {r['status']:8} {r['call_type'] or '':22} {r['api_base'] or '-'}", flush=True)
    return {"window_start": t0 + "Z", "held_after_s": held_after, "llama_processes_while_held": procs, "results": res,
            "spend_rows": rows, "external_rows": ext, "resumed_loaded_after_s": back}

if __name__ == "__main__":
    phases = sys.argv[1:] or ["routes", "fit", "swap", "thru", "load", "closed"]
    for p in phases:
        print(f"== {p} {datetime.datetime.utcnow().strftime('%H:%M:%S')}Z", flush=True)
        R[p] = globals()["phase_" + p]()
    R["finished"] = datetime.datetime.utcnow().isoformat() + "Z"
    json.dump(R, open(os.environ.get("OUT", "/dev/shm/r4b-results.json"), "w"), indent=1)
