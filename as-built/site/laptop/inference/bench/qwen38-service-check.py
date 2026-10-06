#!/usr/bin/env python3
"""(A record of 20260930: the router's name for this model is local-chat from 20261001, and the reranker is retired.)
The Qwen3.8 configuration in the real service (run as seed on compute after deploying the preset): all four
models loaded in the router (qwen3.8-27b, the embedding, the reranker and the speech model), then one request to
qwen3.8-27b filling its context (the site's records, as qwen38-context.py), while the supervisor's tree size
(its status file), wired memory, pressure, swap and free % are sampled every 5 s. One JSON line on stdout.
  qwen38-service-check.py <corpus.txt> <ctx>"""
import json, os, re, subprocess, sys, threading, time, urllib.request
H = os.path.expanduser('~'); D = os.path.dirname(os.path.abspath(__file__))
PINS = dict(re.findall(r'^([A-Z0-9_]+)=(\S+)', open(f'{D}/../pins').read(), re.M))
SVC = f"http://{PINS['LISTEN']}:{PINS['PORT']}"; KEY = open(f'{H}/.config/seed/llama.key').read().strip()
ST = f'{H}/.local/state/seed/inference/status'
def sh(c): return subprocess.run(c, shell=True, capture_output=True, text=True).stdout
def post(path, body, timeout=7200):
    r = urllib.request.Request(SVC + path, json.dumps(body).encode(), {'Content-Type': 'application/json', 'Authorization': f'Bearer {KEY}'})
    with urllib.request.urlopen(r, timeout=timeout) as f: return json.load(f)
def models():
    r = urllib.request.Request(SVC + '/v1/models', headers={'Authorization': f'Bearer {KEY}'})
    with urllib.request.urlopen(r, timeout=30) as f: return {m['id']: m['status']['value'] for m in json.load(f)['data']}
def mem():
    v = sh('vm_stat'); page = int(re.search(r'page size of (\d+)', v).group(1))
    st = dict(l.split('=', 1) for l in open(ST).read().split() if '=' in l)
    return {'wired_mib': int(re.search(r'Pages wired down:\s+(\d+)', v).group(1)) * page // 2**20,
            'pressure': {'1': 'normal', '2': 'warn', '4': 'critical'}.get(sh('sysctl -n kern.memorystatus_vm_pressure_level').strip(), '?'),
            'swap_mib': float(re.search(r'used = ([\d.]+)M', sh('sysctl -n vm.swapusage')).group(1)),
            'free_pct': int(re.search(r'(\d+)%', sh('memory_pressure | tail -1')).group(1)),
            'tree_mib': int(st.get('server_rss_mib', 0)), 'state': st.get('state')}
corpus, ctx = open(sys.argv[1]).read(), int(sys.argv[2])
post('/v1/embeddings', {'model': 'qwen3-embedding-4b', 'input': 'warm'})
post('/v1/rerank', {'model': 'qwen3-reranker-0.6b', 'query': 'warm', 'documents': ['a', 'b']})
try: post('/v1/chat/completions', {'model': 'qwen3-asr-1.7b', 'messages': [{'role': 'user', 'content': 'warm'}], 'max_tokens': 1})
except Exception as e: pass   # the speech model wants audio; the request still loads it
time.sleep(20); loaded = models(); before = mem()
tok = lambda t: len(post('/tokenize', {'model': 'qwen3.8-27b', 'content': t})['tokens'])
target = ctx - 768; t = corpus[: int(len(corpus) * target / tok(corpus))]
for _ in range(6):
    n = tok(t)
    if target * 0.98 <= n <= target: break
    t = corpus[: int(len(t) * target * 0.99 / n)]
peak = {'wired_mib': 0, 'tree_mib': 0, 'swap_mib': 0.0, 'free_pct': 100, 'pressure': 'normal', 'states': set()}
stop = False
def sample():
    while not stop:
        m = mem(); peak['wired_mib'] = max(peak['wired_mib'], m['wired_mib']); peak['tree_mib'] = max(peak['tree_mib'], m['tree_mib'])
        peak['swap_mib'] = max(peak['swap_mib'], m['swap_mib']); peak['free_pct'] = min(peak['free_pct'], m['free_pct']); peak['states'].add(m['state'])
        if m['pressure'] != 'normal': peak['pressure'] = m['pressure']
        time.sleep(5)
th = threading.Thread(target=sample, daemon=True); th.start(); t0 = time.time()
r = post('/v1/chat/completions', {'model': 'qwen3.8-27b', 'max_tokens': 256, 'temperature': 0, 'ignore_eos': True,
         'chat_template_kwargs': {'enable_thinking': False}, 'messages': [{'role': 'user', 'content': t + '\n\nIn about 200 words, summarise what the records above say about the firewall.'}]})
stop = True; th.join(); tm = r.get('timings', {})
peak['states'] = sorted(peak['states'])
print(json.dumps({'ctx': ctx, 'models_loaded_before': loaded, 'before': before, 'prompt_tokens': tm.get('prompt_n'),
      'prompt_tps': round(tm.get('prompt_per_second', 0), 1), 'gen_tps': round(tm.get('predicted_per_second', 0), 2),
      'request_s': round(time.time() - t0, 1), 'peak': peak, 'ceiling_mib': int(PINS['CEILING_MIB']), 'models_loaded_after': models()}))
