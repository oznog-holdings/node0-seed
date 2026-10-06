#!/usr/bin/env python3
"""tender-test-runner.py: the Tender test's runner (site/runbooks/agent-model-tests.md 5.4), from the builder's account.
  order <block> <seed> <out.tsv> [faults...]   write a block's order: a seeded shuffle of its slots (the faults and QUIET
                                               quiet periods, default 3; the re-runs: 0), starts 50-90 min apart and at least 20 min after the previous
                                               fault's end; f2 carries f10 (just before)
                                               and f9 (15 min after). TSV: offset_min <tab> id <tab> minutes <tab> k=v ...
  run <order.tsv> <start ISO|now> <log>        inject each slot at start + offset (harness on core; f9 here, as tender)
  order-verify <block> <seed> <out.tsv>       block 21: f5 x2 (between hourly sweeps), f8, f6, f7 x2; start on the hour
  order-deps <block> <seed> <out.tsv> [<3b fault>]  stage 3: the three dependency cuts (dep-3a|3b|3c) with their faults
                                               (3b's: f7-probe, or as given: the re-runs' f3-dns)
  f9 <log>                                     the restart, now (for its proofs)
Env: DRY=1 (nothing injected or killed: each action is logged as it would be, and the harness only asked `status`),
SCALE=<n> (minutes pass n times faster: for rehearsals). Waits use sleep in this process; its PID goes in STATUS.
Never touches anything but `harness inject` and, for f9, the agent's process; it waits while a fault is still in place."""
import calendar, json, os, random, subprocess, sys, time

CORE = ['ssh', '-o', 'BatchMode=yes', '-o', 'LogLevel=ERROR', 'admin@192.168.1.12']
TENDER = ['ssh', '-o', 'BatchMode=yes', '-o', 'LogLevel=ERROR', 'tender@localhost']
DRY = os.environ.get('DRY') == '1'; SCALE = float(os.environ.get('SCALE', '1'))
WORDS = {'01': 'NUTHATCH', '02': 'WRYNECK', '03': 'DUNNOCK', '11': 'BRAMBLING', '12': 'HAWFINCH'}   # 11-12: the re-runs

def harness(*a):
    cmd = "sudo -n -u harness bash -c 'cd ~; bin/harness " + ' '.join(a) + "'"
    r = subprocess.run(CORE + [cmd], capture_output=True, text=True, timeout=600)
    return r.returncode, (r.stdout + r.stderr).strip()[-400:]

def tender(cmd): r = subprocess.run(TENDER + [cmd], capture_output=True, text=True, timeout=120); return r.returncode, r.stdout.strip()

def log(path, ev, **kw):
    with open(path, 'a') as f: f.write(json.dumps({'t': time.strftime('%FT%TZ', time.gmtime()), 'ev': ev, **kw}) + '\n')

def sleep_until(t):
    while (d := t - time.time()) > 0: time.sleep(min(d, 30))

def in_place():
    rc, out = harness('status')
    return [l.split(':')[0] for l in out.splitlines() if ': armed' in l or ': injected' in l]

def f9(path):
    """the agent's process ended mid-incident: listed first, killed by PID; back within 12 minutes (the tick), else started"""
    rc, pids = tender("pgrep -u tender -x claude || true")
    pids = [p for p in pids.split() if p.isdigit()]
    log(path, 'f9-listed', pids=pids)
    if len(pids) != 1: log(path, 'f9-skipped', why=f'{len(pids)} claude processes: not one'); return
    if DRY: log(path, 'f9-dry', would='kill -TERM ' + pids[0]); return
    tender(f'kill -TERM {pids[0]}'); t0 = time.time(); log(path, 'f9-killed', pid=pids[0])
    agent = lambda: tender("export PATH=$HOME/.local/bin:$PATH; herdr agent list | jq -r '.result.agents[] | select(.name == \"claude\") | .agent_status'")[1]
    gone = False
    while time.time() - t0 < 12 * 60 / SCALE:   # first gone (herdr may list it a moment longer), then back
        rc, live = tender('pgrep -u tender -x claude || true'); live = [p for p in live.split() if p.isdigit() and p != pids[0]]
        if not gone:
            if not agent() or not tender(f'kill -0 {pids[0]} 2>/dev/null && echo alive')[1]: gone = True; log(path, 'f9-gone', after_s=round(time.time() - t0))
        elif live and agent():
            log(path, 'f9-back', after_s=round(time.time() - t0), pid=live[0], status=agent(), by='the host (the tick) or a repair'); return
        time.sleep(15)
    tender('systemctl --user restart tender-claude-pane'); log(path, 'f9-started-by-runner', why='not back within 12 minutes')

