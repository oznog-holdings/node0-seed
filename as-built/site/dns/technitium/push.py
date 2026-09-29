#!/usr/bin/env python3
"""Technitium from the repository (rung 5 brief › B; R5.07, R5.09-R5.11). Run through ./push, which
fetches the admin passwords from the site vault into the environment (TECHNITIUM_PW_CORE,
TECHNITIUM_PW_INFRA) and never onto disk or argv.

The one list, site/dns/rewrites.yaml, becomes three zones on ns1 (core, the primary):
  seed.example.com            an A record per host and service; NS ns1, ns2; the lease subzone delegated
  lan.seed.example.com        the router's DHCP leases (written by the router, not here); NS ns1, ns2
  1.168.192.in-addr.arpa   a PTR per host (not per service); NS ns1, ns2
ns2 (infra) holds them as secondary zones, transferred from ns1 (AXFR/IXFR, TCP, allowed to ns2
only, NOTIFY to ns2).
Records are synced one by one: missing ones added, extra ones deleted by exact value. The API's
`ptr` flag is never used: it treats PTR as a replace, so deleting one record would delete the reverse
entry of every other record at that address (design › DNS). Reverse records are a zone of their own.

Usage: push [check]   (check: compare only, change nothing; exit 1 on any difference)
"""
import json, os, secrets, sys, urllib.parse, urllib.request
import yaml

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..'))
CHECK = sys.argv[1:] == ['check']
N = yaml.safe_load(open('site/dns/rewrites.yaml'))
ZONE, HOSTS, SERVICES = N['zone'], N['hosts'], N.get('services') or {}
LAN, REV = 'lan.' + ZONE, '1.168.192.in-addr.arpa'
NS = [f'ns1.{ZONE}', f'ns2.{ZONE}']
PRIMARY, SECONDARY = HOSTS['ns1'], HOSTS['ns2']
TTL = 300
BLOCKLISTS = [l.split()[0] for l in open('site/dns/technitium/blocklists') if l.strip() and not l.startswith('#')]
DDNS_USER = 'dhcp-router'
# rung 6: the firewall's Kea writes main-LAN leases into LAN by RFC 2136 with this TSIG key (vault item
# "technitium ddns firewall", passed by ./push as TECHNITIUM_TSIG_FW), from the firewall's addresses only
TSIG_NAME, TSIG_ALG = 'fw-ddns', 'hmac-sha256'
TSIG_SECRET = os.environ.get('TECHNITIUM_TSIG_FW', '')
FW_ADDRS = ['192.168.1.1']     # the firewall, the LAN gateway from the rung 6 cut-over (it was .2 beside the router in phase 2)
diffs = []


class Tech:
    def __init__(self, name, ip, pw):
        self.name, self.ip, self.base = name, ip, f'http://{ip}:5380/api/'
        r = self.call('user/login', auth=False, user='admin', pw=pw)
        self.tok = r['token']

    def call(self, path, auth=True, body=None, pw=None, **p):
        if pw is not None: p['pass'] = pw
        data = urllib.parse.urlencode(p).encode()
        req = urllib.request.Request(self.base + path, data=data, method='POST',
                                     headers={'Content-Type': 'application/x-www-form-urlencoded'})
        if auth: req.add_header('Authorization', f'Bearer {self.tok}')
        with urllib.request.urlopen(req, timeout=60) as r:
            j = json.load(r)
        if j.get('status') != 'ok':
            raise SystemExit(f'{self.name} {path}: {j.get("status")}: {j.get("errorMessage")}')
        return j.get('response', j)

    def logout(self):
        self.call('user/logout')


def say(msg): print(msg, flush=True)


def change(t, what, fn, *a, **k):
    """record a difference; in check mode stop there, otherwise apply it"""
    diffs.append(f'{t.name}: {what}')
    say(f'{t.name}: {"DIFFERS" if CHECK else "set"}: {what}')
    if not CHECK: return fn(*a, **k)


