#!/usr/bin/env python3
"""Rung 4 benchmark driver (runbooks/rung4-benchmark.md). Standard library only.

  bench.py speed <label> <base_url> <model> <out.jsonl> [--key-file F] [--runs 5]
  bench.py tasks <label> <base_url> <model> <out.jsonl> [--key-file F]

Every request is streamed and timed on the client side, the same way for every runtime:
ttft = time to the first generated token (content or reasoning), gen_tps = (chunks - 1) /
(last - first); one streamed chunk is one token for both llama-server and mlx_lm.server.
Temperature 0. speed: max_tokens 256 per prompt in prompts.jsonl. tasks: max_tokens 4096,
scored by exact match of the last "ANSWER:" line against tasks.jsonl (a sanity check)."""
import json, re, sys, time, urllib.request, os

HERE = os.path.dirname(os.path.abspath(__file__))

HOSTED = '--hosted' in sys.argv   # through the gateway to a hosted model: no llama.cpp field; record the backend

def stream(base, model, prompt, max_tokens, key):
    b = {'model': model, 'messages': [{'role': 'user', 'content': prompt}],
         'max_tokens': max_tokens, 'temperature': 0, 'stream': True}
    if not HOSTED: b['cache_prompt'] = False   # llama-server: no reuse between runs (mlx_lm.server ignores it)
    body = json.dumps(b).encode()
    h = {'Content-Type': 'application/json'}
    if key: h['Authorization'] = 'Bearer ' + key
    req = urllib.request.Request(base.rstrip('/') + '/v1/chat/completions', data=body, headers=h)
    t0 = time.monotonic(); first = last = None; n = 0; text = []; reasoning = []
    with urllib.request.urlopen(req, timeout=1800) as r:
        backend = r.headers.get('x-litellm-model-api-base')   # the gateway says which backend answered
        for raw in r:
            line = raw.decode('utf-8', 'replace').strip()
            if not line.startswith('data:'): continue
            data = line[5:].strip()
            if data == '[DONE]': break
            try: ch = json.loads(data)
            except ValueError: continue
            for c in ch.get('choices') or []:
                d = c.get('delta') or {}
                piece = d.get('content') or ''
                rpiece = d.get('reasoning_content') or d.get('reasoning') or ''
                if piece or rpiece:
                    now = time.monotonic(); first = first or now; last = now; n += 1
                    text.append(piece); reasoning.append(rpiece)
    end = time.monotonic()
    return {'ttft_s': round(first - t0, 3) if first else None,
            'gen_tokens': n, 'gen_tps': round((n - 1) / (last - first), 2) if n > 1 and last > first else None,
            'total_s': round(end - t0, 3), 'content': ''.join(text), 'reasoning_chars': len(''.join(reasoning)),
            **({'backend': backend} if backend else {})}

def norm(s):
    return re.sub(r'\s+', '', s).strip().strip('.').lower()

def main():
    a = sys.argv[1:]
    mode, label, base, model, out = a[:5]
    key = None; runs = 5
    if '--key-file' in a: key = open(os.path.expanduser(a[a.index('--key-file') + 1])).read().strip()
    if '--runs' in a: runs = int(a[a.index('--runs') + 1])
    ntasks = int(a[a.index('--tasks') + 1]) if '--tasks' in a else 20
    with open(out, 'a') as f:
        if mode == 'speed':
            for p in map(json.loads, open(os.path.join(HERE, 'prompts.jsonl'))):
                for i in range(runs):
                    r = stream(base, model, p['prompt'], 256, key); r.pop('content')
                    row = {'label': label, 'mode': mode, 'prompt': p['id'], 'run': i, 'ts': int(time.time()), **r}
                    f.write(json.dumps(row) + '\n'); f.flush(); print(json.dumps(row))
        elif mode == 'tasks':
            ok = 0
            for t in list(map(json.loads, open(os.path.join(HERE, 'tasks.jsonl'))))[:ntasks]:
                q = t['q'] + '\n\nThink as needed, then end with one line of the form: ANSWER: <answer>'
                r = stream(base, model, q, 4096, key)
                c = re.sub(r'(?s)^.*</think>', '', r['content'])
                m = re.findall(r'ANSWER:\s*(.+)', c)
                got = m[-1].strip() if m else ''
                good = norm(got).replace('*', '') == norm(t['a'])
                ok += good
                row = {'label': label, 'mode': mode, 'task': t['id'], 'expected': t['a'], 'got': got[:80],
                       'correct': good, 'gen_tokens': r['gen_tokens'], 'gen_tps': r['gen_tps'], 'total_s': r['total_s'], 'ts': int(time.time()),
                       **({'backend': r['backend']} if 'backend' in r else {})}
                f.write(json.dumps(row) + '\n'); f.flush(); print(json.dumps(row))
            print(f'{label}: {ok}/{ntasks} correct')

if __name__ == '__main__':
    main()
