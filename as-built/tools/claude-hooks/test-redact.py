#!/usr/bin/env python3
"""test-redact.py: tests the redactor and the hook's wrapper (20261003). The fakes are made here at run time from
random characters (no secret-shaped literal in this file or in a transcript), one per shape; then ordinary output,
to show the false masks; then the wrapper: exit codes, stderr, cd, heredocs, a background job, a missing redactor."""
import json, os, random, re, string, subprocess, sys, time
H = os.path.dirname(os.path.abspath(__file__)); RED = [sys.executable, f'{H}/redact-stream.py']
r = lambda n, a=string.ascii_letters + string.digits: ''.join(random.choice(a) for _ in range(n))
lo = string.ascii_lowercase + string.digits
fakes = {
 'ntfy token': 'tk_' + r(29, lo),
 'age key': 'AGE-SECRET-KEY-1' + r(58, '023456789ACDEFGHJKLMNPQRSTUVWXYZ'),
 'sk- key': 'sk-' + 'ant-api03-' + r(40, string.ascii_letters + string.digits + '-_'),
 'sk_live key': 'sk' + '_live_' + r(24),
 'github token': 'gh' + 'p_' + r(36),
 'aws key id': 'AK' + 'IA' + r(16, string.ascii_uppercase + '234567'),
 'bearer': 'Authorization: Bear' + 'er ' + r(40),
 'basic auth': 'Authorization: Bas' + 'ic ' + r(32, string.ascii_letters + string.digits + '+/') + '==',
 'password=': 'pass' + 'word=' + r(14),
 'token=': 'TOK' + 'EN=' + r(20),
 'secret:': 'client_sec' + 'ret: "' + r(30) + '"',
 'url credentials': 'https://admin:' + r(12) + '@nas.example.net/x',
 'high entropy after =': 'SOMETHING=' + r(40),
 'high entropy after :': 'value: ' + r(32),
}
pem = '-----BEGIN ' + 'OPENSSH PRIVATE KEY-----\n' + '\n'.join(r(70) for _ in range(4)) + '\n-----END OPENSSH PRIVATE KEY-----'
def red(text): return subprocess.run(RED, input=text.encode(), capture_output=True).stdout.decode()
fail = 0
print('== secrets (each must be masked; the line shows what was left)')
for k, v in fakes.items():
    out = red(f'before {v} after\n')
    secret = v.split('@')[0].rsplit(':', 1)[-1] if 'url' in k else v.rsplit(' ', 1)[-1].split('=', 1)[-1] if '=' in v.rstrip('=') else v.rsplit(' ', 1)[-1]
    secret = secret.strip('"')
    ok = secret not in out and secret[4:16] not in out
    fail += not ok; print(f"{'ok  ' if ok else 'FAIL'} {k:22} -> {out.strip()[:90]}")
out = red('key file:\n' + pem + '\nafter the key\n'); ok = 'BEGIN' not in out.replace('[REDACTED:pem-block]', '') and all(l not in out for l in pem.split('\n')[1:5])
fail += not ok; print(f"{'ok  ' if ok else 'FAIL'} {'PEM block':22} -> {out.strip()!r}"[:140])
print('== ordinary output (a [REDACTED] here is a false mask)')
ordinary = [
 'commit 5281137a9e0c4b1f2d3e4f5a6b7c8d9e0f1a2b3c', 'sha256:6c1f0d9e2b7a4c3e8f5d1a0b9c8e7f6a5d4c3b2a1f0e9d8c7b6a5f4e3d2c1b0a  model.gguf',
 '-rw-r--r-- 1 agent agent 4096 Oct  3 03:20 /work/agent/seed-lab/tools/rotate-ntfy-tokens.sh',
 '{"id":"alTIgXhv79b4","time":1790997452,"event":"message","topic":"seed"}', 'PR #87 merged; deploy ref 9cc3d34c7103903473e15bcdf3b44683ee07c853',
 'printf \'header = "Authorization: Bearer %s"\\n\' "$(cat /run/secrets/x)" | curl -K -', 'token=$(cat /run/secrets/tender_gateway_key)',
 'password_file: /secrets/ntfy-core-password', 'auth: true', 'Bearer token auth failed for 4 of 200', 'TOKEN_LIMIT: 4096',
 'url: https://ntfy.seed.example.com/seed?template=alertmanager', 'image: ghcr.io/berriai/litellm:main-v1.102.1@sha256:9e2a6b1d4c7f',
 'ssh-ed25519 AAAA...REPLACE-WITH-YOUR-PUBLIC-KEY', 'x-request-id: YOUR-WORK-VOLUME-UUID',
 'job: SmartPendingSectors infra-sdc', 'header [SECRET:token] and [SECRET:password#2], ask [PII:name]', 'cursor -> JKvU5v8QkHvH (2026-10-02T11:26:02Z)', 'hc tender-claude-work up last 2026-10-03T03:40:11+00:00',
]
for s in ordinary:
    o = red(s + '\n').rstrip('\n')
    print(f"{'MASK' if o != s else 'ok  '} {o[:120]}")
