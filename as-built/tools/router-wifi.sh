#!/usr/bin/env bash
# router-wifi.sh: the router's three wifi networks (R1.24; the owner's decision of 20260927), all on the
# 5 GHz radio (radio1), WPA2/WPA3 mixed (sae-mixed, management frame protection optional):
#   seed        main: bridged into the LAN (br-lan), the LAN's DHCP (option 6: Technitium ns1, ns2 from rung 5) and site names
#   seed-guest  guest: 192.168.20.0/24 (br-guest, wifi only), internet only, clients isolated
#   seed-iot    IoT: 192.168.30.0/24 (br-iot, wifi only), internet; the LAN may open connections into it,
#               it may open none into the LAN; clients isolated
# Guest and IoT get the router's DHCP and DNS (DNS only at their own segment's router address: the main
# dnsmasq, on 192.168.1.1 and the WAN address, forwards the site's zone to the site's DNS) from a second dnsmasq ("wifi") that forwards only to the
# WAN's resolver: no site names, no forwarding to the site's DNS, private answers dropped (rebind protection).
# From rung 5 the router's configuration is applied from site/router/config by site/router/config-tool; this
# script is the record of how the wifi networks were first built, and config-tool's files are the source.
# They leave through the WAN (masqueraded like the LAN, so the upstream containment applies) and are
# rejected, at the router, for every private, link-local and tailnet (CGNAT) address beyond it.
# Every section is named (seed-owned: wifi_*, br_guest/br_iot, guest/iot, zone_*, fwd_*, seed_wifi_*),
# and appended after everything else: the "fixture:" rules are never touched or reordered.
# The passphrases: site vault items "wifi seed", "wifi seed-guest", "wifi seed-iot"; they go vault -> jq
# -> ssh's stdin -> uci on the router; never argv, never printed.
#   stage    write the configuration into uci's staging area (nothing live); shows the pending changes
#   apply    stage, commit, and reload network, dnsmasq, firewall and wifi (radios left as they are)
#   on|off   switch radio1 on or off; the configuration stays
#   status   radios, the running access points, the seed sections (no passphrase)
set -euo pipefail
R="ssh -o BatchMode=yes -o LogLevel=ERROR root@192.168.1.1"
case ${1:-status} in
stage|apply)
  $R 'uci -q batch' <<'EOF'
set network.br_guest=device
set network.br_guest.type='bridge'
set network.br_guest.name='br-guest'
set network.br_guest.bridge_empty='1'
set network.guest=interface
set network.guest.device='br-guest'
set network.guest.proto='static'
set network.guest.ipaddr='192.168.20.1'
set network.guest.netmask='255.255.255.0'
set network.br_iot=device
set network.br_iot.type='bridge'
set network.br_iot.name='br-iot'
set network.br_iot.bridge_empty='1'
set network.iot=interface
set network.iot.device='br-iot'
set network.iot.proto='static'
set network.iot.ipaddr='192.168.30.1'
set network.iot.netmask='255.255.255.0'
delete wireless.default_radio0
delete wireless.default_radio1
set wireless.radio0.country='US'
set wireless.radio1.country='US'
set wireless.wifi_main=wifi-iface
set wireless.wifi_main.device='radio1'
set wireless.wifi_main.mode='ap'
set wireless.wifi_main.network='lan'
set wireless.wifi_main.ssid='seed'
set wireless.wifi_main.encryption='sae-mixed'
set wireless.wifi_main.ieee80211w='1'
set wireless.wifi_guest=wifi-iface
set wireless.wifi_guest.device='radio1'
set wireless.wifi_guest.mode='ap'
set wireless.wifi_guest.network='guest'
set wireless.wifi_guest.ssid='seed-guest'
set wireless.wifi_guest.encryption='sae-mixed'
set wireless.wifi_guest.ieee80211w='1'
set wireless.wifi_guest.isolate='1'
set wireless.wifi_iot=wifi-iface
set wireless.wifi_iot.device='radio1'
set wireless.wifi_iot.mode='ap'
set wireless.wifi_iot.network='iot'
set wireless.wifi_iot.ssid='seed-iot'
set wireless.wifi_iot.encryption='sae-mixed'
set wireless.wifi_iot.ieee80211w='1'
set wireless.wifi_iot.isolate='1'
EOF
  # the passphrases, one per line on stdin, straight into uci
  ( . "${SEED_REPO:-/work/agent/seed-lab}/tools/vault-env.sh"
    BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null </dev/null); export BW_SESSION; unset BW_PASSWORD BW_CLIENTSECRET
    items=$(bw list items --search 'wifi seed'); bw lock >/dev/null
    for n in 'wifi seed' 'wifi seed-guest' 'wifi seed-iot'; do
      N="$n" jq -er '[.[] | select(.name==env.N)] | if length==1 then .[0].login.password else error("missing or not unique: " + env.N) end' <<<"$items"
    done ) | $R 'read -r m; read -r g; read -r i; [ -n "$m" ] && [ -n "$g" ] && [ -n "$i" ] || exit 1
      uci set wireless.wifi_main.key="$m"; uci set wireless.wifi_guest.key="$g"; uci set wireless.wifi_iot.key="$i"; echo "passphrases set: 3"'
  $R 'uci -q batch' <<'EOF'
