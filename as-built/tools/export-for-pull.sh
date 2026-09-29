#!/usr/bin/env bash
# export-for-pull.sh: the only thing the orchestrator pulls from the agent box (from 20260928). Builds
# ~/.orch/export/ afresh: ~/.orch/turn-*.json and turn-*.err, and every .jsonl transcript under
# ~/.claude/projects (as transcripts/<project>/...), with every secret value the builder can read replaced
# by [redacted:<source>]. The sources:
#  - every item in both vaults (the hosted org and the site's Vaultwarden): passwords, TOTP seeds,
#    custom-field values and notes;
#  - every item's password history (old passwords the vault still holds);
#  - the values in ~/.config/seed/*.env;
#  - dead values that still sit in old transcripts: the hidden fields of the site vault's item
#    `redact: dead values` (e.g. the builder's Vaultwarden password rotated on 20260927), labelled
#    dead:<field name>. They were first kept in /dev/shm, which lost them within the hour (logind's
#    RemoveIPC empties a user's /dev/shm when their last session ends), and an export without them
#    still reported residual 0 (20260928). So the export fails if that item can't be read, or holds
#    no hidden field.
# Each secret is matched whole, JSON-escaped once and twice, and as every piece of 6 or more characters
# cut at whitespace and colons, at shell metacharacters, and into alphanumeric runs (the fragments of
# 20260928 were cut at shell metacharacters). Notes and text custom fields (type 0: bucket, endpoint,
# scope, plan...) are prose or metadata as often as secrets, so they and their pieces count only when they
# look like one: 8 or more characters with letters and digits, or 20 or more (a note that is a date, or a
# field that is a word, would otherwise redact every date and that word everywhere). Passwords, TOTP
# seeds, hidden fields, .env values and dead values count whole and in every piece of 6 or more.
# Prints counts per file only, never a value. Checks that every line of every JSON output still parses,
# and that no secret or piece is left in the export outside the [redacted:...] marks (residual 0; a label
# may itself contain a piece, e.g. an item named after its bucket). Exit 1 otherwise, and
# the export is removed: no export, no pull.
set -euo pipefail
X="$HOME/.orch/export"
tmp=$(mktemp -d /dev/shm/seed-export.XXXXXX); chmod 700 "$tmp"; trap 'rm -rf -- "${tmp:?}"' EXIT
# both vaults' items, straight into files in RAM (0600), read by python, removed on exit
( set -a; . "$HOME/.config/seed/bw.env"; set +a; S=$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null </dev/null)
  [ -n "$S" ] || { echo "hosted vault: unlock failed" >&2; exit 1; }
  BW_SESSION=$S bw sync >/dev/null; BW_SESSION=$S bw list items > "$tmp/hosted.json"; BW_SESSION=$S bw lock >/dev/null )
( export BITWARDENCLI_APPDATA_DIR="$HOME/.config/seed/bw-local"; set -a; . "$HOME/.config/seed/bw-local.env"; set +a
  S=$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null </dev/null); [ -n "$S" ] || { echo "site vault: unlock failed" >&2; exit 1; }
  BW_SESSION=$S bw sync >/dev/null; BW_SESSION=$S bw list items > "$tmp/site.json"; BW_SESSION=$S bw lock >/dev/null )
rm -rf -- "${X:?}"; mkdir -p "$X/transcripts"; chmod 700 "$X"
python3 - "$tmp" "$X" <<'PY' || { rm -rf -- "${X:?}"; echo "the export was removed (a fault above): no export, no pull"; exit 1; }
import sys, os, re, json, glob, shlex
tmp, X = sys.argv[1], sys.argv[2]
H = os.path.expanduser('~')
secrets = {}          # value -> label (the first source that named it)
def add(v, label, kind):
    if not isinstance(v, str): return
    v = v.strip()
    looks = lambda p: len(p) >= 20 or (len(p) >= 8 and re.search(r'[A-Za-z]', p) and re.search(r'[0-9]', p))
    if len(v) < 6 or (kind == 'note' and not looks(v)): return
    secrets.setdefault(v, label)
    cuts = [re.split(r'[\s:]+', v), re.split(r'[\s:;&|<>()`$\'"\\]+', v), re.findall(r'[A-Za-z0-9]+', v)]
    for p in {p for c in cuts for p in c}:
        if len(p) < 6: continue
        if kind == 'note' and not looks(p): continue
        secrets.setdefault(p, label)
