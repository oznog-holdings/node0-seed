# seed-wifi-test@<mode> (rung 6; the owner's decision 4, 20260929): the agent box's wifi card as the test
# client for the three wifi networks, in place of Larkbox one. It never touches the wired link: the card's
# phy moves into a network namespace `wtest`, and every address, route and resolver of the wifi exists only
# there. For each of seed, seed-guest and seed-iot (all 5 GHz, WPA2/WPA3 mixed) it joins with SAE, takes a
# DHCP lease, and runs the containment checks (the rows of rung 5's tools/wifi-test.sh, with generic
# targets instead of the lab's addresses); seed-iot is joined a second time with WPA2-PSK (the mixed mode).
# It then deletes the namespace (the phy returns; the card stays down).
#   mode rehearsal: against the rung 5 router (its gateways; the main gateway's MAC is the router's br-lan)
#   mode cutover:   behind the firewall (the same gateway addresses; every gateway's MAC is the firewall's re1)
# Results: /var/lib/seed-wifi-test/<mode>-<UTC>.txt and <mode>-latest.txt (world-readable), one row per
# check: net | check | expected | result | ok/FAIL; the last line "fails N". The unit fails if N > 0.
# The passphrases come from sops (wifi_seed, wifi_seed_guest, wifi_seed_iot; the vault items "wifi seed" etc.)
# into a 0600 file in the unit's runtime directory, removed once associated. The agent user may start the
# unit (polkit rule below), nothing else.
{ config, lib, pkgs, ... }:
let
  fwMac = "02:00:00:00:00:01";       # the firewall's re1 (hosts.md fw); its VLANs carry the same MAC
  routerLanMac = "02:00:00:00:00:01"; # the router's br-lan (hosts.md router)
  dhcpDiscover = ./wifi-test/dhcp-discover.py;
  script = pkgs.writeShellScript "seed-wifi-test" ''
    set -uo pipefail; shopt -s extglob
    export PATH=${lib.makeBinPath (with pkgs; [ coreutils gnugrep gawk gnused iproute2 iputils bash iw wpa_supplicant dhcpcd dnsutils curl netcat-openbsd procps util-linux python3 iperf3 ])}
    mode=''${1:?mode}; case $mode in rehearsal|cutover|iperf) ;; *) echo "mode: rehearsal|cutover|iperf"; exit 2 ;; esac
    IF=wlp0s20f3; NS=wtest; N="ip netns exec $NS"; W=$RUNTIME_DIRECTORY; OUT=/var/lib/seed-wifi-test
    stamp=$(date -u +%Y%m%dT%H%M%SZ); R=$OUT/$mode-$stamp.txt; fails=0
    phy=$(basename "$(readlink /sys/class/net/$IF/phy80211 2>/dev/null)" 2>/dev/null)
    row() { local ok=FAIL pat=$3; [[ $pat == *'|'* ]] && pat="@($pat)"; [[ $4 == $pat ]] && ok=ok; [ $ok = ok ] || fails=$((fails+1))
            printf '%-6s | %-50s | %-24s | %-30s | %s\n' "$1" "$2" "$3" "$4" "$ok" >> $R; }
    teardown() {
      for p in $W/*.pid; do [ -f "$p" ] && kill "$(cat "$p")" 2>/dev/null; done; sleep 1
      pkill -f "wpa_supplicant -B -i $IF" 2>/dev/null; pkill -f "dhcpcd.* $IF\$" 2>/dev/null; sleep 1
      ip netns del $NS 2>/dev/null; rm -rf /etc/netns/$NS; sleep 1
      ip link set $IF down 2>/dev/null
      echo "teardown: $IF in the main namespace: $(ip -br link show $IF 2>/dev/null | awk '{print $2}'); namespaces left: $(ip netns list | grep -c $NS)" >> $R; }
    trap teardown EXIT
    echo "# seed-wifi-test $mode $(date -u +%FT%TZ) on $(hostname), card $IF ($phy); the wired link: $(ip -br -4 addr show enp2s0 | awk '{print $3}')" > $R
    printf '%-6s | %-50s | %-24s | %-30s | %s\n' net check expected result "" >> $R
    [ -n "$phy" ] || { row all "the wifi card is in the main namespace" present missing; exit 1; }
    # every command a row uses: a missing one would read as "no answer" / "not open" (20260929: ping and bash were)
    for c in ping bash timeout nc dig curl ss wpa_supplicant wpa_cli dhcpcd iw ip python3; do command -v $c >/dev/null || row all "the command $c" present missing; done
    ip netns add $NS; $N ip link set lo up; iw phy $phy set netns name $NS; $N ip link set $IF up
    wired0=$(ip route show default | head -1)
    join() {  # ssid key-file SAE|PSK: associate only (wpa state in $W/st)
      local ssid=$1 key=$2 m=$3 km st i
      if [ $m = SAE ]; then km="key_mgmt=SAE\n ieee80211w=2\n sae_password=\"$(cat $key)\""; else km="key_mgmt=WPA-PSK\n ieee80211w=0\n psk=\"$(cat $key)\""; fi
      ( umask 077; printf "ctrl_interface=$W/ctrl\nnetwork={\n ssid=\"%s\"\n $km\n}\n" "$ssid" > $W/wpa.conf )
      $N wpa_supplicant -B -i $IF -c $W/wpa.conf -P $W/wpa.pid -f $W/wpa.log </dev/null >/dev/null 2>&1
      for i in $(seq 1 40); do st=$($N wpa_cli -s $W -p $W/ctrl -i $IF status 2>/dev/null); grep -q '^wpa_state=COMPLETED' <<<"$st" && break; sleep 1; done
      rm -f $W/wpa.conf
      echo "$st" > $W/st; }
    dhcp() {  # hostname-suffix -> "addr|router|dns"
      local i
      printf '#!/bin/sh\n[ -n "$new_ip_address" ] && echo "$new_ip_address|$new_routers|$new_domain_name_servers" > %s/lease\n' $W > $W/hook.sh; chmod 700 $W/hook.sh
      rm -f $W/lease; $N dhcpcd -4 -1 -h "seed-wifitest-$1" -o domain_name_servers -c $W/hook.sh --noipv4ll --nobackground -t 30 $IF </dev/null > $W/dh.log 2>&1 &
      echo $! > $W/dh.pid
      for i in $(seq 1 30); do [ -s $W/lease ] && break; sleep 1; done; sleep 1
      cat $W/lease 2>/dev/null || echo "none|none|none"; }
    leave() { for p in $W/dh.pid $W/wpa.pid; do [ -f $p ] && kill "$(cat $p)" 2>/dev/null; rm -f $p; done; sleep 2; $N ip -4 addr flush dev $IF 2>/dev/null; rm -f $W/lease; }
    probe() { local out rc; out=$($N nc -z -v -w 4 "$1" "$2" 2>&1); rc=$?
      if [ $rc = 0 ]; then echo open; elif grep -qi refused <<<"$out"; then echo refused; elif grep -qiE "unreachable|no route|prohibited" <<<"$out"; then echo unreachable; else echo timeout; fi; }
    dnsq() { local out st ans; out=$($N dig +time=3 +tries=1 @"$1" "$2" A 2>&1)
      st=$(sed -n 's/.*status: \([A-Z]*\).*/\1/p' <<<"$out"); ans=$(sed -n '/ANSWER SECTION/,/^$/p' <<<"$out" | awk '$4=="A"{print $5}' | sort | tr '\n' ' ' | sed 's/ $//')
      echo "''${st:-no answer}''${ans:+ $ans}"; }
    https() { $N curl -s -o /dev/null -w '%{http_code}' --max-time 12 "$1" || echo failed; }
    gwmac() { $N ping -c1 -W2 "$1" >/dev/null 2>&1; $N ip neigh show "$1" | awk '{for(i=1;i<=NF;i++) if($i=="lladdr") print $(i+1)}'; }
    offers() { $N python3 ${dhcpDiscover} $IF 2>/dev/null | sed -n 's/^OFFER from \([0-9.]*\) (\([0-9a-f:]*\)).*/\1 \2/p' | sort -u | tr '\n' ',' | sed 's/,$//'; }
    run() {  # net ssid key subnet dnsx
      local net=$1 ssid=$2 key=$3 sn=$4 dnsx=$5 l a gw dns m off
      join "$ssid" "$key" SAE
      row "$net" "associate $ssid (SAE, 5 GHz)" "SAE COMPLETED" "$(grep -o '^key_mgmt=.*' $W/st | cut -d= -f2) $(grep -o '^wpa_state=.*' $W/st | cut -d= -f2)"
      off=$(offers)                      # before dhcpcd holds port 68
      l=$(dhcp "$net"); IFS='|' read -r a gw dns <<<"$l"
      row "$net" "DHCP: an address in $sn.0/24" "$sn.*" "''${a:-none}"
      row "$net" "DHCP: router" "$sn.1" "''${gw:-none}"
      row "$net" "DHCP: DNS server(s)" "$dnsx" "''${dns:-none}"
      if [ $mode = cutover ]; then row "$net" "DHCP: only the firewall offers (IP MAC)" "$sn.1 ${fwMac}" "''${off:-none}"
      else row "$net" "DHCP: one server offers" "$sn.1 *" "''${off:-none}"; fi
      m=$(gwmac $sn.1)
      if [ $mode = cutover ]; then row "$net" "the gateway's MAC is the firewall's re1" "${fwMac}" "''${m:-none}"
      elif [ $net = main ]; then row "$net" "the gateway's MAC is the router's br-lan" "${routerLanMac}" "''${m:-none}"
      else row "$net" "the gateway isn't the firewall" "!(${fwMac})" "''${m:-none}"; fi
      row "$net" "DNS: example.com via ''${dns%% *}" "NOERROR *" "$(dnsq ''${dns%% *} example.com)"
      row "$net" "internet: https://example.com" "200" "$(https https://example.com)"
      row "$net" "the access point's LAN address 192.168.1.4:53 (no resolver there)" "refused|unreachable|timeout" "$(probe 192.168.1.4 53)"
      if [ $net = main ]; then
        row "$net" "site name vault.seed.example.com via ''${dns%% *}" "NOERROR 192.168.1.10" "$(dnsq ''${dns%% *} vault.seed.example.com)"
        row "$net" "site: https://vault.seed.example.com/alive" "200" "$(https https://vault.seed.example.com/alive)"
        row "$net" "LAN: infra 192.168.1.10:443" open "$(probe 192.168.1.10 443)"
        row "$net" "LAN: core 192.168.1.12:22" open "$(probe 192.168.1.12 22)"
        row "$net" "leases into DNS: seed-wifitest-main.lan.seed.example.com (ns1)" "NOERROR ''${a%/*}" "$(sleep 3; dnsq 192.168.1.15 seed-wifitest-main.lan.seed.example.com)"
      else
        row "$net" "site name vault.seed.example.com via its own gateway" "NXDOMAIN|SERVFAIL|no answer" "$(dnsq $sn.1 vault.seed.example.com)"
        row "$net" "the site's DNS ns1 192.168.1.15:53" "refused|unreachable|timeout" "$(probe 192.168.1.15 53)"
        for t in 192.168.1.1:443:gateway-LAN 192.168.1.10:443:infra 192.168.1.11:22:agent 192.168.1.12:22:core 10.0.0.1:53:rfc1918-10 172.16.0.1:53:rfc1918-172 100.64.0.11:22:tailnet-agent; do
          IFS=: read -r h p n <<<"$t"; row "$net" "refused: $n $h:$p" "refused|unreachable|timeout" "$(probe $h $p)"; done
        for p in 22 80 443; do row "$net" "its own gateway $sn.1:$p (only DHCP, DNS)" "refused|unreachable|timeout" "$(probe $sn.1 $p)"; done
        local other=$([ $net = guest ] && echo 192.168.30.1 || echo 192.168.20.1)
        row "$net" "the other segment's gateway $other:53" "refused|unreachable|timeout" "$(probe $other 53)"
        $N nc -4 -lk 8080 >/dev/null 2>&1 & echo $! > $W/listen.pid; sleep 1
        row "$net" "  (diagnostic) a listener on :8080 in the namespace" "0.0.0.0:8080" "$($N ss -ltnH 'sport = :8080' | awk '{print $4}' | head -1)"
        row "$net" "  (diagnostic) ping from the LAN to this client" "$([ $net = iot ] && echo answers || echo 'answers|no answer')" "$(ping -c2 -W2 ''${a%/*} >/dev/null 2>&1 && echo answers || echo 'no answer')"
        local lan; lan=$(timeout 5 bash -c "exec 3<>/dev/tcp/''${a%/*}/8080" 2>/dev/null && echo open || echo "not open")
        row "$net" "from the LAN (the wired side) to this client :8080" "$([ $net = iot ] && echo open || echo 'not open')" "$lan"
        kill "$(cat $W/listen.pid)" 2>/dev/null; rm -f $W/listen.pid
      fi
      leave
      row "$net" "the wired link untouched (default route)" "$wired0" "$(ip route show default | head -1)"
    }
    if [ $mode = iperf ]; then
      # rung 6 throughput, path (b): the wired LAN -> the firewall (routed) -> VLAN 30 -> the access point -> this card
      # on seed-iot. iperf3's server runs in the namespace (LAN -> IoT is allowed; the IoT side opens nothing); the
      # clients run from the wired side: 1 and 4 streams, both directions, 30 s each. Bounded by the wifi link.
      join seed-iot ${config.sops.secrets.wifi_seed_iot.path} SAE; l=$(dhcp iot); IFS='|' read -r a gw dns <<<"$l"
      row iot "associate seed-iot (SAE, 5 GHz)" "SAE COMPLETED" "$(grep -o '^key_mgmt=.*' $W/st | cut -d= -f2) $(grep -o '^wpa_state=.*' $W/st | cut -d= -f2)"
      row iot "DHCP: an address in 192.168.30.0/24" "192.168.30.*" "''${a:-none}"
      echo "# the wifi link: $($N iw dev $IF link | grep -E 'freq|signal|rx bitrate|tx bitrate' | sed 's/^[[:space:]]*//' | tr '\n' ';')" >> $R
      $N iperf3 -s -p 5201 >/dev/null 2>&1 & echo $! > $W/iperf.pid; sleep 1
      for t in "1 fwd" "4 fwd" "1 rev" "4 rev"; do set -- $t; flag=""; [ $2 = rev ] && flag=-R
        echo "# test P=$1 $2 start $(date -u +%FT%TZ)" >> $R
        iperf3 -c ''${a%/*} -p 5201 -t 30 -P $1 $flag -f m 2>&1 | grep -E 'sender|receiver' | grep -E "SUM|^\[ *[0-9]+\]" | tail -2 | sed "s/^/# P=$1 $2: /" >> $R
        echo "# test P=$1 $2 end $(date -u +%FT%TZ)" >> $R; sleep 5; done
      echo "# the wifi link after: $($N iw dev $IF link | grep -E 'rx bitrate|tx bitrate' | sed 's/^[[:space:]]*//' | tr '\n' ';')" >> $R
      kill "$(cat $W/iperf.pid)" 2>/dev/null; rm -f $W/iperf.pid
      leave; echo "fails $fails" >> $R; ln -sfn $(basename $R) $OUT/$mode-latest.txt; exit 0
    fi
    run main  seed       ${config.sops.secrets.wifi_seed.path}       192.168.1  "192.168.1.15 192.168.1.16"
    run guest seed-guest ${config.sops.secrets.wifi_seed_guest.path} 192.168.20 "192.168.20.1"
    run iot   seed-iot   ${config.sops.secrets.wifi_seed_iot.path}   192.168.30 "192.168.30.1"
    join seed-iot ${config.sops.secrets.wifi_seed_iot.path} PSK; l=$(dhcp iot2); IFS='|' read -r a gw dns <<<"$l"
    row iot "associate seed-iot with WPA2-PSK (the mixed mode)" "WPA2-PSK COMPLETED" "$(grep -o '^key_mgmt=.*' $W/st | cut -d= -f2) $(grep -o '^wpa_state=.*' $W/st | cut -d= -f2)"
    row iot "  internet: https://example.com" 200 "$(https https://example.com)"
    leave
    echo "fails $fails" >> $R
    ln -sfn $(basename $R) $OUT/$mode-latest.txt
    [ $fails = 0 ]
  '';
in {
  sops.secrets.wifi_seed = { };
  sops.secrets.wifi_seed_guest = { };
  sops.secrets.wifi_seed_iot = { };
  systemd.services."seed-wifi-test@" = {
    description = "The agent box's wifi as the test client of the seed's wifi networks (%i)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${script} %i";
      RuntimeDirectory = "seed-wifi-test";
      RuntimeDirectoryMode = "0700";
      StateDirectory = "seed-wifi-test";
      StateDirectoryMode = "0755";
      UMask = "0022";
      TimeoutStartSec = "15min";
    };
  };
  security.polkit.enable = true;
  security.polkit.extraConfig = ''
    // seed (rung 6): the builder may run the wifi test unit, and nothing else through this rule
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" && subject.user == "agent") {
        var unit = action.lookup("unit"), verb = action.lookup("verb");
        if ((unit == "seed-wifi-test@rehearsal.service" || unit == "seed-wifi-test@cutover.service" || unit == "seed-wifi-test@iperf.service") && verb == "start")
          return polkit.Result.YES;
      }
    });
  '';
}