# --- settings -------------------------------------------------------------------------------------
def settings(t, role):
    ip = t.ip
    want = {
        'dnsServerDomain': f'{"ns1" if role == "primary" else "ns2"}.{ZONE}',
        'dnsServerLocalEndPoints': f'{ip}:53',
        # outbound DNS from its own address: core has two, and ns2 refused ns1's NOTIFY sent from .12 (20260929)
        'dnsServerIPv4SourceAddresses': ip,
        'webServiceLocalAddresses': f'{ip},127.0.0.1',
        'recursion': 'UseSpecifiedNetworkACL',
        'recursionNetworkACL': '127.0.0.1,192.168.1.0/24',
        # the same upstreams AdGuard had: Quad9 and Cloudflare over DoH (design › DNS; R1.25)
        'forwarders': 'https://dns.quad9.net/dns-query (9.9.9.9),https://cloudflare-dns.com/dns-query (1.1.1.1)',
        'forwarderProtocol': 'Https',
        'dnssecValidation': 'true',
        'enableBlocking': 'true',
        'blockingType': 'AnyAddress',
        'blockListUrls': ','.join(BLOCKLISTS),
        'blockListUpdateIntervalHours': '24',
        'logQueries': 'false',
        'dnsServerEnableCheckForUpdate': 'false',   # versions are pinned (site/core/pins, the template)
        'dnsAppsEnableAutomaticUpdate': 'false',
        'notifyAllowedNetworks': PRIMARY if role == 'secondary' else '',
    }
    have = t.call('settings/get')
    def norm(k, v):
        if isinstance(v, bool): return 'true' if v else 'false'
        if isinstance(v, list):
            if k == 'forwarders': return ','.join(v)
            return ','.join(str(x) for x in v)
        return '' if v is None else str(v)
    bad = {k: v for k, v in want.items() if norm(k, have.get(k)).replace(', ', ',') != v}
    for k in bad: change(t, f'setting {k}: {norm(k, have.get(k))!r} -> {bad[k]!r}', lambda: None)
    if bad and not CHECK: t.call('settings/set', **bad)
    # the TSIG key (primary only; the secret compared by hash, never printed)
    if role == 'primary' and TSIG_SECRET:
        import hashlib
        hv = lambda s: hashlib.sha256(s.encode()).hexdigest()
        haveK = [(k.get('keyName'), k.get('algorithmName'), hv(k.get('sharedSecret') or '')) for k in (have.get('tsigKeys') or [])]
        if haveK != [(TSIG_NAME, TSIG_ALG, hv(TSIG_SECRET))]:
            change(t, f'setting tsigKeys: {[k[:2] for k in haveK]} -> [({TSIG_NAME!r}, {TSIG_ALG!r})] (secret by hash)',
                   t.call, 'settings/set', tsigKeys=f'{TSIG_NAME}|{TSIG_SECRET}|{TSIG_ALG}')
    # never a second DHCP server on the LAN (R1.17): every Technitium DHCP scope disabled
    for s in t.call('dhcp/scopes/list')['scopes']:
        if s.get('enabled'):
            change(t, f'DHCP scope {s["name"]} enabled -> disabled', t.call, 'dhcp/scopes/disable', name=s['name'])
    say(f'{t.name}: settings checked ({len(want)} keys), DHCP scopes all disabled')


# --- zones on the primary -------------------------------------------------------------------------
def desired():
    a = {(f'{k}.{ZONE}', 'A', v) for k, v in HOSTS.items()}
    for k, h in SERVICES.items():
        if h not in HOSTS: raise SystemExit(f'service {k}: unknown host {h}')
        a.add((f'{k}.{ZONE}', 'A', HOSTS[h]))
    zone = a | {(ZONE, 'NS', n) for n in NS} | {(LAN, 'NS', n) for n in NS}
    rev = {(f'{v.split(".")[3]}.{REV}', 'PTR', f'{k}.{ZONE}') for k, v in HOSTS.items()} | {(REV, 'NS', n) for n in NS}
    lan = {(LAN, 'NS', n) for n in NS}
    return {ZONE: zone, REV: rev, LAN: lan}


