#!/usr/bin/env python3
"""redact-stream.py: the builder's output redactor (20261003, the orchestrator's structural control after three
secrets printed in four days). Every Bash command's output passes through it before the builder (Claude Code) sees
it (pretooluse-redact.py wraps each command). Streaming, line by line, flushed per line; bytes that aren't UTF-8
pass through unchanged. Masks, keeping what kind of thing it was:
  PEM private-key blocks (BEGIN ... END, swallowed whole), ntfy tk_ tokens, age secret keys, provider keys (sk-,
  sk_live_, rk_live_, ghp_, github_pat_, glpat-, xox?-, AKIA/ASIA ids, AIza), Bearer and Basic credentials,
  credentials in URLs, values of password/passwd/pwd/token/secret/api key/access key/private key/auth assignments,
  and long high-entropy strings after = or : (letters and digits, 24+ characters, entropy >= 3.5 bits).
Not handled: UTF-16 output; a quoted value that spans lines (each line is redacted on its own); a prompt without a newline appears when its line completes (no tty here).
Not masked: shell references ($VAR, $(...), ${...}), and pure hex (hashes, commit ids: a hex secret is still caught
when its name says what it is). The mask is [REDACTED:<kind>]. Exit code: always 0 (the wrapper keeps the command's)."""
import math, re, sys

M = lambda k: f'[REDACTED:{k}]'
SHAPES = [
    (re.compile(r'tk_[a-z0-9]{8,}'), M('ntfy-token')),
    (re.compile(r'AGE-SECRET-KEY-1[0-9A-Z]{20,}'), M('age-key')),
    (re.compile(r'\b(?:sk|rk)[-_](?:live|test|ant|proj|svcacct|or)?[-_]?[A-Za-z0-9_-]{16,}'), M('api-key')),
    (re.compile(r'\b(?:ghp|gho|ghs|ghu)_[A-Za-z0-9]{20,}|\bgithub_pat_[A-Za-z0-9_]{20,}|\bglpat-[A-Za-z0-9_-]{16,}'), M('git-token')),
    (re.compile(r'\bxox[abprs]-[A-Za-z0-9-]{10,}'), M('slack-token')),
    (re.compile(r'\b(?:AKIA|ASIA)[A-Z2-7]{16}\b'), M('aws-key-id')),
    (re.compile(r'\bAIza[A-Za-z0-9_-]{30,}'), M('google-key')),
    (re.compile(r'(?i)\b(bearer)\s+(?![$%(<{])[A-Za-z0-9._~+/=-]{8,}'), lambda m: f'{m.group(1)} ' + M('bearer')),
    (re.compile(r'(?i)\b(basic)\s+(?![$%(<{])[A-Za-z0-9+/=]{8,}'), lambda m: f'{m.group(1)} ' + M('basic')),
    (re.compile(r'(://[^/\s:@"\'<>]{1,64}:)(?![$%({<])[^@\s/"\'<>]{2,}@'), lambda m: m.group(1) + M('url-credential') + '@'),
    # a quoted value: to its closing quote (spaces and all); an unquoted one: to the next space or delimiter
    (re.compile(r'(?i)(?<!\[)\b([A-Za-z0-9_.-]*(?:password|passwd|pwd|passphrase|token|secret|api[_-]?key|apikey|access[_-]?key|private[_-]?key|auth|credential)s?)'
                r'(["\']?\s*[=:]\s*)(["\'])(?![$%(<{\[])(?!(?:true|false|none|null|yes|no|required|optional)\3)((?:\\.|(?!\3).){4,}?)\3'),
     lambda m: m.group(1) + m.group(2) + m.group(3) + M('value') + m.group(3)),
    (re.compile(r'(?i)(?<!\[)\b([A-Za-z0-9_.-]*(?:password|passwd|pwd|passphrase|token|secret|api[_-]?key|apikey|access[_-]?key|private[_-]?key|auth|credential)s?)'
                r'(["\']?\s*[=:]\s*)(?![$%(<{\["\'])(?!\[REDACTED)(?!(?:true|false|none|null|yes|no|required|optional)\b)([^\s"\',;)}\]]{4,})'),
     lambda m: m.group(1) + m.group(2) + M('value')),
]
HIGH = re.compile(r'([=:]\s*["\']?)([A-Za-z0-9+/_.~-]{24,})')
PEM_BEGIN = re.compile(r'-----BEGIN [A-Z0-9 ]*(?:PRIVATE KEY|ENCRYPTED|SECRET)[A-Z0-9 ]*-----')
PEM_END = re.compile(r'-----END [A-Z0-9 ]*-----')

def entropy(s):
    return -sum(c / len(s) * math.log2(c / len(s)) for c in (s.count(x) for x in set(s)))

def high(m):
    v = m.group(2)
    if re.fullmatch(r'[0-9a-fA-F-]+', v) or not (re.search(r'[A-Za-z]', v) and re.search(r'\d', v)):
        return m.group(0)   # hex (a hash, a commit, a UUID), or letters only / digits only: left
    if '/' in v and v.count('/') >= 2 and not re.search(r'[+=]', v):
        return m.group(0)   # a path
    return m.group(1) + M('high-entropy') if entropy(v) >= 3.5 else m.group(0)

def line(s):
    for rx, rep in SHAPES: s = rx.sub(rep, s)
    return HIGH.sub(high, s)

MAXLINE = 1 << 20   # a line longer than 1 MiB is processed in 1 MiB pieces (memory stays bounded)

CARRY = 8192        # a long line's last 8 KiB go with the next piece, so a secret or a PEM marker on the cut is whole

def safe_cut(raw):
    """where to cut a long line: CARRY before its end, moved back to the start of any match that spans it (so a
    secret or a PEM marker is never split: it goes whole with the next piece)"""
    s = raw.decode('utf-8', 'surrogateescape'); p = len(s) - CARRY; moved = True
    while moved:
        moved = False
        for rx in [x for x, _ in SHAPES] + [HIGH, PEM_BEGIN]:
            for m in rx.finditer(s, max(0, p - CARRY), min(len(s), p + CARRY)):
                if m.start() < p < m.end(): p = m.start(); moved = True
    return len(s[:max(p, 0)].encode('utf-8', 'surrogateescape'))

def pieces(inp):
    carry = b''
    for raw in iter(lambda: inp.readline(MAXLINE), b''):
        raw = carry + raw; carry = b''
        if not raw.endswith(b'\n') and len(raw) >= MAXLINE:   # a cut inside a long line
            c = safe_cut(raw); carry, raw = raw[c:], raw[:c]
        yield raw
    if carry: yield carry

def main():
    out, inp, in_pem = sys.stdout.buffer, sys.stdin.buffer, False
    for raw in pieces(inp):
        s = raw.decode('utf-8', 'surrogateescape'); res = ''
        while s:   # every PEM block on the line, and a block that runs over lines
            if in_pem:
                e = PEM_END.search(s)
                if not e: s = ''; break
                in_pem = False; s = s[e.end():]; continue
            b = PEM_BEGIN.search(s)
            if not b: res += s; break
            res += s[:b.start()] + M('pem-block'); s = s[b.end():]; in_pem = True
        if in_pem and res and not res.endswith('\n'): res += '\n'
        out.write(line(res).encode('utf-8', 'surrogateescape')); out.flush()

if __name__ == '__main__':
    try: main()
    except BrokenPipeError: pass
