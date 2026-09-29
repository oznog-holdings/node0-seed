#!/usr/bin/env bash
# wifi-test.sh: the tests of the router's three wifi networks (R1.24), with Larkbox one as the client
# (nixos@192.168.1.128, its wifi in network namespace "wtest" by site/router/wifi-client.sh; its wired
# link is checked before and after every network). Joins each network in turn, WPA3-SAE (IoT also once
# with WPA2-PSK: the mixed mode), and checks what it must reach and what it must not. The LAN side
# (LAN -> IoT allowed, LAN -> guest not) is tested from the agent box, on the LAN. The passphrases go
# vault -> ssh stdin; never printed. Prints one line per check: network, check, expected, result, ok/FAIL.
set -uo pipefail; shopt -s extglob
cd "$(dirname "$0")/.."
LB=nixos@192.168.1.128
SSH="ssh -o BatchMode=yes -o LogLevel=ERROR"
L="$SSH $LB sudo /run/wifi-client.sh"
fails=0
psk() { ( . tools/vault-env.sh; BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null </dev/null); export BW_SESSION; unset BW_PASSWORD BW_CLIENTSECRET
  N="$1" bw list items --search "$1" | N="$1" jq -r '[.[]|select(.name==env.N)] | if length==1 then .[0].login.password else error("missing") end'; bw lock >/dev/null ); }
row() {  # network check expected result
  local ok=FAIL pat=$3; [[ $pat == *'|'* ]] && pat="@($pat)"; [[ $4 == $pat ]] && ok=ok; [ $ok = ok ] || fails=$((fails+1))
  printf '%-6s | %-52s | %-18s | %-26s | %s\n' "$1" "$2" "$3" "$4" "$ok"; }
