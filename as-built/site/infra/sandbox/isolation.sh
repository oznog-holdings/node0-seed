#!/bin/bash
# The sandbox's isolation, enforced on infra and never inside the sandbox (design › Operating: "no
# production secrets, no route to production data (isolated, NAT out, nothing in)"; R1.94).
# Traffic entering infra from libvirt's NAT network (virbr0, 192.168.122.0/24) is filtered in
# mangle PREROUTING: libvirt and Docker manage filter/nat and re-insert their own rules there;
# nobody else touches this chain, and here the forge's address is still pre-DNAT.
#   allowed: DHCP and DNS from libvirt's dnsmasq; the forge's git port (a read-only deploy key);
#            the internet through libvirt's NAT
#   dropped: infra itself (every local address), the LAN and every private, CGNAT (tailnet) and
#            link-local range
# "Nothing in" is libvirt's NAT: the LAN has no route to 192.168.122.0/24.
# Idempotent. Run at array start by User Scripts (sandbox-isolation) and before starting the VM.
set -euo pipefail
T="iptables -t mangle"; C=SEED-SANDBOX
$T -N $C 2>/dev/null || $T -F $C
# replies to connections already allowed (infra's own ssh to the sandbox, the sandbox's own NAT'd
# traffic); every NEW connection from the sandbox meets the rules below
$T -A $C -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
$T -A $C -p udp --dport 67 -j RETURN
$T -A $C -d 192.168.122.1 -p udp --dport 53 -j RETURN
$T -A $C -d 192.168.122.1 -p tcp --dport 53 -j RETURN
$T -A $C -d 192.168.1.10 -p tcp --dport 2222 -j RETURN          # the forge: git over ssh only
$T -A $C -m addrtype --dst-type LOCAL -j DROP                    # infra itself, every address
for net in 192.168.0.0/16 172.16.0.0/12 10.0.0.0/8 100.64.0.0/10 169.254.0.0/16; do $T -A $C -d $net -j DROP; done
$T -A $C -j RETURN
$T -C PREROUTING -i virbr0 -j $C 2>/dev/null || $T -I PREROUTING 1 -i virbr0 -j $C
echo "sandbox isolation: $($T -S $C | grep -c -- '-A') rules, hooked: $($T -S PREROUTING | grep -c -- "-j $C")"