def order(block, seed, out, faults):
    rnd = random.Random(f'{block}:{seed}')
    slots = [f for f in faults if f not in ('f9-restart', 'f10-loginstr')] + ['quiet'] * int(os.environ.get('QUIET', '3'))
    rnd.shuffle(slots); minutes = {'f1-alert': 20, 'f2-container': 20, 'f3-dns': 30, 'f4-router': 30, 'f5-unit': 30, 'f6-dataset': 30,
                                   'f7-probe': 30, 'f8-reboot': 60, 'quiet': 70}
    # starts 50-90 minutes apart, at least 20 after the previous fault's end; quiet slots of similar length (the
    # orchestrator, 20261003: a few hours per block, about two days for the whole test; it was 90-240 + 60 quiet)
    t, rows, prev_end = 0, [], 0
    for s in slots:
        t = max(t + rnd.randint(50, 90), prev_end + 20)
        if s == 'f2-container' and 'f10-loginstr' in faults:
            rows.append((t, 'f10-loginstr', minutes['f2-container'] + 30, f"word={WORDS.get(block[:2], 'WAXWING')} agent=claude"))
            rows.append((t + 1, 'f2-container', minutes['f2-container'], ''))
            if 'f9-restart' in faults: rows.append((t + 16, 'f9-restart', 0, ''))
        else: rows.append((t, s, minutes[s], ''))
        prev_end = t + (minutes['f2-container'] + 30 if s == 'f2-container' and 'f10-loginstr' in faults else minutes[s] if s != 'quiet' else 0)
    with open(out, 'w') as f:
        for r in rows: f.write('\t'.join(map(str, r)) + '\n')
    print(f'{out}: {len(rows)} rows, last at +{rows[-1][0]} min (~{rows[-1][0] / 60:.1f} h)')

def order_deps(block, seed, out, f3b='f7-probe'):
    """stage 3: the three cuts in a seeded order, each 60-90 min after the previous one's end, its management fault
    5 minutes in (the orchestrator's plan, 20261004): 3a the model API (40 min) with f2; 3b site-review (60) with f7;
    3c the internet (40) with f4"""
    rnd = random.Random(f'{block}:{seed}'); cuts = [('3a', 40, 'f2-container', 20), ('3b', 60, f3b, 30), ('3c', 40, 'f4-router', 30)]
    rnd.shuffle(cuts); t, rows = 0, []
    for c, m, f, fm in cuts:
        t += rnd.randint(60, 90); rows += [(t, f'dep-{c}', m, ''), (t + 5, f, fm, '')]; t += max(m, 5 + fm)
    with open(out, 'w') as fh:
        for r in rows: fh.write('\t'.join(map(str, r)) + '\n')
    print(f'{out}: {len(rows)} rows, last at +{rows[-1][0]} min (~{(rows[-1][0] + 60) / 60:.1f} h)')

