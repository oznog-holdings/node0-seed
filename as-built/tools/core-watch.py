#!/usr/bin/env python3
"""core-watch.py [seconds]: every second, ask core (192.168.1.12) for DNS (infra.seed.example.com must
be 192.168.1.10) and NTP (a server reply with stratum 1-15), and print every change of state with its
UTC time, plus a line every 30 s. At the end: the first and last failure of each, and the longest
outage. Standard library only. Written for core's move onto its SSD (site/core/ssd/README.md)."""
import socket, struct, sys, time, datetime

HOST, NAME, WANT = '192.168.1.12', 'infra.seed.example.com', '192.168.1.10'
DNS_HOST = '192.168.1.15'   # DNS on core is Technitium ns1 from rung 5 › F (20260929); NTP stays on .12

def dns():
    q = struct.pack('>HHHHHH', 0x5eed, 0x0100, 1, 0, 0, 0) + b''.join(
        bytes([len(p)]) + p.encode() for p in NAME.split('.')) + b'\0' + struct.pack('>HH', 1, 1)
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(0.8)
    try:
        s.sendto(q, (DNS_HOST, 53)); r = s.recv(512)
        return r[-4:] == socket.inet_aton(WANT) and (r[3] & 0x0f) == 0
    except OSError:
        return False
    finally:
        s.close()

def ntp():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(0.8)
    try:
        s.sendto(b'\x23' + 47 * b'\0', (HOST, 123)); r = s.recv(48)
        return len(r) >= 48 and 1 <= r[1] <= 15 and (r[0] >> 6) != 3   # stratum set, leap not "unsynchronised"
    except OSError:
        return False
    finally:
        s.close()

def now():
    return datetime.datetime.now(datetime.timezone.utc)

dur = int(sys.argv[1]) if len(sys.argv) > 1 else 900
state = {}; fails = {'dns': [], 'ntp': []}; down_since = {}; longest = {'dns': 0.0, 'ntp': 0.0}
end = time.time() + dur; last_beat = 0
while time.time() < end:
    t = now(); cur = {'dns': dns(), 'ntp': ntp()}
    for k, ok in cur.items():
        if not ok:
            fails[k].append(t)
        if state.get(k) != ok:
            print(f"{t:%H:%M:%S.%f}"[:-3], k, 'UP' if ok else 'DOWN', flush=True)
            if not ok:
                down_since[k] = t
            elif k in down_since:
                longest[k] = max(longest[k], (t - down_since.pop(k)).total_seconds())
        state[k] = ok
    if time.time() - last_beat >= 30:
        print(f"{t:%H:%M:%S}", 'beat', ' '.join(f"{k}={'ok' if v else 'FAIL'}" for k, v in cur.items()), flush=True)
        last_beat = time.time()
    time.sleep(max(0, 1 - (now() - t).total_seconds()))
for k in fails:
    if fails[k]:
        print(f"{k}: first failure {fails[k][0]:%H:%M:%S}, last {fails[k][-1]:%H:%M:%S}, {len(fails[k])} failed seconds, "
              f"longest outage {longest[k] or (fails[k][-1] - fails[k][0]).total_seconds():.0f} s", flush=True)
    else:
        print(f"{k}: no failure", flush=True)