def records(t, zone):
    r = t.call('zones/records/get', domain=zone, zone=zone, listZone='true')['records']
    out = set()
    for x in r:
        d = x['rData']
        v = {'A': d.get('ipAddress'), 'NS': d.get('nameServer'), 'PTR': d.get('ptrName')}.get(x['type'])
        if v is not None: out.add((x['name'], x['type'], v))
    return out


def add(t, zone, name, typ, v):
    p = {'A': {'ipAddress': v}, 'NS': {'nameServer': v}, 'PTR': {'ptrName': v}}[typ]
    t.call('zones/records/add', zone=zone, domain=name, type=typ, ttl=TTL, **p)   # never ptr=true


def delete(t, zone, name, typ, v):
    p = {'A': {'ipAddress': v}, 'NS': {'nameServer': v}, 'PTR': {'ptrName': v}}[typ]
    t.call('zones/records/delete', zone=zone, domain=name, type=typ, **p)          # by exact value


def primary(t):
    have_zones = {z['name']: z for z in t.call('zones/list')['zones']}
    for zone, want in desired().items():
        if zone not in have_zones:
            change(t, f'zone {zone}: create (Primary)', t.call, 'zones/create', zone=zone if zone != REV else '192.168.1.0/24', type='Primary')
        elif have_zones[zone]['type'] != 'Primary':
            raise SystemExit(f'{t.name}: zone {zone} is {have_zones[zone]["type"]}, not Primary: stopping')
        have = records(t, zone) if (zone in have_zones or not CHECK) else set()
        # the lease subzone: only its NS records are the repository's; its A records are the router's
        managed = have if zone != LAN else {r for r in have if r[1] == 'NS'}
        for r in sorted(want - managed): change(t, f'{zone}: add {r[0]} {r[1]} {r[2]}', add, t, zone, *r)
        for r in sorted(managed - want): change(t, f'{zone}: delete {r[0]} {r[1]} {r[2]}', delete, t, zone, *r)
        opts = t.call('zones/options/get', zone=zone) if zone in have_zones else {}
        wantopt = {'zoneTransfer': 'UseSpecifiedNetworkACL', 'notify': 'SpecifiedNameServers', 'update': 'Deny'}
        if zone == LAN and TSIG_SECRET:
            # dynamic updates from the firewall only, signed with its key, for lease names only (A, DHCID)
            wantopt['update'] = 'UseSpecifiedNetworkACL'
            pol = [{'tsigKeyName': TSIG_NAME, 'domain': f'*.{LAN}', 'allowedTypes': ['A', 'DHCID']}]
            haveacl = [str(x) for x in opts.get('updateNetworkACL') or []]
            havepol = [{'tsigKeyName': p.get('tsigKeyName'), 'domain': p.get('domain'), 'allowedTypes': sorted(p.get('allowedTypes') or [])} for p in opts.get('updateSecurityPolicies') or []]
            if opts.get('update') != wantopt['update'] or haveacl != FW_ADDRS or havepol != pol:
                change(t, f'{zone}: dynamic updates from {FW_ADDRS} with key {TSIG_NAME} for *.{LAN} A, DHCID only',
                       t.call, 'zones/options/set', zone=zone, update=wantopt['update'], updateNetworkACL=','.join(FW_ADDRS),
                       updateSecurityPolicies=f'{TSIG_NAME}|*.{LAN}|A,DHCID')
        acl = [str(x) for x in opts.get('zoneTransferNetworkACL') or []]
        nfy = [str(x) for x in opts.get('notifyNameServers') or []]
        if any(opts.get(k) != v for k, v in wantopt.items()) or acl != [SECONDARY] or nfy != [SECONDARY]:
            change(t, f'{zone}: options zone transfer to {SECONDARY} only, notify {SECONDARY}, dynamic updates: {wantopt["update"]}',
                   t.call, 'zones/options/set', zone=zone, zoneTransferNetworkACL=SECONDARY, notifyNameServers=SECONDARY, **wantopt)
    say(f'{t.name}: zones {ZONE}, {LAN}, {REV} checked (primary)')