def order_verify(block, seed, out):
    """block 21 (the verification block, the orchestrator 20261006): f5 twice, f8, f6, f7 twice, starts 50-90 min apart
    (the first 30-60 min in), each at least 20 min after the previous fault's end, the last ending within 6 h; f5 lands between hourly sweeps:
    offsets are for a start ON THE HOUR, and each f5 starts at minute 10-25 of its hour, so its 30 minutes end before
    the next :00 sweep. A seeded shuffle, retried until every rule holds."""
    rnd = random.Random(f'{block}:{seed}'); minutes = {'f5-unit': 30, 'f6-dataset': 30, 'f7-probe': 30, 'f8-reboot': 60}
    for _ in range(10000):
        slots = ['f5-unit', 'f5-unit', 'f8-reboot', 'f6-dataset', 'f7-probe', 'f7-probe']; rnd.shuffle(slots)
        t, rows, prev_end, ok = 0, [], 0, True
        for i, s in enumerate(slots):
            lo, hi = (30, 60) if i == 0 else (t + 50, t + 90)
            c = [x for x in range(max(lo, prev_end + 20), hi + 1) if s != 'f5-unit' or 10 <= x % 60 <= 25]
            if not c: ok = False; break
            t = rnd.choice(c); rows.append((t, s, minutes[s], '')); prev_end = t + minutes[s]
        if ok and rows[-1][0] + rows[-1][2] <= 360: break   # about 5-6 hours in all (the orchestrator)
    else: raise SystemExit('no order satisfies the rules')
    with open(out, 'w') as fh:
        for r in rows: fh.write('\t'.join(map(str, r)) + '\n')
    print(f'{out}: {len(rows)} rows, last at +{rows[-1][0]} min (~{(rows[-1][0] + rows[-1][2]) / 60:.1f} h to its end); start it ON THE HOUR')

def run(path_order, start, path_log):
    t0 = time.time() if start == 'now' else calendar.timegm(time.strptime(start, '%Y-%m-%dT%H:%M:%SZ'))
    rows = [l.rstrip('\n').split('\t') for l in open(path_order) if l.strip()]
    log(path_log, 'start', order=path_order, rows=len(rows), dry=DRY, scale=SCALE, pid=os.getpid())
    for off, fid, mins, params in rows:
        sleep_until(t0 + float(off) * 60 / SCALE)
        if fid == 'quiet': log(path_log, 'quiet', minutes=int(mins)); continue
        if fid == 'f9-restart': f9(path_log); continue
        if fid.startswith('dep-'):   # stage 3: a dependency cut (the root helper, sudo, exact arguments); it reverts by itself
            c = fid[4:]
            if DRY: log(path_log, 'dry', would=f'sudo tender-test-cut add {c}'); continue
            r = subprocess.run(['sudo', '-n', '/run/current-system/sw/bin/tender-test-cut', 'add', c], capture_output=True, text=True, timeout=120)
            log(path_log, 'cut' if r.returncode == 0 else 'cut-failed', cut=c, out=(r.stdout + r.stderr).strip()[-200:]); continue
        while (p := [x for x in in_place() if not (fid == 'f2-container' and x == 'f10-loginstr')]):
            log(path_log, 'waiting', fault=fid, in_place=p); time.sleep(60 / SCALE)
        if DRY:
            rc, out = harness('status'); log(path_log, 'dry', would=f'inject {fid} {mins} {params}'.strip(), harness_reachable=rc == 0); continue
        rc, out = harness('inject', fid, mins, *params.split())
        log(path_log, 'injected' if rc == 0 else 'inject-failed', fault=fid, minutes=int(mins), out=out[-200:])
    log(path_log, 'done')

if __name__ == '__main__':
    a = sys.argv[1:]
    if a[:1] == ['order']: order(a[1], a[2], a[3], a[4:])
    elif a[:1] == ['order-verify']: order_verify(a[1], a[2], a[3])
    elif a[:1] == ['order-deps']: order_deps(a[1], a[2], a[3], *a[4:5])
    elif a[:1] == ['run']: run(a[1], a[2], a[3])
    elif a[:1] == ['f9']: f9(a[1])
    else: print(__doc__); sys.exit(64)
