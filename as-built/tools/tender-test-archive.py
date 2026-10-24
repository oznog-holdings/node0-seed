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
RULES = '/work/agent/seed-lab/tools/tender-test-gitleaks.toml'   # the site's rules + one exemption for the archive (round 2, item 17)
T = ['ssh', '-o', 'BatchMode=yes', '-o', 'LogLevel=ERROR', 'tender@localhost']
CORE = ['ssh', '-o', 'BatchMode=yes', '-o', 'LogLevel=ERROR', 'admin@192.168.1.12']
ts = lambda s: calendar.timegm(time.strptime(s[:19], '%Y-%m-%dT%H:%M:%S'))
iso = lambda t: time.strftime('%FT%TZ', time.gmtime(t))
def sh(cmd, inp=None): return subprocess.run(cmd, input=inp, capture_output=True, text=True, timeout=600).stdout

# the re-test's fixes (20261008)
def cmd_of(x):   # a tool call's shell command (Claude's Bash: input.command; Hermes's terminal: the same, or raw)
    i = x.get('input') or {}
    return i.get('command') or i.get('raw') or '' if isinstance(i, dict) else str(i)
def runs_notify(c):   # fix 2: site-notify run as a command (a segment's first word), not a grep, printf or doc naming it
    # quotes are kept on the tokens (posix=False), so a quoted ";" stays a word and doesn't split the command
    try: toks = list(shlex.shlex(c.replace('$(', ' ; ').replace('`', ' ; ').replace('\n', ' ; '), posix=False, punctuation_chars=';&|()'))
    except ValueError: toks = c.split()   # unbalanced quotes: a plain split
    segs, cur = [], []
    for t in toks:
        if t and set(t) <= set(';&|()'): segs.append(cur); cur = []
        else: cur.append(t)
    segs.append(cur)
    skip = ('sudo', 'env', 'exec', 'command', 'time', '{', '}', '!', 'if', 'then', 'else', 'elif', 'while', 'until', 'do')
    for seg in segs:
        w = [t for t in seg if not re.match(r'^[A-Z_][A-Z0-9_]*=', t) and t not in skip]
        while w and w[0].startswith('-'): w = w[1:]   # a wrapper's options (sudo -n …)
        if w and re.search(r'(^|/)site-notify$', w[0].strip('"\'')): return True   # any call; sent or not is its result's to say
    return False
def notify_calls(c):   # each site-notify call in a shell command, as its argument list (quotes stripped)
    try: toks = list(shlex.shlex(c.replace('$(', ' ; ').replace('`', ' ; ').replace('\n', ' ; '), posix=False, punctuation_chars=';&|()'))
    except ValueError: toks = c.split()
    segs, cur = [], []
    for t in toks:
        if t and set(t) <= set(';&|()'): segs.append(cur); cur = []
        else: cur.append(t)
    segs.append(cur); out = []
    skip = ('sudo', 'env', 'exec', 'command', 'time', '{', '}', '!', 'if', 'then', 'else', 'elif', 'while', 'until', 'do')
    for seg in segs:
        w = [t.strip('"\'') for t in seg if not re.match(r'^[A-Z_][A-Z0-9_]*=', t) and t not in skip]
        while w and w[0].startswith('-'): w = w[1:]
        if w and re.search(r'(^|/)site-notify$', w[0]): out.append(w[1:])
    return out
def only_help(c):   # item 8: every site-notify call in the command is exactly "--help" or "-h"; none could send
    calls = notify_calls(c)
    seen = len(re.findall(r'(?<![\w-])site-notify(?![\w-])', c))   # conservative: a call the parser missed (sudo -u x …) keeps it listed
    return bool(calls) and len(calls) == seen and all(a in (['--help'], ['-h']) for a in calls)
def tools_e(span):   # (time, tool_use, its entry), in order
    return [(t, x, e) for t, _, e in span for x in (e.get('message', {}).get('content') or []) if isinstance(e.get('message'), dict) and isinstance(x, dict) and x.get('type') == 'tool_use']
