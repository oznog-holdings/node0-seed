#!/usr/bin/env python3
"""encoders.py: compute's encoder models and the secret scanner, behind the gateway (the utility tier, 20261002).
llama.cpp can't serve these, so a small HTTP service does: started by serve.sh beside the router, so the supervisor
counts its footprint with the rest and stops it with the rest. Python's own HTTP server, no framework; models on the
GPU (Metal, through torch's MPS; on the CPU PII-Tracer took minutes for a 40,000-character text); one lock per model.
  POST /v1/secrets   {"text"}                      two layers (the bar: zero secrets out): gitleaks (pinned binary) with its
                                                   defaults and the site's rules (encoders/gitleaks.toml), then PII-Tracer's
                                                   "secret" class. -> {"findings": [{layer, rule, line, start, end}]}
  POST /v1/pii       {"text"}                      PII-Tracer -> {"spans": [{label, start, end}], "sensitivity", "masked"}
  POST /v1/classify  {"text", "labels": {task: [labels] or {label: description}}}   GLiNER2.5-Decide -> {task: label}; only
                                                   with ENCODERS_GLINER=1 (out of the agents' path from 20261002), else 501
  POST /v1/promptguard {"text"}                    Llama Prompt Guard 2 86M (Meta's Llama 4 Community License, accepted by the
                                                   owner 20261002; rev a8ded8e6); 501 if not installed
  POST /v1/injection {"text"}                      prompt-injection screening, two opinions: Qwen3Guard-Gen-0.6B (Apache-2.0;
                                                   Unsafe/Controversial with its Jailbreak category) and protectai's
                                                   deberta-v3-base-prompt-injection-v2 (Apache-2.0, archived; English), and
                                                   Prompt Guard 2 when installed
  POST /v1/audio/transcriptions (multipart)        speech-to-text through the router's model, the "language X<asr_text>"
                                                   prefix stripped (so no caller has to); -> {"text"}
  GET  /health
Every request needs the gateway's key (Authorization: Bearer, the file ~/.config/seed/llama.key). Texts over 200,000
characters are refused. Run: venv/bin/python encoders.py <listen address> <port>."""
import hmac, http.client, json, os, re, signal, subprocess, sys, tempfile, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
U = os.path.expanduser('~/.local/share/seed/utility'); M = f'{U}/models'
KEY = open(os.path.expanduser('~/.config/seed/llama.key')).read().strip()
MAXLEN = 200_000
BUSY = threading.BoundedSemaphore(4)   # at most 4 requests at once; more get 503
CHILDREN = set()                       # gitleaks runs in flight: killed with this service
import torch
torch.set_num_threads(4)
DEV = 'mps' if torch.backends.mps.is_available() else 'cpu'
from transformers import AutoModel, AutoModelForCausalLM, AutoModelForSequenceClassification, AutoTokenizer
from gliner2 import AutoExtractor
pii = AutoModel.from_pretrained(f'{M}/PII-Tracer', trust_remote_code=True).eval().to(DEV); pii_lock = threading.Lock()
# GLiNER2.5-Decide: out of the agents' path (20261002: with label descriptions it typed 45/50 site items right, but
# judged urgency 16/50); loaded only with ENCODERS_GLINER=1, for Paperless's document sorting later
gli = None; gli_lock = threading.Lock()
if os.environ.get('ENCODERS_GLINER') == '1':
    gli = AutoExtractor.from_pretrained(f'{M}/GLiNER2.5-Decide')
    try: gli = gli.to(DEV)
    except Exception: pass   # GLiNER stays on the CPU if it can't move
guard_tok = AutoTokenizer.from_pretrained(f'{M}/Qwen3Guard-Gen-0.6B')
guard = AutoModelForCausalLM.from_pretrained(f'{M}/Qwen3Guard-Gen-0.6B', dtype=torch.bfloat16).eval().to(DEV); guard_lock = threading.Lock()
inj_tok = AutoTokenizer.from_pretrained(f'{M}/deberta-v3-base-prompt-injection-v2')
inj = AutoModelForSequenceClassification.from_pretrained(f'{M}/deberta-v3-base-prompt-injection-v2').eval().to(DEV); inj_lock = threading.Lock()
GITLEAKS_CONFIG = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'encoders', 'gitleaks.toml')
ROUTER = (os.environ.get('LISTEN', '192.168.1.20'), int(os.environ.get('PORT', '8080')))
pg = None; pg_lock = threading.Lock()
if os.path.isdir(f'{M}/Llama-Prompt-Guard-2-86M'):
    pg_tok = AutoTokenizer.from_pretrained(f'{M}/Llama-Prompt-Guard-2-86M')
    pg = AutoModelForSequenceClassification.from_pretrained(f'{M}/Llama-Prompt-Guard-2-86M').eval().to(DEV)   # Meta's licence: accepted by the owner, 20261002