def secondary(t):
    have_zones = {z['name']: z for z in t.call('zones/list')['zones']}
    for zone in (ZONE, LAN, REV):
        if zone not in have_zones:
            change(t, f'zone {zone}: create (Secondary of {PRIMARY})', t.call, 'zones/create', zone=zone,
                   type='Secondary', primaryNameServerAddresses=PRIMARY, zoneTransferProtocol='Tcp')
        elif have_zones[zone]['type'] != 'Secondary':
            raise SystemExit(f'{t.name}: zone {zone} is {have_zones[zone]["type"]}, not Secondary: stopping')
        else:
            opts = t.call('zones/options/get', zone=zone)
            if opts.get('zoneTransfer') != 'Deny' or opts.get('notify') != 'None':
                change(t, f'{zone}: options no zone transfer, no notify', t.call, 'zones/options/set', zone=zone, zoneTransfer='Deny', notify='None')
    say(f'{t.name}: zones {ZONE}, {LAN}, {REV} checked (secondary of {PRIMARY})')


# --- the router's credential: may modify the lease subzone and nothing else ------------------------
def ddns_user(t):
    """rung 6 (the cut-over, 20260929): the router's lease hook is retired, Kea on the firewall registers leases
    (TSIG fw-ddns). The router's user stays as a record but is revoked: disabled, its API token sessions deleted,
    no permission on any zone. (Deleting the user, or its vault item, is the owner's call.)"""
    users = {u['username'] for u in t.call('admin/users/list')['users']}
    if DDNS_USER not in users:
        say(f'{t.name}: {DDNS_USER}: absent'); return
    u = t.call('admin/users/get', user=DDNS_USER)
    if not u.get('disabled'):
        change(t, f'user {DDNS_USER}: disable (revoked at the rung 6 cut-over)', t.call, 'admin/users/set', user=DDNS_USER, disabled='true')
    if u.get('memberOfGroups'):
        change(t, f'user {DDNS_USER}: groups {u["memberOfGroups"]} -> none', t.call, 'admin/users/set', user=DDNS_USER, memberOfGroups='')
    for s in t.call('admin/sessions/list')['sessions']:
        if s.get('username') == DDNS_USER:
            change(t, f'user {DDNS_USER}: delete its {s.get("type")} session "{s.get("tokenName")}" (the token revoked)',
                   t.call, 'admin/sessions/delete', partialToken=s['partialToken'])
    p = t.call('zones/permissions/get', zone=LAN)
    up = {x['username']: x for x in p.get('userPermissions', [])}
    if DDNS_USER in up:
        rows = [f'{n}|{str(x["canView"]).lower()}|{str(x["canModify"]).lower()}|{str(x["canDelete"]).lower()}' for n, x in up.items() if n != DDNS_USER]
        grows = [f'{x["name"]}|{str(x["canView"]).lower()}|{str(x["canModify"]).lower()}|{str(x["canDelete"]).lower()}' for x in p.get('groupPermissions', [])]
        change(t, f'{LAN}: {DDNS_USER}: no permission', t.call, 'zones/permissions/set', zone=LAN,
               userPermissions='|'.join(rows), groupPermissions='|'.join(grows))
    say(f'{t.name}: {DDNS_USER}: revoked (disabled, no token session, no zone permission)')


def main():
    core = Tech('ns1 (core)', PRIMARY, os.environ['TECHNITIUM_PW_CORE'])
    infra = Tech('ns2 (infra)', SECONDARY, os.environ['TECHNITIUM_PW_INFRA'])
    try:
        settings(core, 'primary'); settings(infra, 'secondary')
        primary(core); ddns_user(core); secondary(infra)
        if not CHECK:
            for z in (ZONE, LAN, REV): infra.call('zones/resync', zone=z)
    finally:
        core.logout(); infra.logout()
    say(f'{"check" if CHECK else "push"}: {len(diffs)} difference(s)' + (' (applied)' if diffs and not CHECK else ''))
    sys.exit(1 if CHECK and diffs else 0)


main()
