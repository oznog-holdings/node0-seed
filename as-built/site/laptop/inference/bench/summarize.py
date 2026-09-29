#!/usr/bin/env python3
"""summarize.py <bench dir>: summary.md from run-bench.sh's raw files (speed.jsonl, tasks.jsonl,
<label>-llama-bench.json, <label>-memory.csv). Medians over the runs; nothing is dropped."""
import csv, glob, json, os, statistics as st, sys

d = sys.argv[1]
rows = [json.loads(l) for l in open(os.path.join(d, 'speed.jsonl'))]
tasks = [json.loads(l) for l in open(os.path.join(d, 'tasks.jsonl'))] if os.path.exists(os.path.join(d, 'tasks.jsonl')) else []
labels = sorted({r['label'] for r in rows}, key=lambda x: ['L3', 'L8', 'M8'].index(x) if x in ('L3', 'L8', 'M8') else 9)
plen = {'short': 15, 'medium': 2062, 'long': 12452}
med = lambda xs: st.median(xs) if xs else None
out = ['# Rung 4 benchmark, ' + os.path.basename(d.rstrip('/')), '',
       'L3 llama.cpp UD-Q3_K_XL; L8 llama.cpp Q8_0; M8 MLX 8-bit. All on compute, 127.0.0.1, 16k context, one slot, temperature 0.', '',
       '## Phase A: llama-bench (engine only; tokens/s, mean ± sd of 5)', '', '| config | pp512 | pp4096 | tg128 |', '|---|---|---|---|']
for L in labels:
    f = os.path.join(d, f'{L}-llama-bench.json')
    if not os.path.exists(f): continue
    b = json.load(open(f)); cell = {}
    for t in b:
        k = f"pp{t['n_prompt']}" if t['n_gen'] == 0 else f"tg{t['n_gen']}"
        cell[k] = f"{t['avg_ts']:.1f} ± {t['stddev_ts']:.1f}"
    out.append(f"| {L} | {cell.get('pp512', '')} | {cell.get('pp4096', '')} | {cell.get('tg128', '')} |")
out += ['', '## Phase B: through the server (streamed, client-timed; median of 5)', '',
        'Time to first token from run 0 of each prompt only: runs 1-4 repeat the same prompt and both servers',
        'reuse the previous run\'s prompt cache (their TTFT, 0.04-0.2 s, is a cache hit, not a prefill).', '',
        '| config | prompt (tokens) | time to first token, cold (s) | prefill tokens/s (tokens ÷ TTFT) | generation tokens/s (median of 5) | total, cold (s) |', '|---|---|---|---|---|---|']
for L in labels:
    for p in ('short', 'medium', 'long'):
        rs = [r for r in rows if r['label'] == L and r['prompt'] == p]
        if not rs: continue
        r0 = [r for r in rs if r['run'] == 0][0]; ttft = r0['ttft_s']; tot = r0['total_s']; g = med([r['gen_tps'] for r in rs if r['gen_tps']])
        out.append(f"| {L} | {p} ({plen[p]}) | {ttft:.2f} | {plen[p] / ttft:.0f} | {g:.1f} | {tot:.1f} |")
out += ['', '## Tasks (20, exact match of the last ANSWER line)', '', '| config | correct | wrong (expected → got) | median generated tokens |', '|---|---|---|---|']
for L in labels:
    ts = [t for t in tasks if t['label'] == L]
    if not ts: continue
    wrong = '; '.join(f"{t['task']} {t['expected']} → {t['got'] or '(none)'}" for t in ts if not t['correct'])
    out.append(f"| {L} | {sum(t['correct'] for t in ts)}/{len(ts)} | {wrong or '-'} | {med([t['gen_tokens'] for t in ts]):.0f} |")
out += ['', '## Phase C: memory (sampled every 5 s over the whole configuration)', '',
        '| config | peak resident (MiB) | vs ceiling 49,152 MiB | min free % | max pressure level | swapouts |', '|---|---|---|---|---|---|']
for L in labels:
    f = os.path.join(d, f'{L}-memory.csv')
    if not os.path.exists(f): continue
    m = list(csv.DictReader(open(f)))
    pk = max(int(x['rss_mib']) for x in m)
    out.append(f"| {L} | {pk:,} | {pk / 49152:.0%} | {min(int(x['free_pct']) for x in m)} | {max(int(x['level']) for x in m)} | {int(m[-1]['swapouts']) - int(m[0]['swapouts'])} |")
open(os.path.join(d, 'summary.md'), 'w').write('\n'.join(out) + '\n'); print('\n'.join(out))