print('== the wrapper')
def wrap(cmd, redactor=None):
    ev = {'tool_name': 'Bash', 'tool_input': {'command': cmd, 'description': 'x'}}
    env = dict(os.environ)
    hook = f'{H}/pretooluse-redact.py'
    if redactor == 'missing':   # a copy of the hook beside no redactor
        import tempfile, shutil; d = tempfile.mkdtemp(); shutil.copy(hook, d); hook = f'{d}/pretooluse-redact.py'
    o = subprocess.run([sys.executable, hook], input=json.dumps(ev).encode(), capture_output=True)
    return json.loads(o.stdout)['hookSpecificOutput']
def run(cmd, after=''):
    h = wrap(cmd); t0 = time.time()   # as the harness: its saved stdout/stderr on 11/12; `after` runs in the same shell
    p = subprocess.run(['bash', '-c', 'exec 11>&1 12>&2\n' + h['updatedInput']['command'] + '\n' + after], capture_output=True, timeout=60)
    return p.returncode, p.stdout.decode(), time.time() - t0
tk = fakes['ntfy token']
cases = [
 ('exit code 3 kept', f'echo {tk}; exit_code() {{ return 3; }}; exit_code', lambda rc, o, t: rc == 3 and tk not in o and 'REDACTED' in o),
 ('stderr redacted too', f'echo {tk} >&2; false', lambda rc, o, t: rc == 1 and tk not in o and 'REDACTED' in o),
 ('stderr text arrives', 'echo visible-on-stderr >&2; python3 -c "raise SystemExit(\'py-stderr-visible\')"', lambda rc, o, t: rc == 1 and 'visible-on-stderr' in o and 'py-stderr-visible' in o),
 ('stderr is not /dev/null', 'readlink /proc/self/fd/2', lambda rc, o, t: '/dev/null' not in o),
 ('cd persists within the command', 'cd /tmp && pwd', lambda rc, o, t: rc == 0 and o.strip() == '/tmp'),
 ('a heredoc', "cat <<'EOF'\n" + tk + "\nplain line\nEOF", lambda rc, o, t: rc == 0 and tk not in o and 'plain line' in o),
 ('a background job (its output redirected) does not hold it', 'sleep 30 > /dev/null 2>&1 & echo started', lambda rc, o, t: rc == 0 and 'started' in o and t < 10),
 ('a pipeline with pipefail', 'set -o pipefail; false | cat', lambda rc, o, t: rc == 1),
 ('writing to the harness\'s saved stdout (fd 11) leaks nothing', f'printf "%s\\n" {tk} >&11; echo after', lambda rc, o, t: tk not in o),
 ('a syntax error that quotes a secret', f'echo "{tk}', lambda rc, o, t: rc != 0 and tk not in o),
 ('a trailing backslash', 'echo a \\', lambda rc, o, t: rc == 0 and o.strip() == subprocess.run(['bash', '-c', 'echo a \\'], capture_output=True, text=True).stdout.strip()),
 ('a comment-only command', '# nothing to run', lambda rc, o, t: rc == 0),
 ('exit 4 inside', 'echo x; exit 4', lambda rc, o, t: rc == 4 and 'x' in o),
 ('exec inside', f'exec echo {tk}', lambda rc, o, t: rc == 0 and tk not in o and 'REDACTED' in o),
 ('a background subshell with its output redirected', '(sleep 7; :) >/dev/null 2>&1 & echo started', lambda rc, o, t: 'started' in o and t < 6.5),
 ('a quote-heavy command', '''python3 -c "print('a\\'b', \\"c\\")"''', lambda rc, o, t: rc == 0 and "a'b c" in o),
]
for name, cmd, ok in cases:
    rc, o, t = run(cmd); good = ok(rc, o, t); fail += not good
    print(f"{'ok  ' if good else 'FAIL'} {name} (rc {rc}, {t:.1f} s): {o.strip()[:70]!r}")
