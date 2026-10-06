#!/usr/bin/env python3
"""Qwen3.8-27B on compute: the largest context that runs well, by measurement (the owner's brief, 20260929).
Run as seed on compute, beside the inference service (whose router keeps the embedding and reranker loaded: this
script loads them through it first and checks after each step that they still are). For each context size it
starts a standalone llama-server (the pinned binary) on 127.0.0.1:8091 with the model, one slot, the given KV
cache type and flash attention, and records:
  - memory: wired MiB, macOS memory pressure level, swap used, system-wide free %, sampled every 2 s from the start
    of the load to the end of the request (the peak is reported);
  - speed: one long real prompt (the site's own records, cut to fill the context minus the answer) and 256 tokens
    of generation: prompt tokens/s and generation tokens/s at that depth, from llama-server's own timings.
  context   qwen38-context.py context <model.gguf> <corpus.txt> <kv: q8_0|f16> <ctx> [<ctx> ...]
  retrieval qwen38-context.py retrieval <model.gguf> <corpus.txt> <kv> <ctx>   facts planted at 10%..90% depth
Results: one JSON line per step on stdout (and ~/.local/state/seed/inference/bench-qwen38/). No content is kept.
"""
import json, os, re, subprocess, sys, threading, time, urllib.request

H = os.path.expanduser('~')
I = f'{H}/.local/share/seed/inference'
PINS = dict(re.findall(r'^([A-Z0-9_]+)=(\S+)', open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'pins')).read(), re.M))
SERVER = f"{I}/llama.cpp/{PINS['RUNTIME_TAG']}/llama-{PINS['RUNTIME_TAG']}/llama-server"
OUT = f'{H}/.local/state/seed/inference/bench-qwen38'; os.makedirs(OUT, exist_ok=True)
PORT = 8091; URL = f'http://127.0.0.1:{PORT}'
SVC = f"http://{PINS['LISTEN']}:{PINS['PORT']}"; SVC_KEY = open(f'{H}/.config/seed/llama.key').read().strip()

def sh(c): return subprocess.run(c, shell=True, capture_output=True, text=True).stdout
def mem():
    v = sh('vm_stat'); page = int(re.search(r'page size of (\d+)', v).group(1))
    wired = int(re.search(r'Pages wired down:\s+(\d+)', v).group(1)) * page // 2**20
    lvl = sh('sysctl -n kern.memorystatus_vm_pressure_level').strip()   # 1 normal, 2 warn, 4 critical
    sw = re.search(r'used = ([\d.]+)M', sh('sysctl -n vm.swapusage')); free = re.search(r'(\d+)%', sh('memory_pressure | tail -1'))
    return {'wired_mib': wired, 'pressure': {'1': 'normal', '2': 'warn', '4': 'critical'}.get(lvl, lvl),
            'swap_mib': float(sw.group(1)) if sw else None, 'free_pct': int(free.group(1)) if free else None}
def post(url, body, key=None, timeout=7200):
    r = urllib.request.Request(url, json.dumps(body).encode(), {'Content-Type': 'application/json', **({'Authorization': f'Bearer {key}'} if key else {})})
    with urllib.request.urlopen(r, timeout=timeout) as f: return json.load(f)
def get(url, key=None):
    r = urllib.request.Request(url, headers={'Authorization': f'Bearer {key}'} if key else {})
    with urllib.request.urlopen(r, timeout=30) as f: return json.load(f)
def service_models():   # the router's children and their state (loaded / unloaded)
    try: return {m['id']: m.get('status', {}).get('value', '?') for m in get(f'{SVC}/v1/models', SVC_KEY)['data']}
    except Exception as e: return {'error': str(e)[:80]}
def warm_service():     # the embedding and the reranker loaded in the service, as they will be beside the model
    post(f'{SVC}/v1/embeddings', {'model': 'qwen3-embedding-4b', 'input': 'warm'}, SVC_KEY)
    post(f'{SVC}/v1/rerank', {'model': 'qwen3-reranker-0.6b', 'query': 'warm', 'documents': ['a', 'b']}, SVC_KEY)

class Sampler(threading.Thread):
    def __init__(s): super().__init__(daemon=True); s.peak = None; s.worst = 'normal'; s.swap = 0.0; s.minfree = 100; s.stop = False
    def run(s):
        order = {'normal': 0, 'warn': 1, 'critical': 2}
        while not s.stop:
            m = mem(); s.peak = max(s.peak or 0, m['wired_mib']); s.swap = max(s.swap, m['swap_mib'] or 0)
            if m['free_pct'] is not None: s.minfree = min(s.minfree, m['free_pct'])
            if order.get(m['pressure'], 3) > order.get(s.worst, 3): s.worst = m['pressure']
            time.sleep(2)

def start(model, kv, ctx):
    args = [SERVER, '-m', model, '--host', '127.0.0.1', '--port', str(PORT), '-c', str(ctx), '-np', '1', '-fa', 'on',
            '-ctk', kv, '-ctv', kv, '--jinja', '--no-webui', '--cache-ram', '0', '-ngl', '999'] + os.environ.get('EXTRA_ARGS', '').split()   # e.g. EXTRA_ARGS='-ub 2048 -b 2048'   # mmap as the service (presets.ini)
    log = open(f'{OUT}/server-{kv}-{ctx}.log', 'w'); p = subprocess.Popen(args, stdout=log, stderr=subprocess.STDOUT)
    t0 = time.time()
    while time.time() - t0 < 600:
        if p.poll() is not None: return p, None
        try:
            if get(f'{URL}/health').get('status') == 'ok': return p, time.time() - t0
        except Exception: pass
        time.sleep(2)
    return p, None