rename dhcp.@dnsmasq[0]='main'
del_list dhcp.main.notinterface='guest'
del_list dhcp.main.notinterface='iot'
add_list dhcp.main.notinterface='guest'
add_list dhcp.main.notinterface='iot'
set dhcp.lan.instance='main'
set dhcp.@domain[0].instance='main'
set dhcp.wifi=dnsmasq
set dhcp.wifi.domainneeded='1'
set dhcp.wifi.boguspriv='1'
set dhcp.wifi.rebind_protection='1'
set dhcp.wifi.rebind_localhost='1'
set dhcp.wifi.authoritative='1'
set dhcp.wifi.nonwildcard='1'
set dhcp.wifi.localservice='1'
set dhcp.wifi.cachesize='1000'
set dhcp.wifi.ednspacket_max='1232'
set dhcp.wifi.leasefile='/tmp/dhcp.leases.wifi'
set dhcp.wifi.resolvfile='/tmp/resolv.conf.d/resolv.conf.auto'
set dhcp.wifi.localuse='0'
set dhcp.wifi.nohosts='1'
set dhcp.wifi.ignore_hosts_dir='1'
set dhcp.wifi.add_local_hostname='0'
delete dhcp.wifi.interface
add_list dhcp.wifi.interface='guest'
add_list dhcp.wifi.interface='iot'
delete dhcp.wifi.notinterface
add_list dhcp.wifi.notinterface='loopback'
set dhcp.guest=dhcp
set dhcp.guest.interface='guest'
set dhcp.guest.instance='wifi'
set dhcp.guest.start='100'
set dhcp.guest.limit='150'
set dhcp.guest.leasetime='2h'
set dhcp.guest.dhcpv4='server'
set dhcp.guest.dhcpv6='disabled'
set dhcp.guest.ra='disabled'
set dhcp.iot=dhcp
set dhcp.iot.interface='iot'
set dhcp.iot.instance='wifi'
set dhcp.iot.start='100'
set dhcp.iot.limit='150'
set dhcp.iot.leasetime='12h'
set dhcp.iot.dhcpv4='server'
set dhcp.iot.dhcpv6='disabled'
set dhcp.iot.ra='disabled'
set firewall.zone_guest=zone
set firewall.zone_guest.name='guest'
set firewall.zone_guest.network='guest'
set firewall.zone_guest.input='REJECT'
set firewall.zone_guest.output='ACCEPT'
set firewall.zone_guest.forward='REJECT'
set firewall.zone_iot=zone
set firewall.zone_iot.name='iot'
set firewall.zone_iot.network='iot'
set firewall.zone_iot.input='REJECT'
set firewall.zone_iot.output='ACCEPT'
set firewall.zone_iot.forward='REJECT'
set firewall.fwd_guest_wan=forwarding
set firewall.fwd_guest_wan.src='guest'
set firewall.fwd_guest_wan.dest='wan'
set firewall.fwd_iot_wan=forwarding
set firewall.fwd_iot_wan.src='iot'
set firewall.fwd_iot_wan.dest='wan'
set firewall.fwd_lan_iot=forwarding
set firewall.fwd_lan_iot.src='lan'
set firewall.fwd_lan_iot.dest='iot'
set firewall.seed_wifi_guest_dhcp=rule
set firewall.seed_wifi_guest_dhcp.name='seed wifi: guest DHCP to the router'
set firewall.seed_wifi_guest_dhcp.src='guest'
set firewall.seed_wifi_guest_dhcp.proto='udp'
set firewall.seed_wifi_guest_dhcp.dest_port='67'
set firewall.seed_wifi_guest_dhcp.family='ipv4'
set firewall.seed_wifi_guest_dhcp.target='ACCEPT'
set firewall.seed_wifi_guest_dns=rule
set firewall.seed_wifi_guest_dns.name='seed wifi: guest DNS to the router'
set firewall.seed_wifi_guest_dns.src='guest'
set firewall.seed_wifi_guest_dns.proto='tcp udp'
set firewall.seed_wifi_guest_dns.dest_port='53'
set firewall.seed_wifi_guest_dns.dest_ip='192.168.20.1'
set firewall.seed_wifi_guest_dns.target='ACCEPT'
set firewall.seed_wifi_guest_private=rule
set firewall.seed_wifi_guest_private.name='seed wifi: guest to private, link-local and tailnet addresses beyond the WAN'
set firewall.seed_wifi_guest_private.src='guest'
set firewall.seed_wifi_guest_private.dest='wan'
set firewall.seed_wifi_guest_private.proto='all'
set firewall.seed_wifi_guest_private.family='ipv4'
delete firewall.seed_wifi_guest_private.dest_ip
add_list firewall.seed_wifi_guest_private.dest_ip='10.0.0.0/8'
add_list firewall.seed_wifi_guest_private.dest_ip='172.16.0.0/12'
add_list firewall.seed_wifi_guest_private.dest_ip='192.168.0.0/16'
add_list firewall.seed_wifi_guest_private.dest_ip='100.64.0.0/10'
add_list firewall.seed_wifi_guest_private.dest_ip='169.254.0.0/16'
set firewall.seed_wifi_guest_private.target='REJECT'
set firewall.seed_wifi_iot_dhcp=rule
set firewall.seed_wifi_iot_dhcp.name='seed wifi: IoT DHCP to the router'
set firewall.seed_wifi_iot_dhcp.src='iot'
set firewall.seed_wifi_iot_dhcp.proto='udp'
set firewall.seed_wifi_iot_dhcp.dest_port='67'
set firewall.seed_wifi_iot_dhcp.family='ipv4'
set firewall.seed_wifi_iot_dhcp.target='ACCEPT'
set firewall.seed_wifi_iot_dns=rule
set firewall.seed_wifi_iot_dns.name='seed wifi: IoT DNS to the router'
set firewall.seed_wifi_iot_dns.src='iot'
set firewall.seed_wifi_iot_dns.proto='tcp udp'
set firewall.seed_wifi_iot_dns.dest_port='53'
set firewall.seed_wifi_iot_dns.dest_ip='192.168.30.1'
set firewall.seed_wifi_iot_dns.target='ACCEPT'
set firewall.seed_wifi_iot_private=rule
set firewall.seed_wifi_iot_private.name='seed wifi: IoT to private, link-local and tailnet addresses beyond the WAN'
set firewall.seed_wifi_iot_private.src='iot'
set firewall.seed_wifi_iot_private.dest='wan'
set firewall.seed_wifi_iot_private.proto='all'
set firewall.seed_wifi_iot_private.family='ipv4'
delete firewall.seed_wifi_iot_private.dest_ip
add_list firewall.seed_wifi_iot_private.dest_ip='10.0.0.0/8'
add_list firewall.seed_wifi_iot_private.dest_ip='172.16.0.0/12'
add_list firewall.seed_wifi_iot_private.dest_ip='192.168.0.0/16'
add_list firewall.seed_wifi_iot_private.dest_ip='100.64.0.0/10'
add_list firewall.seed_wifi_iot_private.dest_ip='169.254.0.0/16'
set firewall.seed_wifi_iot_private.target='REJECT'
EOF
  $R 'uci changes | cut -d. -f1 | sed "s/^-//" | sort | uniq -c | sed "s/^/  pending: /"; uci changes | grep -c "fixture" | sed "s/^/  pending changes naming a fixture: /"'
  [ "$1" = apply ] || exit 0
  $R 'uci commit && /etc/init.d/network reload && sleep 3 && /etc/init.d/dnsmasq restart && /etc/init.d/firewall reload 2>&1 | tail -2 && wifi reload && echo "applied: network, dnsmasq, firewall, wifi reloaded"' ;;