import tempfile; pf = tempfile.mktemp()   # as the harness: its pwd goes to a file (pwd -P >| file)
rc, o, t = run('cd /tmp', after=f'pwd -P >| {pf}'); o = open(pf).read(); good = o.strip() == '/tmp'; fail += not good
print(f"{'ok  ' if good else 'FAIL'} cd persists after the wrapper: {o.strip()!r}")
sp = r(6) + ' ' + r(6) + ' ' + r(6); o = red(f'DB_PASSWORD="{sp}" next\n'); good = sp.split()[1] not in o and 'next' in o; fail += not good
print(f"{'ok  ' if good else 'FAIL'} a quoted password with spaces: {o.strip()}")
blk = lambda: '-----BEGIN ' + 'RSA PRIVATE KEY-----' + r(40) + '-----END RSA PRIVATE KEY-----'
b1, b2 = blk(), blk(); o = red(f'a {b1} b {b2} c\n'); good = b1[35:60] not in o and b2[35:60] not in o and o.count('pem-block') == 2; fail += not good
print(f"{'ok  ' if good else 'FAIL'} two PEM blocks on one line: {o.strip()}")
rc, o, t = run(f'printf "%s\\n" {tk} > /proc/$$/fd/1; echo after'); good = tk not in o; fail += not good
print(f"{'ok  ' if good else 'FAIL'} writing to the parent's /proc/$$/fd/1 leaks nothing: {o.strip()[:70]!r}")
rc, o, t = run('cd /tmp; exit 0', after=f'pwd -P >| {pf}'); o = open(pf).read(); good = o.strip() == '/tmp'; fail += not good
print(f"{'ok  ' if good else 'FAIL'} cd persists through exit: {o.strip()[-20:]!r}")
for q2 in (f'password="can\'t {r(8)} keep"', f"password='a \"{r(8)}\" b'"):
    o = red(q2 + ' tail\n'); sec = re.findall(r'[A-Za-z0-9]{8}', q2)[-1]; good = sec not in o and 'tail' in o; fail += not good
    print(f"{'ok  ' if good else 'FAIL'} a quoted value with the other quote inside: {o.strip()}")
big = 'x' * ((1 << 20) - 10) + tk + 'y' * 100 + '\n'; o = red(big); good = tk not in o and 'REDACTED:ntfy-token' in o; fail += not good
print(f"{'ok  ' if good else 'FAIL'} a token on the 1 MiB cut: masked {good}")
for off in range(-40, 41, 8):   # a token at every offset around where the carry cuts (1 MiB - 8 KiB)
    big = 'x' * ((1 << 20) - 8192 + off - 16) + tk + 'y' * 9000 + '\n'; o = red(big); good = tk not in o; fail += not good
    if not good: print(f"FAIL a token across the carry cut at offset {off}")
print('ok   a token across the carry cut, every offset tried') if not fail else None
h = wrap('echo hi', 'missing'); good = h['permissionDecision'] == 'deny'; fail += not good
print(f"{'ok  ' if good else 'FAIL'} the redactor missing: {h['permissionDecision']}: {h.get('permissionDecisionReason', '')[:80]}")
sys.exit(1 if fail else 0)
