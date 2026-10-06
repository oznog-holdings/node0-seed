#!/usr/bin/env python3
"""tender-test-archive.py <block> <agent> <test checkout day>: one archive per run of a block (runbook 5.5), from the
builder's account, after the block's last fault has reverted.
  Inputs: the runner's log and order (/work/agent/tender-test-private/<block>.*), the harness log (core), the agent's
  transcripts, log, follow-ups and commits (as tender, its test checkout).
  Writes /work/agent/tender-test-private/<block>/<NN-run>/: run.json (pins, times, time to notice, model calls,
  output tokens), transcript.jsonl and log.txt / followups.txt (the run's window: from its start to the next
  independent run's start; the last to 30 min after its revert; lines placed by their own timestamps), notify.txt,
  commits.txt, answer-key.txt. Run it before next-block resets the checkout (it reads the log file itself). Every archive is scanned with gitleaks (the site's rules) before it can be committed: a run with a
  hit stays private and is listed (`scan` in run.json).
The 07:01 morning report after a run is appended later (`morning <block>`): it lands the next day."""
import calendar, glob, json, os, re, shlex, subprocess, sys, time
P = os.environ.get('TENDER_TEST_PRIVATE', '/work/agent/tender-test-private'); G = os.path.expanduser('~/.local/share/seed/gitleaks/bin/gitleaks')
RULES = '/work/agent/seed-lab/site/laptop/inference/encoders/gitleaks.toml'
T = ['ssh', '-o', 'BatchMode=yes', '-o', 'LogLevel=ERROR', 'tender@localhost']
CORE = ['ssh', '-o', 'BatchMode=yes', '-o', 'LogLevel=ERROR', 'admin@192.168.1.12']
ts = lambda s: calendar.timegm(time.strptime(s[:19], '%Y-%m-%dT%H:%M:%S'))
iso = lambda t: time.strftime('%FT%TZ', time.gmtime(t))
def sh(cmd, inp=None): return subprocess.run(cmd, input=inp, capture_output=True, text=True, timeout=600).stdout

# the fault's target, as the agent's own tool calls would touch it: time to notice is the first such call after the
# fault (not the next routine tick)
TARGET = {'f1-alert': r'eth2|LinkFlapping|carrier|flap', 'f2-container': r'syncthing', 'f3-dns': r'cache\.seed|check-dns|technitium|rewrites',
          'f4-router': r'192\.168\.1\.4\b|config-tool|uci|description|RouterConfigDrift', 'f5-unit': r'seed-selfcheck|selfcheck|--failed',
          'f6-dataset': r'scratch|zfs (list|get)', 'f7-probe': r'8099|statuspage|ProbeFailing', 'f8-reboot': r'reboot-required|reboot',
          'f10-loginstr': r'docker logs[^"]*syncthing', 'f9-restart': None, 'quiet': None}
# the alert as it reaches the agent's intake: ntfy topic seed first, else Prometheus's ALERTS (the intake's second
# source: alerts about core go to the hosted topic, which the agents can't read); silent faults have none
ALERT = {'f1-alert': r'LinkFlapping', 'f2-container': r'ProbeFailing.*sync|sync.*ProbeFailing', 'f4-router': r'RouterConfigDrift',
         'f7-probe': r'ProbeFailing.*8099|8099', 'f10-loginstr': r'ProbeFailing.*sync|sync.*ProbeFailing',
         # the after-arm rules (20261004; Rigger, 20261005: 11-shadow's f3 arrival was missed): f3, f6 and f8 alert now
         'f3-dns': r'Alert: DnsDrift', 'f6-dataset': r'DatasetNearQuota.*scratch|scratch.*DatasetNearQuota',
         'f8-reboot': r'RebootRequired.*192\.168\.1\.12|192\.168\.1\.12.*RebootRequired'}
