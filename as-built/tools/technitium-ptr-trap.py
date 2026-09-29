#!/usr/bin/env python3
"""The PTR trap of design › DNS, shown on ns1 with a scratch zone (R5.10), then removed:
Technitium's API `ptr=true` flag treats the reverse record as a replace, so deleting one A record
with it deletes the reverse entry every other record at that address had. push.py never uses the
flag and keeps PTRs as records of their own, deleted by exact value; the second half shows that
deleting one explicit PTR leaves the others. Zones: trap-test.seed.example.com and 2.0.192.in-addr.arpa
(TEST-NET-1, documentation only: nothing is reached). Admin password from TECHNITIUM_PW_CORE."""
import json, os, urllib.parse, urllib.request
B = 'http://192.168.1.15:5380/api/'
def call(path, tok=None, **p):
    req = urllib.request.Request(B + path, data=urllib.parse.urlencode(p).encode(), method='POST')
    if tok: req.add_header('Authorization', f'Bearer {tok}')
    j = json.load(urllib.request.urlopen(req, timeout=30))
    if j.get('status') != 'ok': raise SystemExit(f'{path}: {j}')
    return j.get('response', j)
tok = call('user/login', user='admin', **{'pass': os.environ['TECHNITIUM_PW_CORE']})['token']
Z, R, IP = 'trap-test.seed.example.com', '2.0.192.in-addr.arpa', '192.0.2.5'
def ptrs():
    r = call('zones/records/get', tok, domain='5.' + R, zone=R)['records']
    return sorted(x['rData']['ptrName'] for x in r if x['type'] == 'PTR')
def step(what, path, **p):
    try: call(path, tok, **p); res = 'ok'
    except SystemExit as e: res = 'ERROR ' + str(e).split("'errorMessage': ")[-1].rstrip('}')
    a = sorted(x['name'] for x in call('zones/records/get', tok, domain=Z, zone=Z, listZone='true')['records'] if x['type'] == 'A')
    print(f'{what}: {res}; A records now {a}; PTRs at {IP}: {ptrs()}')
try:
    call('zones/create', tok, zone=Z, type='Primary'); call('zones/create', tok, zone='192.0.2.0/24', type='Primary')
    print('1. the ptr flag')
    step('   add A a with ptr=true', 'zones/records/add', zone=Z, domain='a.' + Z, type='A', ipAddress=IP, ptr='true')
    step('   add A b (same address) with ptr=true', 'zones/records/add', zone=Z, domain='b.' + Z, type='A', ipAddress=IP, ptr='true')
    step('   delete A a with ptr=true', 'zones/records/delete', zone=Z, domain='a.' + Z, type='A', ipAddress=IP, ptr='true')
    step('   delete A b without the flag', 'zones/records/delete', zone=Z, domain='b.' + Z, type='A', ipAddress=IP)
    step('   delete the remaining PTR by value', 'zones/records/delete', zone=R, domain='5.' + R, type='PTR', ptrName='b.' + Z)
    print("2. push.py's way: no flag; A and PTR records of their own")
    for n in ('a', 'b'):
        step(f'   add A {n} (no flag)', 'zones/records/add', zone=Z, domain=f'{n}.{Z}', type='A', ipAddress=IP)
        step(f'   add PTR -> {n}', 'zones/records/add', zone=R, domain='5.' + R, type='PTR', ptrName=f'{n}.{Z}')
    step('   delete A a (no flag)', 'zones/records/delete', zone=Z, domain='a.' + Z, type='A', ipAddress=IP)
    step('   delete PTR -> a by value', 'zones/records/delete', zone=R, domain='5.' + R, type='PTR', ptrName='a.' + Z)
finally:
    for z in (Z, R):
        try: call('zones/delete', tok, zone=z)
        except SystemExit as e: print('cleanup:', e)
    print('scratch zones deleted:', not any(z['name'] in (Z, R) for z in call('zones/list', tok)['zones']))
    call('user/logout', tok)
