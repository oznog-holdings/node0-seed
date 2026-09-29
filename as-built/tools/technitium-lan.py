#!/usr/bin/env python3
"""The lan.seed.example.com zone on ns1 (rung 6, after the cut-over). Leases were registered by the router's lease hook
until the cut-over (A records without a DHCID); from the cut-over Kea registers them (A + DHCID) and, by design
(conflict resolution check-with-dhcid), refuses to replace a name it doesn't own: a hook record blocks that client's
name until it is gone. (20260929: seed-wifitest-main was rejected, DHCP_DDNS_FORWARD_REPLACE_REJECTED.)
  list    every A record, and whether a DHCID sits beside it (Kea's) or not (the router hook's)
  purge   delete the A records without a DHCID (each printed): the hook's leftovers; Kea re-registers each
          client at its next renewal. Names only in the lan zone; the site's zone is never touched."""
import json, os, sys, urllib.parse, urllib.request
LAN = 'lan.seed.example.com'; PRIMARY = '192.168.1.15'

class Tech:
    def __init__(self, ip, pw):
        self.base = f'http://{ip}:5380/api/'
        self.tok = self.call('user/login', auth=False, user='admin', **{'pass': pw})['token']
    def call(self, path, auth=True, **p):
        req = urllib.request.Request(self.base + path, data=urllib.parse.urlencode(p).encode(), method='POST',
                                     headers={'Content-Type': 'application/x-www-form-urlencoded'})
        if auth: req.add_header('Authorization', f'Bearer {self.tok}')
        with urllib.request.urlopen(req, timeout=60) as r: j = json.load(r)
        if j.get('status') != 'ok': raise SystemExit(f'{path}: {j.get("status")}: {j.get("errorMessage")}')
        return j.get('response', j)

mode = sys.argv[1] if len(sys.argv) > 1 else 'list'
t = Tech(PRIMARY, os.environ['TECHNITIUM_PW_CORE'])
try:
    recs = t.call('zones/records/get', domain=LAN, zone=LAN, listZone='true')['records']
    a = [(r['name'], r['rData'].get('ipAddress'), r.get('ttl')) for r in recs if r['type'] == 'A']
    dhcid = {r['name'] for r in recs if r['type'] == 'DHCID'}
    hook = [(n, ip) for n, ip, _ in a if n not in dhcid]
    for n, ip, ttl in sorted(a): print(f'{n}\t{ip}\t{"kea (DHCID)" if n in dhcid else "router hook (no DHCID)"}')
    print(f'{len(a)} A records: {len(a) - len(hook)} Kea, {len(hook)} router hook')
    if mode == 'purge':
        for n, ip in hook:
            t.call('zones/records/delete', domain=n, zone=LAN, type='A', ipAddress=ip); print(f'deleted {n} A {ip}')
finally:
    t.call('user/logout')