on|off)
  d=$([ "$1" = on ] && echo 0 || echo 1)
  $R "uci set wireless.radio1.disabled=$d && uci set wireless.radio0.disabled=1 && uci commit wireless && wifi reload && sleep 8 && echo \"radio1 disabled=\$(uci get wireless.radio1.disabled), radio0 disabled=\$(uci get wireless.radio0.disabled)\"" ;;
status)
  $R 'for r in radio0 radio1; do echo "$r: band $(uci get wireless.$r.band), channel $(uci get wireless.$r.channel), $(uci get wireless.$r.htmode), country $(uci -q get wireless.$r.country), disabled=$(uci -q get wireless.$r.disabled || echo 0)"; done
      uci show wireless | grep -E "^wireless\.wifi_[a-z]+\.(ssid|network|encryption|isolate|device)=" | sed "s/^wireless\.//"
      echo "access points running: $(iwinfo 2>/dev/null | grep -c ESSID)"; iwinfo 2>/dev/null | grep -E "ESSID|Channel|Encryption" | sed "s/^/  /"
      echo "ubus wireless:"; ubus call network.wireless status | jsonfilter -e "@.radio0.up" -e "@.radio1.up" | tr "\n" " " | sed "s/^/  radio0 up, radio1 up: /"; echo' ;;
*) echo "usage: router-wifi.sh apply | on | off | status"; exit 2 ;;
esac
