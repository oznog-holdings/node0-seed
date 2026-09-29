#!/usr/bin/env python3
"""Ask an NTP server for the time every N seconds until an absolute end time, one line per answer:
stratum, leap, reference ID, and its offset from this box's own (chrony-synced) clock. For the core
cold-boot test (R1.33, R3.02, F-PI-RTC): does core offer time before it has synced (stratum 10 from
its local clock would be the failure), and how long until it serves synced time again.
  ntp-watch.py SERVER INTERVAL_S END_ISO_UTC >> log      (stops by itself at END)"""
import socket, struct, sys, time, datetime
srv, step, end = sys.argv[1], float(sys.argv[2]), datetime.datetime.fromisoformat(sys.argv[3].replace('Z', '+00:00')).timestamp()
E = 2208988800
while time.time() < end:
    now = datetime.datetime.now(datetime.timezone.utc).strftime('%FT%TZ')
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(2)
    t1 = time.time()
    try:
        s.sendto(b'\x23' + 47 * b'\0', (srv, 123)); d, _ = s.recvfrom(64); t4 = time.time()
        li = d[0] >> 6; st = d[1]; ref = d[12:16]
        refs = socket.inet_ntoa(ref) if st > 1 else ref.decode('ascii', 'replace').strip('\0')
        rx = struct.unpack('!II', d[32:40]); tx = struct.unpack('!II', d[40:48])
        t2 = rx[0] - E + rx[1] / 2**32; t3 = tx[0] - E + tx[1] / 2**32
        off = ((t2 - t1) + (t3 - t4)) / 2
        print(f"{now} answer stratum {st} leap {li} ref {refs} offset {off*1000:+.1f} ms", flush=True)
    except OSError as e:
        print(f"{now} no answer ({e.__class__.__name__})", flush=True)
    s.close(); time.sleep(step)
print(f"{datetime.datetime.now(datetime.timezone.utc):%FT%TZ} watch ended (end time reached)", flush=True)