def result_of(span):   # a tool call's result text: Claude's tool_result by id; Hermes's next tool row in its session
    by_id, rows, pos = {}, [], {}
    for n_, (t, raw, e) in enumerate(span):
        pos[id(e)] = n_
        m = e.get('message') or {}
        for y in (m.get('content') if isinstance(m.get('content'), list) else []):
            if isinstance(y, dict) and y.get('type') == 'tool_result':
                c = y.get('content'); by_id[y.get('tool_use_id')] = c if isinstance(c, str) else json.dumps(c)
        if e.get('hermes') and m.get('role') == 'tool':
            try: sid = json.loads(raw).get('session_id')
            except ValueError: sid = None
            rows.append((n_, sid, json.dumps(m.get('content'))))
    def res(x, e, t):
        if x.get('id') in by_id: return by_id[x['id']]
        if e.get('hermes'):   # one turn may call several tools: the k-th call's result is the k-th tool row after it
            uses = [y for y in e['message']['content'] if isinstance(y, dict) and y.get('type') == 'tool_use']
            sid = e.get('session_id'); k = next(i for i, y in enumerate(uses) if y is x)   # by position, not equality
            after = [c for n_, s_, c in rows if n_ > pos.get(id(e), -1) and s_ == sid]   # by the transcript's order, not time
            return after[k] if k < len(after) else ''
        return ''
    return res
SENT = re.compile(r'sent to the owner \(seed-agents, (default|high|urgent)\)')   # site-notify's success line
HOME_ = r'(~|\$HOME|\$\{HOME\}|"\$HOME"|/home/tender)'
OTHER = {o: rf'/work/tender/{o}\b|{HOME_}/\.{o}\b|site/agents/(log|followups)/{o}\.md|site-review/{o}\.log|site-intake/{o}\b|site-heartbeat/{o}\b'
         for o in ('hermes', 'claude')}
OTHER = {'claude': OTHER['hermes'], 'hermes': OTHER['claude']}   # each agent's reads of the other's

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
STAMP = re.compile(r'(\d{4})-?(\d{2})-?(\d{2})[T ](\d{2}):?(\d{2})(?::?(\d{2}))?Z')   # T or a space ("20261006 06:01Z", from block 21: Codex/Rigger 20261007)
def line_time(l):
    m = STAMP.search(l[:60])
    if not m: return None
    y, mo, d, h, mi, s = m.groups(); return calendar.timegm((int(y), int(mo), int(d), int(h), int(mi), int(s or 0), 0, 0, 0))

def hermes_tx():
    """Hermes's messages (~tender/.hermes/state.db, read-only), as (time, the raw row as a JSON line, a Claude-shaped
    entry): each tool call becomes a tool_use with its arguments as input, so the run's measures read the same"""
    py = ("import sqlite3, os, json\n"
          "c = sqlite3.connect('file:' + os.path.expanduser('~/.hermes/state.db') + '?mode=ro', uri=True)\n"
          "for r in c.execute('select session_id, role, content, tool_calls, tool_name, timestamp from messages order by timestamp'):\n"
          "    print(json.dumps(dict(zip(('session_id', 'role', 'content', 'tool_calls', 'tool_name', 'timestamp'), r))))\n")
    out = []
    r_ = subprocess.run(T + ['python3 -'], input=py, capture_output=True, text=True, timeout=600)
    if r_.returncode != 0 or not r_.stdout.strip(): raise SystemExit(f'Hermes\'s session store unread: {r_.stderr.strip()[-200:]}')
    for l in r_.stdout.splitlines():
        r = json.loads(l); uses = []
        for tc in json.loads(r['tool_calls'] or '[]'):
            f = tc.get('function') or {}
            try: args = json.loads(f.get('arguments') or '{}')
            except ValueError: args = {'raw': f.get('arguments')}
            uses.append({'type': 'tool_use', 'name': f.get('name'), 'input': args if isinstance(args, dict) else {'raw': args}})
        e = {'timestamp': iso(r['timestamp']), 'hermes': True, 'session_id': r['session_id'],
             'message': {'role': r['role'], 'content': uses + ([{'type': 'text', 'text': r['content']}] if r['content'] else [])}}
        out.append((r['timestamp'], l, e))
    return out