def stop(p): p.terminate(); p.wait(timeout=60); time.sleep(5)
def ntok(text): return len(post(f'{URL}/tokenize', {'content': text})['tokens'])
def cut(corpus, target):  # a prefix of the corpus with at most `target` tokens and at least 98% of it (never over:
    # an overshoot eats the answer's room; 20260929, the first sweep's 64k step generated 29 tokens)
    n_all = ntok(corpus); t = corpus[: int(len(corpus) * min(1, target / n_all))]
    for _ in range(6):
        n = ntok(t)
        if target * 0.98 <= n <= target: break
        t = corpus[: int(len(t) * target * 0.99 / n)]
    return t
def chat(content, max_tokens, **kw):
    return post(f'{URL}/v1/chat/completions', {'messages': [{'role': 'user', 'content': content}], 'max_tokens': max_tokens,
            'temperature': 0, 'cache_prompt': True, 'chat_template_kwargs': {'enable_thinking': False}, **kw})

def context(model, corpus_file, kv, ctxs):
    corpus = open(corpus_file).read()
    for ctx in ctxs:
        warm_service(); before = mem(); s = Sampler(); s.start()
        p, load_s = start(model, kv, ctx)
        row = {'kv': kv, 'ctx': ctx, 'extra': os.environ.get('EXTRA_ARGS', ''), 'before': before}
        if load_s is None:
            s.stop = True; row['result'] = 'did not start'; row['log_tail'] = sh(f'tail -5 {OUT}/server-{kv}-{ctx}.log')
            print(json.dumps(row), flush=True); open(f'{OUT}/context.jsonl', 'a').write(json.dumps(row) + '\n'); stop(p); continue
        row['load_s'] = round(load_s, 1); row['loaded'] = mem()
        text = cut(corpus, ctx - 256 - 512)   # the question, the chat template and 256 answer tokens fit behind it
        q = text + '\n\nIn about 200 words, summarise what the records above say about the firewall.'
        t0 = time.time(); r = chat(q, 256, ignore_eos=True); dt = time.time() - t0   # always 256 tokens
        tm = r.get('timings', {}); s.stop = True; s.join()
        row.update({'prompt_tokens': tm.get('prompt_n'), 'prompt_tps': round(tm.get('prompt_per_second', 0), 1),
                    'gen_tokens': tm.get('predicted_n'), 'gen_tps': round(tm.get('predicted_per_second', 0), 2),
                    'request_s': round(dt, 1), 'after': mem(), 'peak_wired_mib': s.peak, 'worst_pressure': s.worst,
                    'max_swap_mib': s.swap, 'min_free_pct': s.minfree, 'server_rss_mib': int(sh(f'ps -o rss= -p {p.pid}').strip() or 0) // 1024,
                    'service_models': service_models()})
        print(json.dumps(row), flush=True); open(f'{OUT}/context.jsonl', 'a').write(json.dumps(row) + '\n')
        stop(p)

# retrieval: facts planted in the real corpus at five depths; each asked after the whole context is cached
FACTS = [(0.10, 'The spare key for the bench cabinet is kept in the blue tin labelled ORCHID-7.', 'What is the label on the tin that holds the spare key for the bench cabinet?', 'ORCHID-7'),
         (0.30, 'The owner\'s preferred maintenance day for the switch is the second Thursday of each month.', 'On which day of the month is the owner\'s preferred maintenance day for the switch?', 'second Thursday'),
         (0.50, 'The test UPS was bought for 212 euros from a shop in Ghent.', 'In which city was the test UPS bought?', 'Ghent'),
         (0.70, 'The passphrase hint for the old backup drive is "copper lantern 44".', 'What is the passphrase hint for the old backup drive?', 'copper lantern 44'),
         (0.90, 'The first packet capture of the new VLAN was saved as trunk-capture-5519.pcap.', 'What was the file name of the first packet capture of the new VLAN?', 'trunk-capture-5519.pcap')]
def retrieval(model, corpus_file, kv, ctx):
    corpus = open(corpus_file).read(); warm_service(); s = Sampler(); s.start()
    p, load_s = start(model, kv, ctx)
    if load_s is None: print(json.dumps({'kv': kv, 'ctx': ctx, 'result': 'did not start'})); stop(p); return
    text = cut(corpus, ctx - 2048)
    for d, fact, _, _ in sorted(FACTS, reverse=True):     # plant from the end, so earlier offsets stay right
        i = text.rfind('\n', 0, int(len(text) * d)) + 1; text = text[:i] + fact + '\n' + text[i:]
    rows = []
    for d, _, q, want in FACTS:
        r = chat(text + '\n\nAnswer from the records above only, in a few words. ' + q, 48)
        a = r['choices'][0]['message']['content'].strip(); tm = r.get('timings', {})
        rows.append({'depth': d, 'ok': want.lower() in a.lower(), 'answer': a[:80], 'prompt_n': tm.get('prompt_n'), 'gen_tps': round(tm.get('predicted_per_second', 0), 2)})
    s.stop = True; s.join()
    row = {'kv': kv, 'ctx': ctx, 'tokens': ntok(text), 'score': f"{sum(x['ok'] for x in rows)}/{len(rows)}", 'tasks': rows,
           'peak_wired_mib': s.peak, 'worst_pressure': s.worst, 'max_swap_mib': s.swap, 'min_free_pct': s.minfree, 'service_models': service_models()}
    print(json.dumps(row), flush=True); open(f'{OUT}/retrieval.jsonl', 'a').write(json.dumps(row) + '\n'); stop(p)

if __name__ == '__main__':
    m = sys.argv[1]
    if m == 'context': context(sys.argv[2], sys.argv[3], sys.argv[4], [int(x) for x in sys.argv[5:]])
    elif m == 'retrieval': retrieval(sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5]))
    else: print(__doc__); sys.exit(2)