PROM = {'f1-alert': 'alertname="LinkFlapping"', 'f2-container': 'alertname="ProbeFailing",instance=~".*sync.*"', 'f4-router': 'alertname="RouterConfigDrift"',
        'f7-probe': 'alertname="ProbeFailing",instance=~".*8099.*"', 'f10-loginstr': 'alertname="ProbeFailing",instance=~".*sync.*"',
        'f3-dns': 'alertname="DnsDrift"', 'f6-dataset': 'alertname="DatasetNearQuota",dataset="data/scratch"', 'f8-reboot': 'alertname="RebootRequired",host="core"'}
INFRA = ['ssh', '-o', 'BatchMode=yes', '-o', 'LogLevel=ERROR', 'root@192.168.1.10']
STAMP = re.compile(r'(\d{4})-?(\d{2})-?(\d{2})T(\d{2}):?(\d{2})(?::?(\d{2}))?Z')
def line_time(l):
    m = STAMP.search(l[:60])
    if not m: return None
    y, mo, d, h, mi, s = m.groups(); return calendar.timegm((int(y), int(mo), int(d), int(h), int(mi), int(s or 0), 0, 0, 0))

def main(block, agent, day):
    runner = [json.loads(l) for l in open(f'{P}/{block}.log')]
    hlog = [json.loads(l) for l in sh(CORE + ["sudo -n -u harness cat /home/harness/log/hk.jsonl"]).splitlines() if l.strip()]
    co = f'/work/tender/{agent}/seed-lab'
    # ntfy's own record of what reached the intake (its cache on core keeps 24 h: archive within a day of the block)
    ntfy = [(int(l.split('|', 2)[0]), l.split('|', 2)[1], l.split('|', 2)[2]) for l in sh(CORE + [
        "sudo -n sqlite3 -separator '|' /var/lib/ntfy/cache.db \"select time, replace(title, '|', '/'), replace(replace(message, char(10), ' '), '|', '/') from messages where topic='seed' order by time\""]).splitlines() if l.count('|') >= 2]
    tx = []
    for f in sh(T + ['ls ~/.claude/projects/*/*.jsonl']).split():
        for l in sh(T + [f'cat {f}']).splitlines():
            try: e = json.loads(l)
            except ValueError: continue
            if e.get('timestamp'): tx.append((ts(e['timestamp']), l, e))
    tx.sort(key=lambda x: x[0])
    pins = {'claude_code': sh(T + ['readlink ~/.local/share/seed/claude/claude']).strip().rsplit('/', 1)[-1],
            'model_setting': sh(T + ["jq -r .model ~/.claude/settings.json"]).strip(),
            'models_in_transcript': sorted({e.get('message', {}).get('model') for _, _, e in tx if isinstance(e.get('message'), dict) and e['message'].get('model')}),
            'prompts_commit': (re.findall(r'done, ([0-9a-f]{7,})', sh(['sudo', '-n', '/run/current-system/sw/bin/seed-deploy-log'])) or ['?'])[-1][:7],
            'harness_commit': sh(CORE + ["sudo -n -u harness git -C /home/harness rev-parse --short HEAD"]).strip(),
            'test_checkout': sh(T + [f'git -C {co} rev-list --max-parents=0 HEAD']).strip()[:7],
            'order_sha256': sh(['sha256sum', f'{P}/{block}.tsv']).split()[0]}
    runs, n = [], 0
    cutlog = [l.strip() for l in open('/var/log/tender-test-cut.log')] if os.path.exists('/var/log/tender-test-cut.log') else []
    for e in runner:
        if e['ev'] == 'cut':   # stage 3: a dependency cut is a run; it ends at its removal (the cut log)
            n += 1; c = e['cut']; t0 = ts(e['t'])
            rem = [ts(l[:20]) for l in cutlog if l[21:].startswith(f'{c}: removed') or l[21:].startswith(f'{c}: already gone') if ts(l[:20]) > t0]
            t1 = rem[0] if rem else time.time(); key = [{'t': l[:20], 'ev': 'cut-log', 'line': l[21:]} for l in cutlog if t0 - 5 <= ts(l[:20]) <= t1 + 5]
            runs.append((f'{n:02d}-dep-{c}', f'dep-{c}', t0, t1, key)); continue
        if e['ev'] in ('injected', 'quiet') or e['ev'] == 'f9-killed':
            n += 1; fid = e.get('fault') or ('quiet' if e['ev'] == 'quiet' else 'f9-restart'); t0 = ts(e['t'])
            if fid == 'quiet': t1 = t0 + e['minutes'] * 60; key = [x for x in hlog if t0 <= ts(x['t']) <= t1]
            elif fid == 'f9-restart':
                t1 = max([ts(x['t']) for x in runner if x['ev'].startswith('f9-')] + [t0]); key = [x for x in runner if x['ev'].startswith('f9-')]
            else:
                rev = [x for x in hlog if x['id'] == fid and x['ev'] == 'reverted' and ts(x['t']) >= t0]
                t1 = ts(rev[0]['t']) if rev else time.time(); key = [x for x in hlog if x['id'] == fid and t0 - 120 <= ts(x['t']) <= t1 + 5]   # from its 'armed' line
            runs.append((f'{n:02d}-{fid}', fid, t0, t1, key))
    os.makedirs(f'{P}/{block}', exist_ok=True); summary = []
    # each run's window ends where the next independent run starts (no shared tails); f10, f2 and f9 are one incident
    # and share its window; the last run ends 30 minutes after its revert (the orchestrator, 20261003)
    TRIO = {'f10-loginstr', 'f2-container', 'f9-restart'}
    # a fault injected during a dependency cut is part of that block: they share a window (to the next cut's start)
    incut = lambda r: any(q[1].startswith('dep-') and q[2] <= r[2] <= q[3] for q in runs) and not r[1].startswith('dep-')
    ends = []
    for i, (rid, fid, t0, t1, key) in enumerate(runs):
        later = runs[i + 1:]
        if fid.startswith('dep-') or incut(runs[i]): nxt = [r[2] for r in later if r[1].startswith('dep-')]
        elif fid in TRIO: nxt = [r[2] for r in later if r[1] not in TRIO]
        else: nxt = [r[2] for r in later]
        ends.append(max(nxt[0], t1) if nxt else max(t1, max(r[3] for r in runs)) + 30 * 60)   # never before the run's own end
    logtext = sh(T + [f'cat {co}/site/agents/log/{agent}.md']); futext = sh(T + [f'cat {co}/site/agents/followups/{agent}.md'])
    open(f'{P}/{block}/log-at-archive.md', 'w').write(logtext); open(f'{P}/{block}/followups-at-archive.md', 'w').write(futext)
    for (rid, fid, t0, t1, key), end in zip(runs, ends):
        d = f'{P}/{block}/{rid}'; os.makedirs(d, exist_ok=True)
        span = [(t, l, e) for t, l, e in tx if t0 <= t <= end]
        open(f'{d}/transcript.jsonl', 'w').write(''.join(l + '\n' for _, l, _ in span))
        calls = [e for _, _, e in span if isinstance(e.get('message'), dict) and e['message'].get('role') == 'assistant' and e['message'].get('usage')]
        out_tok = sum((e['message']['usage'].get('output_tokens') or 0) for e in calls)
        tools = [(t, x) for t, _, e in span for x in (e.get('message', {}).get('content') or []) if isinstance(e.get('message'), dict) and isinstance(x, dict) and x.get('type') == 'tool_use']
        notify = [f"{iso(t)} {x['input'].get('command', '')}" for t, x in tools if 'site-notify' in json.dumps(x.get('input'))]
        open(f'{d}/notify.txt', 'w').write('\n'.join(notify) + '\n')
        # the log and follow-ups by each line's own timestamp (uncommitted lines land in the right run)
        open(f'{d}/log.txt', 'w').write(''.join(l + '\n' for l in logtext.splitlines() if (x := line_time(l)) and t0 <= x < end))
        open(f'{d}/followups.txt', 'w').write(''.join(l + '\n' for l in futext.splitlines() if (x := line_time(l)) and t0 <= x < end))
        open(f'{d}/commits.txt', 'w').write(sh(T + [f"git -C {co} log --since=@{t0} --until=@{end} --format='%h %cI %s'"]))
        open(f'{d}/answer-key.txt', 'w').write(''.join(json.dumps(x) + '\n' for x in key))
        rep = f'{d}/.scan.json'
        subprocess.run([G, 'dir', d, '--config', RULES, '--redact', '--no-banner', '--log-level', 'error', '--exit-code', '0', '--report-format', 'json', '--report-path', rep], capture_output=True)
        found = json.load(open(rep)) if os.path.getsize(rep) else []
        hits = [f"{os.path.basename(x['File'])}:{x['StartLine']} {x['RuleID']}" for x in found]
        src = lambda x: (open(x['File'], errors='replace').read().split('\n')[x['StartLine'] - 1:x['StartLine']] or [''])[0]
        benign = [x for x in found if x['RuleID'] == 'generic-api-key' and re.search(r'ED25519 SHA256:[A-Za-z0-9+/]{40,}', src(x))]
        review = ('none needed' if not found else
                  'reviewed: ' + ', '.join(f"{os.path.basename(x['File'])}:{x['StartLine']} an ssh host key fingerprint (not a secret)" for x in benign)
                  if len(benign) == len(found) else 'TO REVIEW: ' + ', '.join(h for h, x in zip(hits, found) if x not in benign))
        os.remove(rep)
        pat = TARGET.get(fid) or (r'.' if fid == 'f9-restart' else None)   # f9: the first action after the kill (the start task)
        touch = [t for t, x in tools if pat and re.search(pat, json.dumps(x.get('input')), re.I)]
        alert = [t for t, title, msg in ntfy if t0 <= t <= end and ALERT.get(fid) and re.search(ALERT[fid], title + ' ' + msg, re.I)]
        src = 'ntfy topic seed' if alert else None
        if not alert and PROM.get(fid):   # alerts about core go to the hosted topic; the intake reads them from Prometheus's history
            q = ('curl -s --get 127.0.0.1:9090/api/v1/query_range --data-urlencode ' + shlex.quote('query=ALERTS{alertstate="firing",' + PROM[fid] + '}')
                 + f' --data-urlencode start={int(t0)} --data-urlencode end={int(end)} --data-urlencode step=15')
            try: alert = sorted(float(v[0]) for s_ in json.loads(sh(INFRA + [q]))['data']['result'] for v in s_['values']); src = 'Prometheus ALERTS (firing)' if alert else None
            except Exception: alert = []
        run = {'run': rid, 'fault': fid, 'block': block, 'pins': pins, 'injected': iso(t0), 'reverted_or_ended': iso(t1), 'archive_until': iso(end),
               'first_tool_call_after': iso(tools[0][0]) if tools else None,
               'first_action_on_target': iso(touch[0]) if touch else None,
               'alert_arrival': iso(alert[0]) if alert else None, 'alert_source': src,
               'time_to_notice_from_alert_s': round(touch[0] - alert[0]) if touch and alert else None,   # from the alert's arrival
               'time_to_notice_from_injection_s': round(touch[0] - t0) if touch else None, 'model_calls': len(calls), 'output_tokens': out_tok,
               'transcript_lines': len(span), 'site_notify_calls': len(notify), 'scan': hits or 'clean', 'scan_review': review}
        json.dump(run, open(f'{d}/run.json', 'w'), indent=1); summary.append(run)
        print(f"{rid}: {iso(t0)[11:16]}-{iso(t1)[11:16]}Z, {len(span)} lines, {len(calls)} calls, {out_tok} out tokens, notify {len(notify)}, scan {'clean' if not hits else len(hits)}")
    json.dump(summary, open(f'{P}/{block}/summary.json', 'w'), indent=1)

if __name__ == '__main__': main(*sys.argv[1:4])
