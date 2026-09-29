#!/usr/bin/env python3
"""Send one DHCPDISCOVER on the LAN and list every OFFER heard for 6 s (R1.17: exactly one DHCP
server; R1.25: the DNS servers a fresh lease would get). Uses a locally administered MAC, so it
matches no real host, and never sends a REQUEST: no lease is taken. Offers are read with a raw
AF_PACKET socket, so a host firewall on the sender doesn't hide them. Run as root on a LAN host.
  dhcp-discover.py <interface>"""
import os, socket, struct, sys, time, random
ifname = sys.argv[1]
mac = bytes([0x02, 0x5e, 0xed] + [random.randint(0, 255) for _ in range(3)])
xid = random.getrandbits(32)
pkt = struct.pack('!BBBBIHHIIII16s64s128sI', 1, 1, 6, 0, xid, 0, 0x8000, 0, 0, 0, 0,
                  mac.ljust(16, b'\0'), b'', b'', 0x63825363)
pkt += bytes([53, 1, 1, 55, 4, 1, 3, 6, 15, 255])
raw = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.ntohs(0x0800)); raw.bind((ifname, 0)); raw.settimeout(0.5)
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
s.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, ifname.encode()); s.bind(('0.0.0.0', 68))
s.sendto(pkt, ('255.255.255.255', 67))
print(f"DISCOVER sent on {ifname}, chaddr {mac.hex(':')}, xid {xid:08x}")
offers = {}
end = time.time() + 6
while time.time() < end:
    try: f = raw.recv(2048)
    except socket.timeout: continue
    ihl = (f[14] & 0x0f) * 4; ip = f[14:]; 
    if ip[9] != 17: continue
    udp = ip[ihl:]; sport, dport = struct.unpack('!HH', udp[:4])
    if sport != 67 or dport != 68: continue
    b = udp[8:]
    if len(b) < 240 or struct.unpack('!I', b[4:8])[0] != xid: continue
    yiaddr = socket.inet_ntoa(b[16:20]); src = socket.inet_ntoa(ip[12:16]); opts = {}; i = 240
    while i < len(b) and b[i] != 255:
        if b[i] == 0: i += 1; continue
        opts[b[i]] = b[i+2:i+2+b[i+1]]; i += 2 + b[i+1]
    if opts.get(53) != b'\x02': continue
    dns = [socket.inet_ntoa(opts[6][j:j+4]) for j in range(0, len(opts.get(6, b'')), 4)]
    offers[src] = (f[6:12].hex(':'), yiaddr, dns, socket.inet_ntoa(opts.get(3, b'\0\0\0\0')[:4]), opts.get(15, b'').decode())
for src, (smac, y, dns, gw, dom) in offers.items():
    print(f"OFFER from {src} ({smac}): address {y}, router {gw}, DNS {', '.join(dns)}, domain {dom}")
print(f"{len(offers)} DHCP server(s) answered")