wired() { local r; r=$(ping -c 2 -W 1 192.168.1.128 >/dev/null 2>&1 && echo up || echo DOWN); row "$1" "Larkbox one's wired link (192.168.1.128), from the agent box" up "$r"; }
cat site/router/wifi-client.sh | $SSH $LB 'sudo install -m 0700 /dev/stdin /run/wifi-client.sh'
$L setup >/dev/null; $L leave wlp0s20f3 >/dev/null
echo "$(date -u +%FT%TZ) wifi tests; router $(ssh -o BatchMode=yes -o LogLevel=ERROR root@192.168.1.1 'iwinfo | grep -c ESSID') access points up"
printf '%-6s | %-52s | %-18s | %-26s | %s\n' net check expected result ""
# targets nobody on wifi may reach (the upstream's containment; the router rejects them for guest and IoT)
OUTSIDE="${OUTSIDE:?set OUTSIDE to the home-network and tailnet hosts the wifi must not reach, as addr:port:label, space-separated}"
LAN="192.168.1.1:22:router-LAN-ssh 192.168.1.1:443:router-LAN-web 192.168.1.10:443:infra 192.168.1.11:22:agent 192.168.1.12:53:core 192.0.2.1:53:upstream-gateway"
run_net() {  # net ssid item mode gwexpect dnsexpect
  local net=$1 ssid=$2 item=$3 mode=$4 gwx=$5 dnsx=$6 j a gw dns
  wired "$net"
  j=$(psk "$item" | $L join "$ssid" wlp0s20f3 "$mode")
  row "$net" "associate $ssid ($mode)" "key_mgmt=$([ $mode = SAE ] && echo SAE || echo WPA2-PSK)" "$(grep -o 'key_mgmt=[A-Z-]*' <<<"$j")"
  row "$net" "  on 5 GHz, CCMP, completed" "5180 CCMP COMPLETED" "$(sed -E 's/.*freq=([0-9]+).*pairwise_cipher=([A-Z]+).*wpa_state=([A-Z]+).*/\1 \2 \3/' <<<"$(head -1 <<<"$j")")"
  a=$(sed -n 's/^dhcp: address \([^,]*\),.*/\1/p' <<<"$j"); gw=$(sed -n 's/.*router \([^,]*\),.*/\1/p' <<<"$j"); dns=$(sed -n 's/.*dns \([^,]*\),.*/\1/p' <<<"$j")
  row "$net" "DHCP: an address" "$gwx*" "${a:-none}"
  row "$net" "DHCP: router" "$gwx.1" "${gw:-none}"
  row "$net" "DHCP: DNS server(s)" "$dnsx" "${dns:-none}"
  row "$net" "DNS: example.com via ${dns%% *}" "NOERROR *" "$($L dns "${dns%% *}" example.com)"
  row "$net" "internet: https://example.com" "200" "$($L https https://example.com)"
  if [ $net = main ]; then
    row "$net" "site name: vault.seed.example.com via ${dns%% *}" "NOERROR 192.168.1.10*" "$($L dns "${dns%% *}" vault.seed.example.com)"
    row "$net" "site: https://vault.seed.example.com" "200" "$($L https https://vault.seed.example.com/alive)"
    row "$net" "LAN: infra 192.168.1.10:443" open "$($L probe 192.168.1.10 443)"
    row "$net" "LAN: agent 192.168.1.11:22" open "$($L probe 192.168.1.11 22)"
  else
    local me=$gwx.1
    row "$net" "site name: vault.seed.example.com via $me" "NXDOMAIN" "$($L dns $me vault.seed.example.com)"
    row "$net" "site name via the router's LAN dnsmasq 192.168.1.1" "no answer" "$($L dns 192.168.1.1 vault.seed.example.com)"
    row "$net" "site name via the router's WAN address 192.0.2.4" "no answer" "$($L dns 192.0.2.4 vault.seed.example.com)"
    for p in 22 80 443; do row "$net" "router's own address $me:$p" refused "$($L probe $me $p)"; done
    for t in $LAN; do IFS=: read -r h p n <<<"$t"; row "$net" "LAN/upstream: $n $h:$p" "refused|unreachable" "$($L probe $h $p)"; done
    local other=$([ $net = guest ] && echo 192.168.30.1 || echo 192.168.20.1)
    row "$net" "the other segment's router address $other:53" "refused|unreachable" "$($L probe $other 53)"
    $L listen 8080 >/dev/null
    local lan_r; lan_r=$(timeout 5 bash -c "exec 3<>/dev/tcp/${a%/*}/8080" 2>/dev/null && echo open || echo "not open ($?)")
    row "$net" "from the LAN (agent box) to this client ${a%/*}:8080" "$([ $net = iot ] && echo open || echo 'not open*')" "$lan_r"
    $L unlisten >/dev/null
  fi
  for t in $OUTSIDE; do IFS=: read -r h p n <<<"$t"; row "$net" "outside: $n $h:$p" "refused|unreachable|timeout" "$($L probe $h $p)"; done
  $L leave wlp0s20f3 >/dev/null
  wired "$net"
}
run_net main  seed       'wifi seed'       SAE 192.168.1   '192.168.1.12 192.168.1.10'
run_net guest seed-guest 'wifi seed-guest' SAE 192.168.20  '192.168.20.1'
run_net iot   seed-iot   'wifi seed-iot'   SAE 192.168.30  '192.168.30.1'
# the mixed mode: an IoT device that only speaks WPA2
wired iot; j=$(psk 'wifi seed-iot' | $L join seed-iot wlp0s20f3 PSK)
row iot "associate seed-iot (WPA2-PSK, as a WPA2-only device)" "key_mgmt=WPA2-PSK" "$(grep -o 'key_mgmt=[A-Z0-9-]*' <<<"$j")"
row iot "  internet: https://example.com" 200 "$($L https https://example.com)"
$L leave wlp0s20f3 >/dev/null
# clients isolated from each other: the access point's side (one test card can't be two stations: its
# driver allows one managed interface, and wpa_supplicant turns a P2P-client interface into one)
iso=$(ssh -o BatchMode=yes -o LogLevel=ERROR root@192.168.1.1 'c=/var/run/hostapd-phy1.conf; for i in 0 1 2; do printf "%s:%s:%s:%s " phy1-ap$i $(awk -v n=$((i+1)) "/^ap_isolate=/{k++; if(k==n) print substr(\$0,12)}" $c) $(cat /sys/class/net/phy1-ap$i/brport/hairpin_mode) $(ls /sys/class/net/$(basename $(readlink /sys/class/net/phy1-ap$i/master))/brif | wc -l); done')
for t in $iso; do IFS=: read -r i ai hp np <<<"$t"; n=$(case $i in phy1-ap0) echo main;; phy1-ap1) echo guest;; *) echo iot;; esac)
  exp=$([ $n = main ] && echo "ap_isolate 1, hairpin 1" || echo "ap_isolate 1, hairpin 0, 1 port")
  res=$([ $n = main ] && echo "ap_isolate $ai, hairpin $hp" || echo "ap_isolate $ai, hairpin $hp, $np port$([ "$np" = 1 ] || echo s)")
  row $n "peers: AP isolation and bridge hairpin ($i)" "$exp" "$res"; done
$L teardown
wired end
echo "$(date -u +%FT%TZ) done: $fails failed"
exit $((fails > 0))
