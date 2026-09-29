#!/usr/bin/env bash
# wifi-client.sh: the wifi test client's side of tools/wifi-test.sh (R1.24), run as root on Larkbox one
# (a live installer). The wifi phy lives in its own network namespace "wtest", so the wired link (enp2s0,
# how we reach the box) is never touched: no route, address or resolver of the main namespace changes.
# The passphrase comes on stdin into a 0600 file in /run, removed once associated; never argv.
#   setup                        unmanage the wifi in NetworkManager, move phy0 into netns wtest
#   join <ssid> <ifc> SAE|PSK    associate (WPA3-SAE with PMF required, or WPA2-PSK), then DHCP
#   vif  <ifc>                   add a second station interface (P2P-client type) with its own MAC
#   leave <ifc>                  disconnect, release DHCP
#   probe <host> <port>          tcp connect from the netns: open | refused | unreachable | timeout
#   dns <server> <name>          A records from that server (dig), or NXDOMAIN / SERVFAIL / none
#   https <url>                  HTTP status over the netns (resolver: the DHCP-given server)
#   arp <ifc> <ip>               ARP replies for <ip> heard on <ifc> (3 requests)
#   listen <port> | unlisten     a tcp listener in the netns (for LAN -> IoT / guest tests)
#   teardown                     stop everything, phy0 back to the main namespace, NetworkManager as before
set -uo pipefail
S=/nix/store
IW=$S/aka3355fd0b3v2yvzscfllzwbb9x7iz6-iw-6.17/bin/iw
WPA=$S/fd13lxasxs0bp254g0d48lfl4drlg0ks-wpa_supplicant-2.11/bin
DH=$S/ny0v3a34im8cdnpbvqnixcrvs3gvvqin-dhcpcd-10.3.1/bin/dhcpcd
ARPING=$S/mm9yc80ddn249ibx1bplf9dmzjl41q9d-arping-2.28/bin/arping
DIG=$S/zydwr4dxgqw80l9avcaa931sazi0fg4x-bind-9.20.26-dnsutils/bin/dig
CURL=$S/wdlfs81fkmdra741vj4gq9i5p1hb273z-curl-8.21.0-bin/bin/curl
NC=$S/9ay0dwp7wxslhlx392j4zvp302vvfypa-netcat-openbsd-1.234-2/bin/nc
N="ip netns exec wtest"; W=/run/wtest; umask 077; mkdir -p $W
cmd=$1; shift
case $cmd in
setup)
  nmcli device set wlp0s20f3 managed no 2>/dev/null
  ip netns list | grep -qw wtest || ip netns add wtest
  $N ip link show wlp0s20f3 >/dev/null 2>&1 || $IW phy phy0 set netns name wtest
  $N ip link set lo up; echo "wtest: $($N ip -br link | awk '{print $1}' | tr '\n' ' ')" ;;
join)
  ssid=$1; ifc=$2; mode=$3; read -r psk; [ -n "$psk" ] || { echo "no passphrase on stdin"; exit 1; }
  $N ip link set $ifc up
  if [ "$mode" = SAE ]; then km='key_mgmt=SAE\n ieee80211w=2\n sae_password="%s"'; else km='key_mgmt=WPA-PSK\n ieee80211w=0\n psk="%s"'; fi
  printf "ctrl_interface=$W/ctrl-$ifc\nnetwork={\n ssid=\"%s\"\n scan_freq=5180\n $km\n}\n" "$ssid" "$psk" > $W/$ifc.conf; unset psk
  $N $WPA/wpa_supplicant -B -i $ifc -c $W/$ifc.conf -P $W/$ifc.wpa.pid -f $W/$ifc.wpa.log
  for i in $(seq 1 40); do st=$($N $WPA/wpa_cli -s $W -p $W/ctrl-$ifc -i $ifc status 2>/dev/null); grep -q '^wpa_state=COMPLETED' <<<"$st" && break; sleep 1; done
  shred -u $W/$ifc.conf
  echo "$st" | grep -E '^(ssid|bssid|freq|key_mgmt|pairwise_cipher|pmf|wpa_state)=' | tr '\n' ' '; echo
  grep -q '^wpa_state=COMPLETED' <<<"$st" || { echo "not associated"; exit 1; }
  printf '#!/bin/sh\n[ -n "$new_ip_address" ] && echo "$new_ip_address|$new_routers|$new_domain_name_servers|$new_dhcp_lease_time" > %s/$interface.lease\n' $W > $W/hook.sh; chmod 700 $W/hook.sh
  $N $DH -4 -1 -o domain_name_servers -c $W/hook.sh --noipv4ll --nobackground -t 30 $ifc >$W/$ifc.dh.log 2>&1 &
  echo $! > $W/$ifc.dh.pid
  for i in $(seq 1 30); do a=$($N ip -4 -o addr show $ifc | awk '{print $4}'); [ -n "$a" ] && break; sleep 1; done
  sleep 1; IFS='|' read -r _ gw dns lt < $W/$ifc.lease 2>/dev/null
  echo "dhcp: address ${a:-none}, router ${gw:-?}, dns ${dns:-?}, lease ${lt:-?}s"
  mkdir -p /etc/netns/wtest; printf 'nameserver %s\n' ${dns%% *} > /etc/netns/wtest/resolv.conf ;;