for vault in ('hosted', 'site'):
    for it in json.load(open(f'{tmp}/{vault}.json')):
        name = it.get('name', '?')
        lg = it.get('login') or {}
        add(lg.get('password'), name, 'secret'); add(lg.get('totp'), name, 'secret')
        for h in it.get('passwordHistory') or []: add(h.get('password'), f'{name}:history', 'secret')
        for f in it.get('fields') or []: add(f.get('value'), f'{name}:{f.get("name")}', 'note' if f.get('type') == 0 else 'secret')
        add(it.get('notes'), name, 'note')
for f in sorted(glob.glob(f'{H}/.config/seed/*.env')):
    for line in open(f):
        m = re.match(r'\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$', line.rstrip('\n'))
        if not m: continue
        try: val = ' '.join(shlex.split(m.group(2))) if m.group(2) else ''
        except ValueError: val = m.group(2)
        add(val, f'{os.path.basename(f)}:{m.group(1)}', 'secret')
dead = [it for it in json.load(open(f'{tmp}/site.json')) if it.get('name') == 'redact: dead values']
dead_f = [f for f in (dead[0].get('fields') or []) if f.get('type') == 1 and f.get('value')] if len(dead) == 1 else []
if not dead_f:
    print(f"FAULT: the site vault's item 'redact: dead values' is missing, duplicated or has no hidden field ({len(dead)} found); nothing exported")
    sys.exit(1)
for f in dead_f: add(f['value'], f'dead:{f.get("name")}', 'secret')
# every form a value can take in the files: raw, JSON-escaped once, and twice (JSON inside JSON)
forms = {}
for v, label in secrets.items():
    e1 = json.dumps(v)[1:-1]; e2 = json.dumps(e1)[1:-1]
    for form in (v, e1, e2): forms.setdefault(form, label)
for label in set(forms.values()): assert '"' not in label and '\\' not in label
pat = re.compile('|'.join(re.escape(k) for k in sorted(forms, key=len, reverse=True)))
def redact(text):
    n = 0
    def r(m):
        nonlocal n; n += 1; return f'[redacted:{forms[m.group(0)]}]'
    return pat.sub(r, text), n
files = [(p, os.path.basename(p)) for p in sorted(glob.glob(f'{H}/.orch/turn-*.json') + glob.glob(f'{H}/.orch/turn-*.err'))]
files += [(p, 'transcripts/' + os.path.relpath(p, f'{H}/.claude/projects')) for p in sorted(glob.glob(f'{H}/.claude/projects/**/*.jsonl', recursive=True))]
bad = 0; total = 0
print(f'secrets: {len(secrets)} values and pieces from {len(json.load(open(f"{tmp}/hosted.json")))} hosted and {len(json.load(open(f"{tmp}/site.json")))} site items, the .env files and {len(dead_f)} dead value(s); {len(forms)} forms matched')
for src, rel in files:
    text = open(src, encoding='utf-8', errors='surrogateescape').read()
    out, n = redact(text); total += n
    dst = os.path.join(X, rel); os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(dst, 'w', encoding='utf-8', errors='surrogateescape') as fh: fh.write(out)
    os.chmod(dst, 0o600)
    ok = 'text'
    if rel.endswith(('.json', '.jsonl')):
        lines = [l for l in out.splitlines() if l.strip()]
        try:
            json.loads(out) if (rel.endswith('.json') and out.strip()) else None; ok = 'json ok'
        except ValueError:
            try:
                for l in lines: json.loads(l)
                ok = f'{len(lines)} lines ok'
            except ValueError:
                ok = 'JSON BROKEN'; bad = 1
        if rel.endswith('.jsonl'):
            try:
                for l in lines: json.loads(l)
                ok = f'{len(lines)} lines ok'
            except ValueError:
                ok = 'JSON BROKEN'; bad = 1
    left = len(pat.findall(re.sub(r'\[redacted:[^\]]*\]', '\x00', out)))
    if left: bad = 1
    print(f'{rel}: {n} redacted, {ok}, residual {left}')
print(f'total: {len(files)} files, {total} redactions; {"FAULT" if bad else "all JSON parses, residual 0"}')
sys.exit(bad)
PY
