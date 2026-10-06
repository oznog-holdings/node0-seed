#!/usr/bin/env python3
"""Per-call timings of the inference server, from its own log (server.log), one TSV row per finished request.
Run on compute (as seed) by the agent box's keel-qwen-calls timer: `python3 - <offset> < qwen-calls.py`.
Reads server.log from byte <offset>, prints rows, and a last line `#offset <n>` (the next start).
The log's times are each model process's uptime (MM.SS.mmm.uuu), so wall time comes from that process's start
(ps, by its --port). A request from a process no longer running gets an empty time.
Columns: utc  model  port  task  slot  prompt_new  prompt_s  cached  gen  gen_s  ctx_end
  prompt_new = prompt tokens read this call (the cache missed them); cached = ctx_end - prompt_new - gen (the
  prompt tokens the slot already held); ctx_end = the slot's tokens when the request finished."""
import os, re, subprocess, sys, time
LOG = os.path.expanduser('~/.local/state/seed/inference/server.log')
off = int(sys.argv[1]) if len(sys.argv) > 1 else 0
size = os.path.getsize(LOG)
if off > size: off = 0          # the log was rotated or truncated
starts, models = {}, {}
for line in subprocess.run(['ps', '-axo', 'pid=,lstart=,command='], capture_output=True, text=True).stdout.splitlines():
    m = re.search(r'--port (\d+)', line)
    if 'llama-server' in line and m and '--alias' in line:
        port = m.group(1); models[port] = re.search(r'--alias (\S+)', line).group(1)
        lstart = ' '.join(line.split()[1:6])
        starts[port] = time.mktime(time.strptime(lstart, '%a %b %d %H:%M:%S %Y'))
with open(LOG, 'rb') as f:
    f.seek(off); data = f.read()
# only whole lines: a partial last line is read next time
cut = max(data.rfind(b'\n'), data.rfind(b'\r')) + 1
# lines with their byte offsets, so the next run can start at a request that hasn't finished yet (Codex's review)
lines, pos = [], 0
for raw in re.split(rb'(?<=[\r\n])', data[:cut]):
    if raw: lines.append((off + pos, raw.decode('utf-8', 'replace').rstrip('\r\n'))); pos += len(raw)
T = r'\[(\d+)\] (\d+)\.(\d+)\.(\d+)\.\d+ I slot '
pend = {}
for at, l in lines:
    m = re.match(T + r'print_timing: id +(\d+) \| task (\d+) \| prompt eval time = +([\d.]+) ms / +(\d+) tokens', l)
    if m:
        p, _, _, _, slot, task, ms, n = m.groups(); pend[(p, task)] = {'slot': slot, 'pms': float(ms), 'pn': int(n), 'at': at}; continue
    m = re.match(T + r'print_timing: id +\d+ \| task (\d+) \| +eval time = +([\d.]+) ms / +(\d+) tokens', l)
    if m:
        p, _, _, _, task, ms, n = m.groups(); pend.setdefault((p, task), {}).update(gms=float(ms), gn=int(n)); continue
    m = re.match(T + r'+release: id +\d+ \| task (\d+) \| stop processing: n_tokens = (\d+)', l)
    if m:
        p, mm, ss, ms_, task, ctx = m.groups(); r = pend.pop((p, task), None)
        if not r or 'pn' not in r: continue
        up = int(mm) * 60 + int(ss) + int(ms_) / 1000
        utc = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(starts[p] + up)) if p in starts else ''
        gn = r.get('gn', 0); ctx = int(ctx)
        print('\t'.join(map(str, [utc, models.get(p, ''), p, task, r['slot'], r['pn'], round(r['pms'] / 1000, 1),
                                  max(0, ctx - r['pn'] - gn), gn, round(r.get('gms', 0) / 1000, 1), ctx])))
# a request still open (timings seen, no release yet) is read again next time, from its first line; one whose process
# has gone never finishes, so only requests from running processes hold the offset back
open_at = [r['at'] for (p, _), r in pend.items() if 'at' in r and p in starts]
print(f'#offset {min(open_at) if open_at else off + cut}')