vif)
  ifc=$1; $N $IW phy phy0 interface add $ifc type __p2pcl 2>&1 || $N $IW phy phy0 interface add $ifc type managed 2>&1
  $N ip link set $ifc address 02:00:00:00:00:01; echo "$ifc: $($N $IW dev $ifc info | grep -E 'type' | xargs)" ;;
leave)
  ifc=$1; [ -f $W/$ifc.dh.pid ] && kill $(cat $W/$ifc.dh.pid) 2>/dev/null; pkill -f "dhcpcd.* $ifc\$" 2>/dev/null
  [ -f $W/$ifc.wpa.pid ] && kill $(cat $W/$ifc.wpa.pid) 2>/dev/null; sleep 2
  $N ip -4 addr flush dev $ifc 2>/dev/null; rm -f $W/$ifc.*; echo "$ifc: left" ;;
probe)
  out=$($N $NC -z -v -w 4 "$1" "$2" 2>&1); rc=$?
  if [ $rc = 0 ]; then r=open; elif grep -qi refused <<<"$out"; then r=refused; elif grep -qi -E "unreachable|no route|prohibited" <<<"$out"; then r=unreachable; else r=timeout; fi
  echo "$r" ;;
dns)
  out=$($N $DIG +time=3 +tries=1 @"$1" "$2" A 2>&1)
  st=$(sed -n 's/.*status: \([A-Z]*\).*/\1/p' <<<"$out"); ans=$(sed -n '/ANSWER SECTION/,/^$/p' <<<"$out" | awk '$4=="A"{print $5}' | sort | tr '\n' ' ')
  echo "${st:-no answer}${ans:+ $ans}" ;;
https)
  $N $CURL -s -o /dev/null -w '%{http_code}\n' --max-time 12 "$1" || echo "failed" ;;
arp)
  n=$($N $ARPING -c 3 -w 6 -I "$1" "$2" 2>/dev/null | grep -c -i "bytes from\|reply"); echo "$n replies" ;;
listen)
  $N $NC -lk "$1" >/dev/null 2>&1 & echo $! > $W/listen.pid; sleep 1; echo "listening on $1" ;;
unlisten)
  [ -f $W/listen.pid ] && kill $(cat $W/listen.pid) 2>/dev/null; rm -f $W/listen.pid; echo "listener stopped" ;;
teardown)
  for p in $W/*.pid; do [ -f "$p" ] && kill $(cat "$p") 2>/dev/null; done; pkill -f "$DH" 2>/dev/null; pkill -f "$WPA/wpa_supplicant" 2>/dev/null; sleep 2
  $N $IW dev wl2 del 2>/dev/null
  $N $IW phy phy0 set netns 1 2>/dev/null; ip netns del wtest 2>/dev/null; rm -rf /etc/netns/wtest $W; rm -f /var/lib/dhcpcd/wl*-seed*.lease
  nmcli device set wlp0s20f3 managed yes 2>/dev/null
  echo "teardown: wifi back in the main namespace: $(ip -br link show wlp0s20f3 | awk '{print $1, $2}'); netns: $(ip netns list | wc -l)" ;;
esac
