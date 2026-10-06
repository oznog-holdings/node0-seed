#!/usr/bin/env python3
"""tender-test-archive-task.py <block> <run> <from ISO> <until ISO> <record file> <PR numbers...>: the archive of a single
real-task run (the Tender test's stage 4), in the same shape as a block's runs (runbook 5.5), from the builder's account.
Writes /work/agent/tender-test-private/<block>/<run>/: run.json (pins, times, model calls, output tokens, scan),
transcript.jsonl, log.txt and followups.txt (lines placed by their own timestamps), notify.txt (every site-notify call),
commits.txt (the agent's commits in the window, on any branch), prs.json (the forge's record of the PRs), record.txt (the
owner-side actions and the delivery, the run's answer key)."""
import importlib.util, json, os, subprocess, sys
s = importlib.util.spec_from_file_location('a', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'tender-test-archive.py'))
a = importlib.util.module_from_spec(s); s.loader.exec_module(a)
P = a.P; T = a.T; CORE = a.CORE

def main(block, rid, frm, until, record, *prs):
    t0, end = a.ts(frm), a.ts(until); d = f'{P}/{block}/{rid}'; os.makedirs(d, exist_ok=True); co = '/work/tender/claude/seed-lab'
    tx = []
    for f in a.sh(T + ['ls ~/.claude/projects/*/*.jsonl']).split():
        for l in a.sh(T + [f'cat {f}']).splitlines():
            try: e = json.loads(l)
            except ValueError: continue
            if e.get('timestamp') and t0 <= a.ts(e['timestamp']) <= end: tx.append((a.ts(e['timestamp']), l, e))
    tx.sort(key=lambda x: x[0]); open(f'{d}/transcript.jsonl', 'w').write(''.join(l + '\n' for _, l, _ in tx))
    calls = [e for _, _, e in tx if isinstance(e.get('message'), dict) and e['message'].get('role') == 'assistant' and e['message'].get('usage')]
    tools = [(t, x) for t, _, e in tx for x in (e.get('message', {}).get('content') or []) if isinstance(e.get('message'), dict) and isinstance(x, dict) and x.get('type') == 'tool_use']
    notify = [f"{a.iso(t)} {x['input'].get('command', '')}" for t, x in tools if 'site-notify' in json.dumps(x.get('input'))]
    open(f'{d}/notify.txt', 'w').write('\n'.join(notify) + '\n')
    for name, path in (('log', 'site/agents/log/claude.md'), ('followups', 'site/agents/followups/claude.md')):
        text = a.sh(T + [f'cat {co}/{path}'])
        open(f'{d}/{name}.txt', 'w').write(''.join(l + '\n' for l in text.splitlines() if (x := a.line_time(l)) and t0 <= x <= end))
    open(f'{d}/commits.txt', 'w').write(a.sh(T + [f"git -C {co} fetch -q origin; git -C {co} log --all --since=@{t0} --until=@{end} --format='%h %cI %an: %s'"]))
    pr = []
    for n in prs:
        r = subprocess.run(['bash', '-c', f". /tmp/forge.sh; forge GET /repos/seed/seed-lab/pulls/{n}"], capture_output=True, text=True)
        try: j = json.loads(r.stdout); pr.append({k: j.get(k) for k in ('number', 'title', 'body', 'state', 'merged', 'merged_at', 'created_at')} | {'head': j.get('head', {}).get('ref'), 'base': j.get('base', {}).get('ref'), 'user': (j.get('user') or {}).get('login'), 'merged_by': (j.get('merged_by') or {}).get('login')})
        except ValueError: pr.append({'number': n, 'error': 'not read'})
    json.dump(pr, open(f'{d}/prs.json', 'w'), indent=1)
    open(f'{d}/record.txt', 'w').write(open(record).read())
    rep = f'{d}/.scan.json'
    subprocess.run([a.G, 'dir', d, '--config', a.RULES, '--redact', '--no-banner', '--log-level', 'error', '--exit-code', '0', '--report-format', 'json', '--report-path', rep], capture_output=True)
    found = json.load(open(rep)) if os.path.getsize(rep) else []; os.remove(rep)
    run = {'run': rid, 'block': block, 'task': 'the nixpkgs upgrade 1bc55b9 -> 7fc6f2c (the owner, via the orchestrator)', 'delivered': a.iso(t0), 'archive_until': a.iso(end),
           'pins': {'claude_code': a.sh(T + ['readlink ~/.local/share/seed/claude/claude']).strip().rsplit('/', 1)[-1], 'model_setting': a.sh(T + ["jq -r .model ~/.claude/settings.json"]).strip()},
           'model_calls': len(calls), 'output_tokens': sum((e['message']['usage'].get('output_tokens') or 0) for e in calls), 'tool_calls': len(tools),
           'transcript_lines': len(tx), 'site_notify_calls': len(notify), 'prs': [p.get('number') for p in pr],
           'scan': [f"{os.path.basename(x['File'])}:{x['StartLine']} {x['RuleID']}" for x in found] or 'clean'}
    json.dump(run, open(f'{d}/run.json', 'w'), indent=1)
    print(f"{rid}: {len(tx)} lines, {len(calls)} calls, {run['output_tokens']} out tokens, {len(tools)} tool calls, notify {len(notify)}, PRs {run['prs']}, scan {run['scan'] if found else 'clean'}")

if __name__ == '__main__': main(*sys.argv[1:])