def secrets(text):
    with tempfile.TemporaryDirectory() as d:   # the report goes to a private temporary file, never a terminal
        rep = f'{d}/r.json'
        p = subprocess.Popen([f'{U}/bin/gitleaks', 'stdin', '--config', GITLEAKS_CONFIG, '--no-banner', '--redact', '--report-format', 'json', '--report-path', rep,
                              '--exit-code', '0', '--log-level', 'error'], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        CHILDREN.add(p)
        try: p.communicate(text.encode(), timeout=60)
        except subprocess.TimeoutExpired: p.kill(); p.wait(); raise RuntimeError('gitleaks timed out')
        finally: CHILDREN.discard(p)
        if p.returncode != 0: raise RuntimeError(f'gitleaks exited {p.returncode}')
        found = json.load(open(rep)) if os.path.getsize(rep) else []
    out = [{'layer': 'gitleaks', 'rule': f.get('RuleID'), 'line': f.get('StartLine'), 'start': f.get('StartColumn'), 'end': f.get('EndColumn'),
            'entropy': round(f.get('Entropy') or 0, 2)} for f in found]
    # the second layer: PII-Tracer's "secret" class (it caught a quoted password and a key id gitleaks's defaults
    # missed, 20261002); its character spans turned into gitleaks's line and columns (1-based)
    for s in pii_spans(text)['spans']:
        if s['label'] != 'secret': continue
        line = text.count('\n', 0, s['start']) + 1; col = s['start'] - (text.rfind('\n', 0, s['start']) + 1) + 1
        out.append({'layer': 'pii-tracer', 'rule': 'secret', 'line': line, 'start': col, 'end': col + (s['end'] - s['start']) - 1})
    return {'findings': out}

pii_tok = AutoTokenizer.from_pretrained(f'{M}/PII-Tracer', trust_remote_code=True)   # its repo's code, pinned (pins)
def chunks(text, size=3500, overlap=300):   # PII-Tracer reads at most 4,096 tokens: windows of 3,500 tokens, cut on the
    offs = pii_tok(text, add_special_tokens=False, return_offsets_mapping=True)['offset_mapping']   # tokenizer's own
    if len(offs) <= size: yield 0, text; return                                                     # boundaries
    i = 0
    while i < len(offs):
        j = min(len(offs), i + size); a, b = offs[i][0], offs[j - 1][1]
        yield a, text[a:b]
        if j >= len(offs): break
        i = j - overlap

def pii_spans(text):
    spans, sens = {}, 0.0
    for off, part in chunks(text):
        with pii_lock, torch.inference_mode(): ss, s = pii.predict(part)
        sens = max(sens, float(s))
        for x in ss: spans[(x.start + off, x.end + off)] = x.label   # the overlap finds a span twice: once kept
    # overlapping spans (the same name seen from two windows, cut differently) merged into their union
    merged = []
    for (a, b), lab in sorted(spans.items()):
        if merged and a < merged[-1]['end']: merged[-1]['end'] = max(merged[-1]['end'], b)
        else: merged.append({'label': lab, 'start': a, 'end': b})
    spans = merged
    masked, last = [], 0
    for s in sorted(spans, key=lambda s: s['start']):
        masked += [text[last:s['start']], f"[{s['label'].upper()}]"]; last = s['end']
    return {'spans': spans, 'sensitivity': round(sens, 4), 'masked': ''.join(masked) + text[last:]}

def classify(text, labels):
    if not isinstance(labels, dict) or not labels: raise ValueError('labels: {task: [label, ...]}')
    with gli_lock, torch.inference_mode(): return gli.classify_text(text, labels)

def injection(text):
    # Qwen3Guard-Gen reads the text as a user prompt and answers "Safety: ...", "Categories: ..."
    with guard_lock, torch.inference_mode():
        x = guard_tok.apply_chat_template([{'role': 'user', 'content': text[:16000]}], tokenize=False)
        ids = guard_tok([x], return_tensors='pt').to(DEV)
        g = guard.generate(**ids, max_new_tokens=32, do_sample=False)
        ans = guard_tok.decode(g[0][ids.input_ids.shape[1]:], skip_special_tokens=True)
    m = re.search(r'Safety: (Safe|Unsafe|Controversial)', ans)
    cats = re.findall(r'(Violent|Non-violent Illegal Acts|Sexual Content or Sexual Acts|PII|Suicide & Self-Harm|Unethical Acts|Politically Sensitive Topics|Copyright Violation|Jailbreak|None)', ans)
    with inj_lock, torch.inference_mode():
        y = inj_tok(text, return_tensors='pt', truncation=True, max_length=512).to(DEV)
        pr = torch.softmax(inj(**y).logits, -1)[0].float().cpu()
    lab = inj.config.id2label; k = max(range(len(pr)), key=lambda i: float(pr[i]))
    out = {'qwen3guard': {'safety': m.group(1) if m else None, 'categories': cats},
           'deberta': {'label': lab[k], 'score': round(float(pr[k]), 4)}}
    if pg is not None: out['promptguard'] = promptguard(text)   # Llama Prompt Guard 2 86M, once the owner's licence holds
    return out

def json_format(body, ctype):   # the multipart parts split on the boundary; only a form field (no filename) is touched
    m = re.search(r'boundary="?([^";]+)"?', ctype or '')
    if not m: raise ValueError('multipart/form-data with a boundary expected')
    sep = b'--' + m.group(1).encode(); parts = body.split(sep); out = []
    for part in parts:
        head, _, rest = part.partition(b'\r\n\r\n')
        if b'name="response_format"' in head and b'filename=' not in head and rest:
            part = head + b'\r\n\r\njson\r\n'   # the value ends at the part's CRLF before the next boundary
        out.append(part)
    return sep.join(out)

ASR_PREFIX = re.compile(r'^\s*language\s+[A-Za-z_ -]+?\s*<asr_text>\s*')
class UpstreamError(Exception): pass

def transcribe(body, ctype):
    # forwarded to the router's speech model as sent (multipart), the answer's text without the model's prefix
    # the router takes only response_format=json for transcription; OpenAI-style clients (the gateway's openai/) send
    # another: that one field rewritten in the multipart body
    body = json_format(body, ctype)
    c = http.client.HTTPConnection(*ROUTER, timeout=600)
    c.request('POST', '/v1/audio/transcriptions', body, {'Content-Type': ctype, 'Authorization': 'Bearer ' + KEY, 'Content-Length': str(len(body))})
    r = c.getresponse(); data = r.read()
    if r.status != 200:   # the router's own message to this service's log only; the caller gets a fixed answer
        print(f'transcribe: the router answered {r.status}', file=sys.stderr, flush=True)
        raise UpstreamError()
    return {'text': ASR_PREFIX.sub('', json.loads(data).get('text', ''))}

def promptguard(text):
    with pg_lock, torch.inference_mode():
        x = pg_tok(text, return_tensors='pt', truncation=True, max_length=512).to(DEV)
        p = torch.softmax(pg(**x).logits, -1)[0].float().cpu()
    return {'malicious': round(float(p[1]), 4), 'label': 'malicious' if p[1] > 0.5 else 'benign'}

class H(BaseHTTPRequestHandler):
    server_version = 'seed-encoders'
    timeout = 30   # a socket that stalls for 30 s is dropped
    def log_message(self, *a): pass
    def reply(self, code, obj):
        b = json.dumps(obj).encode(); self.send_response(code); self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(b))); self.end_headers(); self.wfile.write(b)
    def authed(self):
        h = self.headers.get('Authorization', '')
        return h.startswith('Bearer ') and hmac.compare_digest(h[7:].strip(), KEY)
    def do_GET(self):
        if self.path == '/health': return self.reply(200, {'status': 'ok', 'promptguard': pg is not None})
        self.reply(404, {'error': 'not found'})
    def do_POST(self):
        if not self.authed(): return self.reply(401, {'error': 'unauthorized'})
        if not BUSY.acquire(blocking=False): return self.reply(503, {'error': 'busy: retry'})
        try:
            n = int(self.headers.get('Content-Length', -1))
            if n < 0: return self.reply(411, {'error': 'Content-Length required'})
            if self.path == '/v1/audio/transcriptions':   # audio: its own limit, the body forwarded as it came
                if n > 50 * 2**20: return self.reply(413, {'error': 'audio over 50 MB'})
                t0 = time.time(); out = transcribe(self.rfile.read(n), self.headers.get('Content-Type', ''))
                out['seconds'] = round(time.time() - t0, 3); return self.reply(200, out)
            if n > 4 * MAXLEN: return self.reply(413, {'error': 'too large'})
            body = json.loads(self.rfile.read(n) or b'{}'); text = body.get('text')
            if not isinstance(text, str) or not text: return self.reply(400, {'error': 'text: a non-empty string'})
            if len(text) > MAXLEN: return self.reply(413, {'error': f'text over {MAXLEN} characters'})
            t0 = time.time()
            if self.path == '/v1/secrets': out = secrets(text)
            elif self.path == '/v1/pii': out = pii_spans(text)
            elif self.path == '/v1/classify':
                if gli is None: return self.reply(501, {'error': 'GLiNER is not loaded (out of the agents\' path, 20261002)'})
                out = classify(text, body.get('labels'))
            elif self.path == '/v1/injection': out = injection(text)
            elif self.path == '/v1/promptguard':
                if pg is None: return self.reply(501, {'error': 'Prompt Guard 2 is not installed: its licence is the owner\'s to accept'})
                out = promptguard(text)
            else: return self.reply(404, {'error': 'not found'})
            out = out if isinstance(out, dict) else {'result': out}; out['seconds'] = round(time.time() - t0, 3)
            self.reply(200, out)
        except UpstreamError: self.reply(502, {'error': 'the speech model failed'})
        except (ValueError, KeyError, json.JSONDecodeError) as e: self.reply(400, {'error': str(e)[:200]})
        except Exception as e: self.reply(500, {'error': type(e).__name__})
        finally: BUSY.release()

def bye(*_):   # stopped (the supervisor, serve.sh): no gitleaks left behind
    for p in list(CHILDREN):
        try: p.kill()
        except Exception: pass
    os._exit(0)

if __name__ == '__main__':
    signal.signal(signal.SIGTERM, bye); signal.signal(signal.SIGINT, bye)
    ThreadingHTTPServer((sys.argv[1], int(sys.argv[2])), H).serve_forever()