def hermes_calls():
    """Hermes's model calls from its agent.log ("API call #n: ... out=N"), as (time, output tokens); the log's local
    times converted on the agent box itself"""
    py = ("import re, time, glob, os\n"
          "fs = sorted(glob.glob(os.path.expanduser('~/.hermes/logs/agent.log*')))\n"
          "if not fs: raise SystemExit('no agent.log')\n"
          "for f in fs:\n"
          "    for l in open(f, errors='replace'):\n"
          "        m = re.match(r'(\\d{4}-\\d\\d-\\d\\d \\d\\d:\\d\\d:\\d\\d),\\d+ .*API call #\\d+: .* out=(\\d+)', l)\n"
          "        if m: print(time.mktime(time.strptime(m.group(1), '%Y-%m-%d %H:%M:%S')), m.group(2))\n")
    r_ = subprocess.run(T + ['python3 -'], input=py, capture_output=True, text=True, timeout=600)
    if r_.returncode != 0: raise SystemExit(f'Hermes\'s agent.log unread: {r_.stderr.strip()[-200:]}')
    return sorted((float(a), int(b)) for a, b in (l.split() for l in r_.stdout.splitlines()))

PLUGIN = 'claude-subscription-directsdk-experimental'   # the harness test (20261021): Hermes on Sonnet 5.5 through the claude CLI
USAGE_SQL = '/work/agent/seed-lab/tools/tender-test-usage.sql'   # written from the rehearsal (the plan's A5.6), reviewed before 61
def hermes_usage():
    """per Hermes session: (epoch of its first call, session, list-price equivalent or None, uncached, cache read,
    cache write, output, model native reported or None, model calls), by USAGE_SQL on state.db (read-only); None when the query isn't written yet"""
    if not os.path.exists(USAGE_SQL): return None
    py = ("import sqlite3, os, sys, json\n"
          "c = sqlite3.connect('file:' + os.path.expanduser('~/.hermes/state.db') + '?mode=ro', uri=True)\n"
          "for r in c.execute(sys.stdin.read()): print(json.dumps(list(r)))\n")
    r_ = subprocess.run(T + [f'python3 -c {shlex.quote(py)}'], input=open(USAGE_SQL).read(), capture_output=True, text=True, timeout=600)
    if r_.returncode != 0: raise SystemExit(f'Hermes\'s usage unread: {r_.stderr.strip()[-200:]}')
    return [json.loads(l) for l in r_.stdout.splitlines() if l.strip()]
def usage_of(rows, t0, end):   # a call whose usage native didn't report is unknown, never zero (the plan's A5.6)
    if rows is None: return 'not configured (no tools/tender-test-usage.sql)'
    w = [r for r in rows if t0 <= float(r[0]) < end]   # half-open: a call on a boundary counts once
    known = [r for r in w if r[2] is not None]
    # one row per Hermes session (usage is kept per session): counted whole in the window of its first call
    return {'sessions': len(w), 'calls': sum(int(r[8] or 0) for r in w if len(r) > 8), 'sessions_cost_unknown': len(w) - len(known),
            'list_usd_known': round(sum(float(r[2]) for r in known), 4),
            'tokens': {k: sum(int(r[i] or 0) for r in w) for k, i in (('uncached', 3), ('cache_read', 4), ('cache_write', 5), ('output', 6))},
            'models_reported': sorted({r[7] for r in w if len(r) > 7 and r[7]})}

