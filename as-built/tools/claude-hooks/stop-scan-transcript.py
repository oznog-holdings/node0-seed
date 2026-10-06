#!/usr/bin/env python3
"""stop-scan-transcript.py: the builder's Stop hook (20261003): after each turn, the transcript's new lines through
gitleaks with the site's rules (site/laptop/inference/encoders/gitleaks.toml: its defaults plus ours). Detection,
behind the prevention (pretooluse-redact.py): whatever got into the transcript anyway is found within a turn.
- The transcript is JSON lines whose strings are escaped; each new line's strings are decoded and scanned as text,
  and a finding is mapped back to its transcript line.
- A hit: one line appended to /work/agent/STATUS.md and one message to the owner's hosted ntfy topic, each naming the
  transcript, the line and the rule, never the value (gitleaks --redact; only RuleID and the line are used).
- State: ~/.local/state/secret-scan/<session>.json (byte offset, line count). A new session starts at its beginning.
- Never blocks the session: any failure is written to ~/.local/state/secret-scan/errors.log and to STATUS, and the
  hook exits 0 (the prevention, not this, is the gate). Unscanned lines are scanned at the next turn."""
import json, os, subprocess, sys, tempfile, time, urllib.request

GITLEAKS = os.path.expanduser('~/.local/share/seed/gitleaks/bin/gitleaks')
RULES = '/work/agent/seed-lab/site/laptop/inference/encoders/gitleaks.toml'
STATE = os.environ.get('SCAN_STATE', os.path.expanduser('~/.local/state/secret-scan')); STATUS = os.environ.get('SCAN_STATUS', '/work/agent/STATUS.md')
URLF = os.path.expanduser('~/.config/seed/hosted-ntfy-url')
now = lambda: time.strftime('%FT%TZ', time.gmtime())

def strings(v, out):
    if isinstance(v, str): out.append(v)
    elif isinstance(v, dict): [strings(x, out) for x in v.values()]
    elif isinstance(v, list): [strings(x, out) for x in v]

def notify(title, msg):
    if os.environ.get('SCAN_NOTIFY_TO'):   # tests: the message to a file instead of the owner's phone
        open(os.environ['SCAN_NOTIFY_TO'], 'a').write(f'{title}: {msg}\n'); return
    url = open(URLF).read().strip()   # the URL itself is the topic's secret: read here, never an argument
    urllib.request.urlopen(urllib.request.Request(url, msg.encode(), {'Title': title, 'Priority': 'high', 'Tags': 'warning,builder'}), timeout=15)

def status(line):
    with open(STATUS, 'a') as f: f.write(line + '\n')

def main():
    ev = json.load(sys.stdin); tp = ev.get('transcript_path'); sid = ev.get('session_id') or 'unknown'
    if not tp or not os.path.isfile(tp): return
    os.makedirs(STATE, mode=0o700, exist_ok=True); sf = f'{STATE}/{sid}.json'
    st = json.load(open(sf)) if os.path.exists(sf) else {'offset': 0, 'lines': 0}
    with open(tp, 'rb') as f:
        f.seek(st['offset']); data = f.read()
    end = data.rfind(b'\n') + 1
    if end <= 0: return
    chunk = data[:end].split(b'\n')[:-1]
    text, where = [], []   # decoded text lines, and the transcript line each came from
    for i, raw in enumerate(chunk):
        try: obj = json.loads(raw)
        except ValueError: obj = raw.decode('utf-8', 'replace')
        ss = []; strings(obj, ss)
        for s in ss:
            for l in s.split('\n'): text.append(l); where.append(st['lines'] + i + 1)
    hits = []
    if text:
        with tempfile.TemporaryDirectory() as d:
            rep = f'{d}/r.json'
            p = subprocess.run([GITLEAKS, 'stdin', '--config', RULES, '--redact', '--no-banner', '--log-level', 'error', '--exit-code', '0',
                                '--report-format', 'json', '--report-path', rep], input='\n'.join(text).encode(), capture_output=True, timeout=120)
            if p.returncode != 0: raise RuntimeError(f'gitleaks exited {p.returncode}')
            for x in (json.load(open(rep)) if os.path.getsize(rep) else []):
                n = x.get('StartLine') or 0
                hits.append((where[n - 1] if 0 < n <= len(where) else '?', x.get('RuleID', '?')))
    for line, rule in sorted(set(hits), key=str):
        msg = f'{os.path.basename(tp)} line {line}, rule {rule} (value not shown)'
        status(f'- **SECRET SCAN HIT {now()}:** {msg}. Check the line, rotate if real.')
        try: notify('builder: a secret-shaped string in the transcript', msg)
        except Exception as e: status(f'- secret scan: the ntfy alert failed ({type(e).__name__})')
    json.dump({'offset': st['offset'] + end, 'lines': st['lines'] + len(chunk), 'last': now()}, open(sf + '.tmp', 'w')); os.replace(sf + '.tmp', sf)

if __name__ == '__main__':
    try: main()
    except Exception as e:
        try:
            os.makedirs(STATE, mode=0o700, exist_ok=True)
            with open(f'{STATE}/errors.log', 'a') as f: f.write(f'{now()} {type(e).__name__}: {str(e)[:200]}\n')
            status(f'- secret scan FAILED {now()} ({type(e).__name__}): the transcript was not scanned this turn; see ~/.local/state/secret-scan/errors.log')
        except Exception: pass
    sys.exit(0)