def main(block, agent, day):
    runner = [json.loads(l) for l in open(f'{P}/{block}.log')]
    hlog = [json.loads(l) for l in sh(CORE + ["sudo -n -u harness /home/harness/bin/hk-run"], "log\n").splitlines() if l.strip()]
    co = f'/work/tender/{agent}/seed-lab'
    # ntfy's own record of what reached the intake (its cache on core keeps 24 h: archive within a day of the block)
    ntfy = [(int(l.split('|', 2)[0]), l.split('|', 2)[1], l.split('|', 2)[2]) for l in sh(CORE + [
        "sudo -n sqlite3 -separator '|' /var/lib/ntfy/cache.db \"select time, replace(title, '|', '/'), replace(replace(message, char(10), ' '), '|', '/') from messages where topic='seed' order by time\""]).splitlines() if l.count('|') >= 2]
    tx = []
    if agent == 'hermes':   # the GPU day (20261006): Hermes's session store, each message as one transcript line
        tx = hermes_tx()
    for f in (sh(T + ['ls ~/.claude/projects/*/*.jsonl']).split() if agent == 'claude' else []):
        for l in sh(T + [f'cat {f}']).splitlines():
            try: e = json.loads(l)
            except ValueError: continue
            if e.get('timestamp'): tx.append((ts(e['timestamp']), l, e))
    tx.sort(key=lambda x: x[0])
    provider = sh(T + ["sed -n 's/^  provider: *\"\\(.*\\)\"/\\1/p' ~/.hermes/config.yaml | head -1"]).strip() if agent == 'hermes' else ''
    pins = ({'hermes': sh(T + ['export PATH=$HOME/.local/bin:$PATH; hermes --version 2>&1 | head -1']).strip(),
             'provider': provider,
             'model_setting': sh(T + ["sed -n 's/^  default: *\"\\(.*\\)\"/\\1/p' ~/.hermes/config.yaml | head -1"]).strip(),
             'context_length': sh(T + ["sed -n 's/^  context_length: *\\([0-9]*\\).*/\\1/p' ~/.hermes/config.yaml | head -1"]).strip(),
             'reasoning_effort': sh(T + ["sed -n 's/^  reasoning_effort: *\"\\(.*\\)\"/\\1/p' ~/.hermes/config.yaml | head -1"]).strip(),
             # the GPU day's served model (the orchestrator, 20261006): thinking ON by the server's template unless a
             # request turns it off; Hermes's main turns don't (as on the Mac), its compression does (as on the Mac).
             # Only on gpu-chat (post-test item 23: run.json pinned the old server whatever the model)
             **({} if provider == PLUGIN else {'served': {'model': 'Qwen3.8-27B UD-Q4_K_XL', 'sha256': '3f227079003add2511437e5b1e94812e363385225bf6a9b47b0054a72bc8b01e',
                        'server': 'llama.cpp build 9190 (CUDA)', 'context': 131072, 'kv': 'q8_0', 'parallel': '2, kv-unified',
                        'alias': 'qwen3.8-27b-gpu', 'thinking': 'on (server default), Hermes reasoning_effort medium'}}),
             # the model client (the harness test): the plugin as installed (its manifest's sha256, as pinned in the plan's
             # A1), the claude CLI it runs, and the model three ways: requested (model_setting), native's route as the
             # builder saw it in a native child's argv at the block's first woken run, native-reported (usage, per run)
             **({'model_client': {'plugin_version': sh(T + ["sed -n 's/^version: *//p' ~/.hermes/plugins/claude-subscription-directsdk/plugin.yaml"]).strip(),
                                  # the vendor's files only (Python's caches and the pin file left out, as hermes-sonnet.sh does)
                                  'plugin_manifest_sha256': sh(T + ["cd ~/.hermes/plugins/claude-subscription-directsdk && find . -type f ! -name .seed-pin ! -name '*.pyc' ! -path '*/__pycache__/*' ! -path './.pytest_cache/*' -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -c1-64"]).strip(),
                                  'plugin_pin': sh(T + ['cat ~/.hermes/plugins/claude-subscription-directsdk/.seed-pin']).strip(),   # commit and manifest, written at install
                                  'claude_code': sh(T + ['readlink ~/.local/share/seed/claude/claude']).strip().rsplit('/', 1)[-1],
                                  'native_route_seen': open(f'{P}/{block}.native-route').read().strip() if os.path.exists(f'{P}/{block}.native-route') else 'not sampled'}}
                if provider == PLUGIN else {})}
            if agent == 'hermes' else
            {'claude_code': sh(T + ['readlink ~/.local/share/seed/claude/claude']).strip().rsplit('/', 1)[-1],
             'model_setting': sh(T + ["jq -r .model ~/.claude/settings.json"]).strip()}) | {
            'models_in_transcript': sorted({e.get('message', {}).get('model') for _, _, e in tx if isinstance(e.get('message'), dict) and e['message'].get('model')}),
            'prompts_commit': (re.findall(r'done, ([0-9a-f]{7,})', sh(['sudo', '-n', '/run/current-system/sw/bin/seed-deploy-log'])) or ['?'])[-1][:7],
            'harness_commit': sh(CORE + ["sudo -n -u harness /home/harness/bin/hk-run"], "head\n").strip(),
            'test_checkout': sh(T + [f'git -C {co} rev-list --max-parents=0 HEAD']).strip()[:7],
            'order_sha256': sh(['sha256sum', f'{P}/{block}.tsv']).split()[0],
            # the claude CLI's own state files (~/.claude/state: unattended-serving-consent.json, settings-review.json,
            # device-mcp-consent.json, device-mcp-snapshot.json, served-calls): absent in Claude's arm (root-60b,
            # 20261021) and in the model client's own HOME (mc/home) at the harness test's start: like for like
            'claude_cli_state_files_at_start': 'none in either arm (root-60b, 20261021)' if block[:1] == '6' else 'not recorded'}
    if agent == 'hermes' and provider != PLUGIN:   # round 2, item 19: the GPU node's own settings, from llama-server's /props through infra (the key by reference)
        q = ('K=$(sed -n "s/^GPU_TEST_API_KEY=//p" /mnt/data/system/secrets/litellm.env); curl -s -m 15 -H @<(printf "Authorization: Bearer %s\\n" "$K") '
             'http://100.64.0.20:8080/props | jq -c "{total_slots, n_ctx: .default_generation_settings.n_ctx, model_alias, build_info}"; unset K')
        try: pins['node'] = json.loads(sh(INFRA + [q]) or 'null')
        except ValueError: pins['node'] = 'unread'
        pins['node_note'] = "/props doesn't report the prompt cache; --no-cache-prompt since 20261010 15:50:12Z is Bosun's record (infra notes)"
    hcalls = hermes_calls() if agent == 'hermes' else []
    husage = hermes_usage() if agent == 'hermes' and provider == PLUGIN else None
    runs, n = [], 0
    cutlog = sorted(l.strip() for f in ('/var/log/tender-test-cut.log', f'{P}/gpu-model-cut.log') if os.path.exists(f) for l in open(f))   # 3m: the GPU day's model cut
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
    RES = result_of(tx)
    sweeplog = sh(T + ['cat ~/.local/state/site-sweep/runs.log 2>/dev/null'])   # fix 4: written by site-sweep itself
    logtext = sh(T + [f'cat {co}/site/agents/log/{agent}.md']); futext = sh(T + [f'cat {co}/site/agents/followups/{agent}.md'])
    open(f'{P}/{block}/log-at-archive.md', 'w').write(logtext); open(f'{P}/{block}/followups-at-archive.md', 'w').write(futext)
    for (rid, fid, t0, t1, key), end in zip(runs, ends):
        d = f'{P}/{block}/{rid}'; os.makedirs(d, exist_ok=True)
        span = [(t, l, e) for t, l, e in tx if t0 <= t <= end]
        open(f'{d}/transcript.jsonl', 'w').write(''.join(l + '\n' for _, l, _ in span))
        calls = [e for _, _, e in span if isinstance(e.get('message'), dict) and e['message'].get('role') == 'assistant' and e['message'].get('usage')]
        out_tok = sum((e['message']['usage'].get('output_tokens') or 0) for e in calls)
        if agent == 'hermes':   # Hermes's model calls are in its agent.log, not its messages
            calls = [c for c in hcalls if t0 <= c[0] <= end]; out_tok = sum(c[1] for c in calls)
        tools = [(t, x) for t, _, e in span for x in (e.get('message', {}).get('content') or []) if isinstance(e.get('message'), dict) and isinstance(x, dict) and x.get('type') == 'tool_use']
        # fix 2: a send is a tool call whose result carries site-notify's own success line, however it was called; a call
        # that looks like site-notify without that line (refused, failed, --help) is listed as NOT SENT (best effort)
        res, notify, unsent = RES, [], []   # results from the whole transcript: one may land after the window
        for t, x, e in tools_e(span):
            r_ = res(x, e, t)
            if SENT.search(r_): notify.append(f"{iso(t)} {cmd_of(x)}")
            elif runs_notify(cmd_of(x)) and not only_help(cmd_of(x)): unsent.append(f"{iso(t)} {cmd_of(x)}")   # item 8: --help isn't an attempt
        open(f'{d}/notify.txt', 'w').write(('\n'.join(notify) + '\n' if notify else 'none (no site-notify sent in this run\'s window)\n')
                                           + ''.join(f'NOT SENT (refused or failed): {u}\n' for u in unsent))
        # the log and follow-ups by each line's own timestamp (uncommitted lines land in the right run)
        # item 7: stamps run 1-2 min late, so a line stamped up to 3 min after the window's end still belongs to it
        open(f'{d}/log.txt', 'w').write(''.join(l + '\n' for l in logtext.splitlines() if (x := line_time(l)) and t0 <= x < end + 180))
        # item 5: follow-ups carry no stamps; their changes in the window, from the file's own commits (+ added, - closed)
        fu = sh(T + [f"git -C {co} log --since=@{t0} --until=@{int(end) - 1} --format='== %cI %h %s' -p -- site/agents/followups/{agent}.md"])
        fu = '\n'.join(l for l in fu.splitlines() if l.startswith('== ') or (l[:1] in '+-' and not l.startswith(('+++', '---'))))
        open(f'{d}/followups.txt', 'w').write(fu + '\n' if fu.strip() else 'none (no follow-up changed in this run\'s window)\n')
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
        # fix 5: every tool call naming the other agent's files (its checkout, state, log or follow-ups), blocked or not
        cross = [f"{iso(t)} {cmd_of(x) or json.dumps(x.get('input'))[:300]}" for t, x in tools if re.search(OTHER[agent], cmd_of(x) or json.dumps(x.get('input')))]
        open(f'{d}/cross-reads.txt', 'w').write('\n'.join(cross) + '\n' if cross else "none (no tool call named the other agent's files)\n")
        # fix 4: every sweep in the window, from site-sweep's own record (it covers Hermes's scripted pre-check too)
        sweeps = [l for l in sweeplog.splitlines() if (x := line_time(l)) and t0 <= x <= end]
        open(f'{d}/sweep.txt', 'w').write('\n'.join(sweeps) + '\n' if sweeps else 'none (no site-sweep run in this window)\n')
        # fix 3: the other runs whose windows overlap this one's (one incident by design, or a fault during a cut)
        shares = [r[0] for r, e2 in zip(runs, ends) if r[0] != rid and r[2] < end and t0 < e2]   # overlap, not touch
        # item 6: the daily morning report (07:01 local, 13:01Z) inside this window: say so, so it isn't read as the fault's
        morning = [iso(m) for m in range(int(t0 // 86400) * 86400 + 13 * 3600 + 60, int(end) + 1, 86400) if t0 <= m < end]
        run = {'run': rid, 'fault': fid, 'block': block, 'pins': pins, 'shares_window_with': shares, 'morning_report_in_window': morning, 'injected': iso(t0), 'reverted_or_ended': iso(t1), 'archive_until': iso(end),
               'first_tool_call_after': iso(tools[0][0]) if tools else None,
               'first_action_on_target': iso(touch[0]) if touch else None,
               'alert_arrival': iso(alert[0]) if alert else None, 'alert_source': src,
               'time_to_notice_from_alert_s': round(touch[0] - alert[0]) if touch and alert else None,   # from the alert's arrival
               'time_to_notice_from_injection_s': round(touch[0] - t0) if touch else None, 'model_calls': len(calls), **({'usage': usage_of(husage, t0, end)} if agent == 'hermes' and provider == PLUGIN else {}), 'output_tokens': out_tok,
               'transcript_lines': len(span), 'site_notify_calls': len(notify), 'site_notify_not_sent': len(unsent), 'cross_reads': len(cross), 'sweeps': len(sweeps), 'scan': hits or 'clean', 'scan_review': review}
        json.dump(run, open(f'{d}/run.json', 'w'), indent=1); summary.append(run)
        print(f"{rid}: {iso(t0)[11:16]}-{iso(t1)[11:16]}Z, {len(span)} lines, {len(calls)} calls, {out_tok} out tokens, notify {len(notify)}, scan {'clean' if not hits else len(hits)}")
    # item 6: each morning report in the block (07:01 local, 13:01Z) gets a packet of its own: its transcript and sends
    b0, b1 = min(r[2] for r in runs), max(ends)
    for m in range(int(b0 // 86400) * 86400 + 13 * 3600 + 60, int(b1) + 1, 86400):
        if not b0 <= m < b1: continue
        d = f"{P}/{block}/morning-report-{time.strftime('%Y%m%d', time.gmtime(m))}"; os.makedirs(d, exist_ok=True)
        span = [(t, l, e) for t, l, e in tx if m - 60 <= t <= m + (104 if agent == 'hermes' else 44) * 60]   # Hermes may wait an hour first
        open(f'{d}/transcript.jsonl', 'w').write(''.join(l + '\n' for _, l, _ in span))
        sent = [f"{iso(t)} {cmd_of(x)}" for t, x, e in tools_e(span) if SENT.search(RES(x, e, t))]
        open(f'{d}/notify.txt', 'w').write('\n'.join(sent) + '\n' if sent else 'none\n')
        rep_ = f'{d}/.scan.json'   # scanned like every packet
        subprocess.run([G, 'dir', d, '--config', RULES, '--redact', '--no-banner', '--log-level', 'error', '--exit-code', '0', '--report-format', 'json', '--report-path', rep_], capture_output=True)
        found_ = json.load(open(rep_)) if os.path.getsize(rep_) else []; os.remove(rep_)
        open(f'{d}/scan.txt', 'w').write('clean\n' if not found_ else 'TO REVIEW: ' + ', '.join(f"{os.path.basename(x['File'])}:{x['StartLine']} {x['RuleID']}" for x in found_) + '\n')
        print(f"{os.path.basename(d)}: {len(span)} lines, {len(sent)} sent, scan {'clean' if not found_ else len(found_)}")
    json.dump(summary, open(f'{P}/{block}/summary.json', 'w'), indent=1)
    if agent == 'hermes' and provider == PLUGIN:   # the block's total, from the unique calls (the f10 and f2 packets overlap)
        json.dump({'from': iso(b0), 'to': iso(b1), 'usage': usage_of(husage, b0, b1)}, open(f'{P}/{block}/usage-block.json', 'w'), indent=1)

if __name__ == '__main__': main(*sys.argv[1:4])
