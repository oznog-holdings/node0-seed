#!/usr/bin/env bash
# rung6-cutover.sh: rung 6 phase 3, the window, as one script (the owner's decision, 20260929: an agent must
# not depend on the path it is changing). It runs on the agent box and needs no internet: it talks only to
# the router, the firewall and core over the LAN (and the site vault, on infra). Started before the owner
# unplugs anything; from then on nobody has to be in a conversation.
#   tools/rung6-cutover.sh --dry-run   every precondition checked; nothing changes anywhere; in the foreground
#   tools/rung6-cutover.sh             the window: detaches (setsid) and returns the log's path
# The log: /var/tmp/seed-cutover/<run|dry>-<UTC>.log, and latest.log (world-readable; over the LAN:
# `ssh agent@192.168.1.11 cat /var/tmp/seed-cutover/latest.log`). One line per step and check:
# "<UTC> <step> | <what> | ok/FAIL/WAIT/INFO | <detail>"; the last lines say DONE, or WAY BACK and one
# instruction for the owner (a line starting "OWNER:").
# The steps (site/runbooks/rung6.md › phase 3):
#   0  the preconditions (as the dry run); the router's backup (tools/router-backup.sh; the internet still up)
#   1  wait for the owner to unplug the upstream cable from the router's eth0 (no carrier), limit 20 min
#   2  the router becomes the access point: site/router/config-tool apply --ap (config.ap/, the WAN
#      disabled: the one change to the lab's sections, the orchestrator's written yes; the router's 120 s
#      rollback, confirmed at 192.168.1.4); nothing listens on :53 or :67 there; `check --ap` equal
#   3  the firewall takes the gateway: site/firewall/seed-cutover-fw gateway (LAN 192.168.1.2 -> .1, Kea on
#      lan; its own 180 s rollback, confirmed from here at .1 after: re1 .1, Kea's interfaces, and one DHCP
#      server on the LAN, the firewall, DNS .15 .16, seen from core)
#   4  wait for the owner's recabling (firewall re1 -> the router's eth0, the upstream -> the firewall's re0):
#      carrier on re0 and on the router's eth0, limit 20 min; then a TCP connection from re0's address to the
#      WAN gateway's port 53 (the upstream allows the site only DNS and NTP to its own addresses, never ping;
#      window 2), limit 5 min; the ping logged as information. Booleans; the address never leaves the firewall
#   5  the offline checks: every box answers, DNS at ns1 and ns2, the access point clean, one DHCP server,
#      the wifi test (seed-wifi-test@cutover: every row but the ones that need the internet)
#   6  INFO only: when the internet returns (the upstream's ARP refresh is the owner's step 5), up to 10 min
# Any FAIL from step 2 on, or a time limit, runs the way back by itself, in the runbook's order (20260929, after window 3):
#   1. the firewall to 192.168.1.2 with Kea's lan off: `back` started whenever it answers at .1, else its own
#      rollback (180 s); the wait lasts until that deadline + 90 s;
#   2. the router to rung 5 (`config-tool apply --offline`, its 180 s rollback, confirmed at .1 by the router's host
#      key) as soon as 192.168.1.1 is proven free (silent to ping, :22 and :443, three times). If something still
#      holds .1, one OWNER line asks for the firewall's LAN cable to be unplugged and the way back goes on by itself
#      once .1 is silent (up to 30 min); a failed confirmation is retried once after the router's own rollback;
#   3. one OWNER line for the cables.
# Every check over the LAN from step 2 on is retried through short link losses (the owner may move a cable any time).
set -uo pipefail
cd "$(dirname "$0")/.."
REPO=$PWD
MODE=run; case ${1:-} in --dry-run) MODE=dry ;; --rehearse-fw) MODE=rehearse ;; esac
# --rehearse-fw: the firewall's move with the window's own functions, on a spare address and without an outage
# (20260929, after window 3): .2 -> .3 with Kea unchanged (main DHCP stays the router's) and the confirmation over
# ssh, then the way back's firewall part; then .2 -> .3 unconfirmed, so the firewall's own rollback fires and the
# way back's wait must see it. In the foreground.
T_UNPLUG=${T_UNPLUG:-1200}; T_RECABLE=${T_RECABLE:-1200}; T_GW=${T_GW:-300}; T_NET=${T_NET:-600}
OUT=/var/tmp/seed-cutover
FWMAC=02:00:00:00:00:01; ROUTERMAC=02:00:00:00:00:01
S="ssh -o BatchMode=yes -o LogLevel=ERROR -o ConnectTimeout=5"
RT1="$S root@192.168.1.1"; RT4="$S root@192.168.1.4"                       # the router, before / after
FW2="$S root@192.168.1.2"; FW1="$S -o HostKeyAlias=192.168.1.2 root@192.168.1.1"   # the firewall, its own key
FW_W=180      # the firewall's own rollback window (seed-cutover-fw reload-and-wait); FW_T0 = when it started
FW_T0=0; FW_TO=192.168.1.1
CORE="$S admin@192.168.1.12"

if [[ $MODE == run && ${SEED_CUTOVER_DETACHED:-} != 1 ]]; then
  mkdir -p -m 755 $OUT; stamp=$(date -u +%Y%m%dT%H%M%SZ)
  SEED_CUTOVER_DETACHED=1 SEED_CUTOVER_STAMP=$stamp setsid nohup "$0" </dev/null >/dev/null 2>&1 &
  echo "started (pid $!); the log: $OUT/run-$stamp.log (and $OUT/latest.log)"; exit 0
fi
mkdir -p -m 755 $OUT; umask 022
LOG=$OUT/$MODE-${SEED_CUTOVER_STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}.log; : > $LOG; ln -sfn $(basename $LOG) $OUT/latest.log
STEP=0; FAILS=0; AP_DONE=0; FW_DONE=0; RECABLED=0; FINISHED=0
log() { local l; l="$(date -u +%FT%TZ) $STEP | $1 | $2 | ${3:-}"; echo "$l" >> $LOG; [[ $MODE != run ]] && echo "$l"; return 0; }
chk() { # chk "what" <command...>: ok if the command succeeds; its last output line as the detail
  local what=$1 o rc; shift; o=$("$@" 2>&1); rc=$?; o=$(tail -1 <<<"$o" | cut -c1-200)
  if [[ $rc == 0 ]]; then log "$what" ok "$o"; else log "$what" FAIL "$o"; FAILS=$((FAILS+1)); fi; return $rc; }
# chkr <limit s> "what" <command...>: as chk, retried every 3 s up to the limit. Every check over the LAN from step 2
# on: the owner may move a cable at any moment (window 3: re1 was down 9 s during step 3's single-shot confirmation)
chkr() { local lim=$1 what=$2 o rc t0=$SECONDS; shift 2
  while :; do o=$("$@" 2>&1); rc=$?; [[ $rc == 0 ]] && break; (( SECONDS - t0 + 3 < lim )) || break; sleep 3; done
  o=$(tail -1 <<<"$o" | cut -c1-180)
  if [[ $rc == 0 ]]; then log "$what" ok "$o$( (( SECONDS - t0 > 2 )) && echo " (after $((SECONDS - t0)) s)")"; else log "$what" FAIL "$o (tried ${lim} s)"; FAILS=$((FAILS+1)); fi; return $rc; }
# the command output into the log, indented, for the record
rec() { sed 's/^/        /' >> $LOG; }
wait_for() { # wait_for "what" <limit s> <command...>: poll every 5 s
  local what=$1 lim=$2 t0=$SECONDS; shift 2; log "$what" WAIT "limit ${lim} s"
  while (( SECONDS - t0 < lim )); do "$@" >/dev/null 2>&1 && { log "$what" ok "after $((SECONDS - t0)) s"; return 0; }; sleep 5; done
  log "$what" FAIL "not within ${lim} s"; FAILS=$((FAILS+1)); return 1; }

# --- the checks, as functions (each prints one line; succeeds or fails) ---
router_carrier() { [[ $($1 'cat /sys/class/net/eth0/carrier 2>/dev/null' || echo x) == "$2" ]] && echo "eth0 carrier $2"; }
nothing_at() { ! ping -c 2 -W 1 "$1" >/dev/null 2>&1 && echo "$1 silent"; }
answers() { ping -c 2 -W 2 "$1" >/dev/null 2>&1 && echo "$1 answers"; }
dns_ok() { host -W 3 infra.seed.example.com "$1" | grep -q 'has address 192\.168\.1\.10$' && echo "infra.seed.example.com at $1 = 192.168.1.10"; }
ap_quiet() { local l; l=$($RT4 'netstat -lnu 2>/dev/null; netstat -lnt 2>/dev/null' | awk '$4 ~ /:(53|67)$/') || return 1; [[ -z $l ]] && echo "nothing on :53 or :67"; }
fw_state() { $1 'sh -s' <<<'echo "re1 $(ifconfig re1 | awk "/inet /{print \$2}" | tr "\n" " ")Kea $(php -r '"'"'require_once "config.inc"; echo (string)OPNsense\Core\Config::getInstance()->object()->OPNsense->Kea->dhcp4->general->interfaces;'"'"')"'; }
fw_is() { local s; s=$(fw_state "$1") || return 1; echo "$s"; [[ $s == "$2" ]]; }
dhcp_one() { # dhcp_one <server IP> <server MAC>: exactly one DHCP server on the LAN, that one, DNS .15 .16 (from core; 3 tries)
  local o i; for i in 1 2 3; do o=$($CORE 'sudo -n python3 - eth0' < tools/dhcp-discover.py 2>&1); echo "$o" | rec
    grep -q '^1 DHCP server(s) answered' <<<"$o" && grep -q "^OFFER from $1 ($2): .*DNS 192.168.1.15, 192.168.1.16" <<<"$o" && { echo "one server, $1 ($2), DNS .15 .16 (try $i)"; return 0; }
    sleep 3; done; return 1; }
fw_wan() { local o; o=$($FW1 /root/seed-cutover-fw wan 2>/dev/null) || return 1; echo "$o"; }
recabled() { local w; w=$(fw_wan) && [[ $w == 're0 active;'* ]] && router_carrier "$RT4" 1 >/dev/null; }
gw_answers() { [[ $(fw_wan) == *'tcp53 open;'* ]]; }
detach_ok() { local m="seed-detach-check-$$-$RANDOM"
  $RT1 "setsid sh -c 'sleep 1; logger -t seed-cutover $m' </dev/null >/dev/null 2>&1 &" || return 1; sleep 3
  $RT1 "logread -e $m | grep -q $m" && echo "a setsid child logged after the session ended"; }
fw_detach_ok() { local m="seed-detach-check-$$-$RANDOM"
  $FW2 "daemon -f sh -c 'sleep 1; logger -t seed-cutover $m'" || return 1; sleep 3
  $FW2 'sh -s' <<<"grep -rlq $m /var/log/system/" && echo "a daemon(8) child logged after the session ended"; }
ap_renders() { local o; o=$(site/router/config-tool apply --dry-run --ap 2>&1) || return 1; echo "$o" | grep -v unchanged | rec
  grep -q "the WAN is disabled in the render" <<<"$o" && grep -q "would import dhcp firewall network system" <<<"$o" && echo "rendered: the WAN disabled; dhcp firewall network system"; }
wifi_cutover() { # the unit's rows; FAIL rows count except the ones that need the internet, and diagnostics
  systemctl start seed-wifi-test@cutover.service >/dev/null 2>&1; local f=/var/lib/seed-wifi-test/cutover-latest.txt n
  [[ -r $f ]] && (( $(date +%s) - $(stat -Lc %Y $f) < 900 )) || { echo "no fresh result"; return 1; }
  rec < $f; n=$(awk -F' [|] ' '$NF ~ /FAIL/ && $2 !~ /example\.com|\(diagnostic\)/' $f | wc -l)
  echo "$(readlink -f $f): $n offline row(s) failed; $(tail -1 $f)"; [[ $n == 0 ]]; }

# --- the firewall's move and its way back (the window's step 3 and the rehearsal use the same code) ---
fw_new() { $S -o HostKeyAlias=192.168.1.2 root@$FW_TO "$@"; }     # the firewall at its new address, by its own key
fw_move() { # fw_move <to> <kea> <dhcp-check 0|1> <confirm 0|1>
  local kea=$2 dh=$3 cf=$4 left; FW_TO=$1
  $FW2 'cat > /root/seed-cutover-fw && chmod 700 /root/seed-cutover-fw' < site/firewall/seed-cutover-fw || { log "copying the firewall's script" FAIL ""; return 1; }
  FW_DONE=1; FW_T0=$SECONDS
  chk "the firewall: LAN .2 -> $FW_TO, Kea $kea (its own ${FW_W} s rollback)" $FW2 /root/seed-cutover-fw gateway $FW_TO $kea || return 1
  wait_for "the firewall at $FW_TO" 90 fw_new true || return 1
  chkr 30 "the firewall: LAN $FW_TO, Kea $kea" fw_is fw_new "re1 $FW_TO Kea $kea" || return 1
  chkr 30 "the firewall's ssh and web GUI moved to $FW_TO" fw_listens $FW_TO || return 1
  if (( dh )); then chkr 30 "one DHCP server, the firewall" dhcp_one $FW_TO $FWMAC || return 1; fi
  (( cf )) || { log "the firewall: not confirmed, on purpose" INFO "its own rollback is due ${FW_W} s after the move started"; return 0; }
  left=$(( FW_T0 + FW_W - 30 - SECONDS ))   # retried until 30 s before the firewall's own deadline
  chkr $left "the firewall: confirmed" fw_new 'touch /tmp/seed-cutover-confirmed && echo confirmed' || return 1
  fw_new 'cat /tmp/seed-cutover-fw.log' 2>/dev/null | rec; }
fw_listens() { local o; o=$(fw_new "sockstat -4l | awk '\$2 ~ /sshd|lighttpd/ {print \$2, \$6}'" ) || return 1; echo "$o" | rec
  grep -q "^sshd $1:22$" <<<"$o" && grep -q "^lighttpd $1:443$" <<<"$o" && [[ -z $(grep -E '192\.168\.1\.[0-9]+:' <<<"$o" | grep -v " $1:") ]] && echo "sshd and lighttpd on $1 only (no other LAN address)"; }
fw_back() { # fw_back [trigger 0|1]: until the firewall is proven at .2 with Kea opt1,opt2. Whenever it answers at its
  # new address, `back` is started there; otherwise its own rollback lands at FW_T0+FW_W. The wait lasts until that
  # deadline plus 90 s, and never less than 90 s. (Window 3: 150 s against a 180 s rollback, one try at .1.)
  local trig=${1:-1} started=0 deadline=$(( FW_T0 + FW_W + 90 )); (( deadline < SECONDS + 90 )) && deadline=$(( SECONDS + 90 ))
  log "the firewall back at 192.168.1.2 (Kea opt1,opt2)" WAIT "until $((deadline - SECONDS)) s from now: its own rollback is due $(( FW_T0 + FW_W - SECONDS )) s from now"
  while (( SECONDS < deadline )); do
    if fw_is "$FW2" "re1 192.168.1.2 Kea opt1,opt2" >/dev/null 2>&1; then
      log "the firewall back at 192.168.1.2 (Kea opt1,opt2)" ok "$(( SECONDS - FW_T0 )) s after the move started$( (( started )) && echo ", by \`back\`" || echo ", by its own rollback")"; FW_DONE=0; return 0; fi
    if (( trig && !started )) && fw_new 'daemon -f /root/seed-cutover-fw back' 2>/dev/null; then started=1; log "the firewall: \`back\` started at $FW_TO" INFO ""; fi
    sleep 3; done
  log "the firewall back at 192.168.1.2" FAIL "not by $(( deadline - FW_T0 )) s after the move started"; FAILS=$((FAILS+1)); return 1; }
addr_free() { # an address proven free: nothing answers ping, ssh or https there, three times over ~10 s
  local i; for i in 1 2 3; do ping -c 1 -W 1 $1 >/dev/null 2>&1 && return 1; nc -z -w 2 $1 22 2>/dev/null && return 1; nc -z -w 2 $1 443 2>/dev/null && return 1; sleep 2; done; echo "$1 silent (ping, :22, :443; 3 times)"; }
one_free() { addr_free 192.168.1.1; }

# --- the way back ---
owner() { log "OWNER" INFO "$1"; echo "OWNER: $1" >> $LOG; }
wayback() {
  STEP=back; log "the way back" INFO "reason: $1"
  local where
  if (( FW_DONE )); then fw_back 1 || true; fi
  if (( AP_DONE )); then
    # the router goes back to rung 5 as soon as 192.168.1.1 is proven free. config-tool confirms at .1 by the
    # router's own host key, so a firewall still at .1 fails the confirmation and the router rolls itself back.
    if ! wait_for "192.168.1.1 free" 60 one_free; then
      owner "Unplug the firewall's LAN cable (it may still hold 192.168.1.1); the way back continues by itself once 192.168.1.1 is silent."
      wait_for "192.168.1.1 free (after the owner unplugs the firewall's LAN cable)" 1800 one_free || { log "WAY BACK" FAIL "192.168.1.1 never became free: the router stays the access point at 192.168.1.4"; owner "The builder is needed: something holds 192.168.1.1 and the router is still the access point."; FINISHED=1; return; }
    fi
    local try; for try in 1 2; do
      if $RT4 true 2>/dev/null; then where=4; elif $RT1 true 2>/dev/null; then where=1; else where=none; fi
      [[ $where == 1 ]] && { log "the router" INFO "already at 192.168.1.1"; break; }
      [[ $where == none ]] && { wait_for "the router at 192.168.1.4 or .1" 240 sh -c "$RT4 true || $RT1 true" || break; continue; }
      ROUTER=192.168.1.4 site/router/config-tool apply --rung5 --offline > >(rec) 2>&1 && break
      log "config-tool apply --offline (try $try)" FAIL "the router rolls itself back to the access point within 180 s"
      wait_for "the router back at 192.168.1.4 (its rollback)" 240 $RT4 true; done
    chkr 30 "the router back to rung 5 at 192.168.1.1" $RT1 true
    chkr 60 "the router: rung 5 configuration (config-tool check)" site/router/config-tool check --rung5
    chkr 30 "one DHCP server, the router" dhcp_one 192.168.1.1 $ROUTERMAC
  fi
  if (( RECABLED )) || [[ $(fw_wan_any) == 're0 active'* ]]; then
    owner "Move the upstream cable from the firewall's WAN port back into the router's 2.5G port (eth0), and the firewall's LAN cable from the router's eth0 back into the switch; if the internet isn't back in a few minutes, have the upstream's ARP entry refreshed."
  elif (( STEP_REACHED >= 2 )); then
    owner "Plug the upstream cable back into the router's 2.5G port (eth0)."
  else owner "Nothing was changed; the window didn't start. Plug the upstream cable back into the router's 2.5G port (eth0) if it's out."; fi
  log "WAY BACK" INFO "finished; the internet returns once the cable is back"; FINISHED=1
}
fw_wan_any() { $FW2 'ifconfig re0' 2>/dev/null | awk '/status:/{print "re0", $2; exit}'; }
STEP_REACHED=0
fail() { log "STOP" FAIL "$1"; if (( STEP_REACHED >= 2 )); then wayback "$1"; else owner "Nothing was changed; the window didn't start ($1). Plug the upstream cable back into the router's 2.5G port (eth0) if it's out."; FINISHED=1; fi; exit 1; }
trap '(( FINISHED )) || { log "the script" FAIL "stopped unexpectedly"; (( STEP_REACHED >= 2 )) && wayback "the script stopped unexpectedly"; }' EXIT
trap 'fail "interrupted"' INT TERM

# --- the rehearsal of the firewall's move (no outage: the router stays the gateway and the only DHCP server) ---
if [[ $MODE == rehearse ]]; then
  STEP=r0; log "rehearsal of the firewall's move, on 192.168.1.3" INFO "$(hostname)"
  export_eq() { $FW2 /usr/local/sbin/seed-config-export | diff -q - site/firewall/config.expected.xml >/dev/null && echo "the export = config.expected.xml"; }
  at2() { FW_TO=192.168.1.2 fw_listens 192.168.1.2; }
  pre=0
  chk "the firewall: LAN .2, Kea opt1,opt2" fw_is "$FW2" "re1 192.168.1.2 Kea opt1,opt2" || pre=1
  chk "192.168.1.3 free" addr_free 192.168.1.3 || pre=1
  chk "the router = rung 5" site/router/config-tool check --rung5 || pre=1
  chk "one DHCP server, the router" dhcp_one 192.168.1.1 $ROUTERMAC || pre=1
  chk "the firewall's export before" export_eq || pre=1
  (( pre == 0 )) || { log "REHEARSAL" FAIL "a precondition failed; nothing moved"; FINISHED=1; exit 1; }
  STEP=A; log "A: the move with the confirmation over ssh, then the way back's firewall part" INFO ""
  if fw_move 192.168.1.3 opt1,opt2 0 1; then
    chk "A: the router is still the one DHCP server" dhcp_one 192.168.1.1 $ROUTERMAC
    chk "A: nothing on .2 while the firewall is at .3" addr_free 192.168.1.2
  fi
  fw_back 1; chkr 30 "A: sshd and the web GUI back on .2 only" at2; chk "A: the export after" export_eq
  STEP=B; log "B: the move without a confirmation: the firewall's own rollback must fire, and the way back's wait see it" INFO ""
  fw_move 192.168.1.3 opt1,opt2 0 0; fw_back 0; chkr 30 "B: sshd and the web GUI back on .2 only" at2; chk "B: the export after" export_eq
  chk "B: the firewall's own log" sh -c "$FW2 'cat /tmp/seed-cutover-fw.log' | tail -3 | tr '\n' ' '"
  STEP=end; log "REHEARSAL" "$([[ $FAILS == 0 ]] && echo ok || echo FAIL)" "$FAILS check(s) failed"; FINISHED=1; exit $(( FAILS > 0 ))
fi

# --- step 0: the preconditions (the whole dry run) ---
STEP=0; log "rung 6 phase 3 cut-over" INFO "mode $MODE, $(hostname), limits: unplug ${T_UNPLUG}s, recable ${T_RECABLE}s, gateway ${T_GW}s"
for c in bw jq host nc python3 ssh setsid systemctl find; do chk "tool $c" command -v $c; done
chk "the wifi test unit (seed-wifi-test@cutover)" systemctl cat seed-wifi-test@cutover.service
chk "the wifi card in the main namespace" sh -c 'ls /sys/class/ieee80211 | head -1 | grep .'
chk "the router at 192.168.1.1" $RT1 true
chk "the router's eth0 has carrier (the upstream still in)" router_carrier "$RT1" 1
# config-tool --ap reloads the router detached (the session drops when the address moves); busybox has no nohup, and
# that sank the first window (20260929). A process started the same way must outlive its ssh session.
chk "the router runs a detached process after its session ends (setsid)" detach_ok
chk "the router = rung 5 (config-tool check)" site/router/config-tool check --rung5
chk "the access point renders (apply --dry-run --ap): the WAN disabled, 4 packages" ap_renders
chk "192.168.1.4 free" nothing_at 192.168.1.4
chk "known_hosts: 192.168.1.4 is the router's key" sh -c '[ "$(ssh-keygen -F 192.168.1.1 | grep -v "^#" | cut -d" " -f2-)" = "$(ssh-keygen -F 192.168.1.4 | grep -v "^#" | cut -d" " -f2-)" ] && echo same'
chk "the firewall at 192.168.1.2" $FW2 true
chk "the firewall: LAN .2, Kea opt1,opt2" fw_is "$FW2" "re1 192.168.1.2 Kea opt1,opt2"
chk "the firewall runs a detached process after its session ends (daemon -f)" fw_detach_ok
chk "the firewall's cut-over script (check)" $FW2 'sh -s check' < site/firewall/seed-cutover-fw
chk "the firewall's WAN: a gateway configured (boolean), its monitoring off, IPv6 and blockpriv off" $FW2 'php' <<'EOF'
<?php require_once 'config.inc'; $c = OPNsense\Core\Config::getInstance()->object(); $w = $c->interfaces->wan; $gw = 0;
$mon = 0; foreach ($c->xpath('//gateway_item') as $g) if ((string)$g->interface == 'wan') { $gw++; if ((string)$g->monitor_disable != '1') $mon++; }
$ok = $gw > 0 && $mon == 0 && empty((string)$w->blockpriv) && empty((string)$w->ipaddrv6);
echo ($ok ? "yes" : "no"), " (gateways on the WAN: ", $gw > 0 ? "present" : "none", "; monitored: ", $mon, ")\n"; exit($ok ? 0 : 1);
EOF
chk "the firewall's re0: no carrier yet" sh -c "$FW2 'ifconfig re0' | grep -q 'status: no carrier' && echo 'no carrier'"
chk "the firewall's export = site/firewall/config.expected.xml" sh -c "$FW2 /usr/local/sbin/seed-config-export | diff -q - site/firewall/config.expected.xml >/dev/null && echo equal"
chk "core: sudo for the DHCP discover" $CORE 'sudo -n true && echo yes'
chk "one DHCP server now, the router" dhcp_one 192.168.1.1 $ROUTERMAC
for h in 192.168.1.10 192.168.1.12 192.168.1.15 192.168.1.16; do chk "$h answers" answers $h; done
for d in 192.168.1.15 192.168.1.16; do chk "DNS at $d" dns_ok $d; done
chk "the log is world-readable" sh -c "stat -c %A $LOG | grep -q '^-rw-r--r--' && echo yes"
log "the internet now" INFO "$(curl -s -o /dev/null -m 5 -w '%{http_code}' https://example.com/)"
if [[ $MODE == dry ]]; then
  log "DRY RUN" "$([[ $FAILS == 0 ]] && echo ok || echo FAIL)" "$FAILS precondition(s) failed; nothing was changed"; FINISHED=1; exit $(( FAILS > 0 ))
fi
(( FAILS == 0 )) || fail "$FAILS precondition(s) failed"
o=$(tools/router-backup.sh 2>&1); rc=$?; echo "$o" | rec
[[ $rc == 0 ]] && log "the router's backup (tools/router-backup.sh)" ok "$(head -1 <<<"$o" | cut -d' ' -f1)" || fail "the router's backup failed"

# --- step 1: the owner unplugs the upstream from the router ---
STEP=1; log "OWNER, now: unplug the upstream cable from the router's 2.5G port (eth0)" WAIT ""
wait_for "the router's eth0: no carrier" $T_UNPLUG router_carrier "$RT1" 0 || fail "the upstream cable wasn't unplugged in time"
sleep 5; chk "the router's eth0: still no carrier (5 s later)" router_carrier "$RT1" 0 || fail "the router's eth0 carrier came back"
log "t0: the internet is down from here" INFO ""

# --- step 2: the router becomes the access point ---
STEP=2; STEP_REACHED=2; AP_DONE=1   # from here the way back puts the router back (if it's at .4)
ROUTER=192.168.1.1 site/router/config-tool apply --ap > >(rec) 2>&1; rc=$?; sleep 1
if [[ $rc != 0 ]]; then
  log "config-tool apply --ap" FAIL "rc $rc; the router's own rollback restores rung 5 within 120 s"
  wait_for "the router back at 192.168.1.1 (its rollback, due within 180 s of the import)" 240 $RT1 true && AP_DONE=0
  fail "the access point apply didn't confirm"; fi
chkr 30 "the access point at 192.168.1.4 (config-tool apply --ap confirmed)" $RT4 true || fail "the access point doesn't answer"
chkr 30 "the access point: nothing on :53 or :67" ap_quiet || fail "the access point still serves DNS or DHCP"
chkr 60 "the access point = config.ap (config-tool check --ap)" env ROUTER=192.168.1.4 site/router/config-tool check --ap || fail "the access point differs from config.ap"
chkr 30 "192.168.1.1 free" one_free || fail "something still answers at 192.168.1.1"

# --- step 3: the firewall takes the gateway ---
STEP=3
log "OWNER: please wait for the recabling line (step 4); the firewall is moving" INFO ""
fw_move 192.168.1.1 lan,opt1,opt2 1 1 || fail "the firewall's move to 192.168.1.1"

# --- step 4: the owner recables ---
STEP=4; log "OWNER, now: the firewall's LAN cable into the router's eth0; the upstream cable into the firewall's WAN port (re0)" WAIT ""
wait_for "recabled: carrier on the firewall's re0 and the router's eth0" $T_RECABLE recabled || fail "the recabling wasn't seen in time"
RECABLED=1
log "the router's eth0 speed" INFO "$($RT4 'cat /sys/class/net/eth0/speed') Mb/s (2500 expected)"
wait_for "the WAN gateway's port 53 answers a TCP connection from re0" $T_GW gw_answers || { log "the WAN, for the record" INFO "$(fw_wan)"; fail "the WAN gateway's port 53 doesn't answer the firewall"; }
log "the WAN gateway's ping (information only: the upstream blocks it)" INFO "$(fw_wan | sed 's/.*; ping //')"

# --- step 5: the offline checks ---
STEP=5
for h in 192.168.1.1 192.168.1.4 192.168.1.10 192.168.1.12 192.168.1.15 192.168.1.16; do chkr 30 "$h answers" answers $h; done
for d in 192.168.1.15 192.168.1.16; do chkr 30 "DNS at $d" dns_ok $d; done
chkr 30 "the firewall: LAN .1, Kea lan,opt1,opt2" fw_is "$FW1" "re1 192.168.1.1 Kea lan,opt1,opt2"
chkr 30 "the access point: nothing on :53 or :67" ap_quiet
chkr 60 "the access point = config.ap" env ROUTER=192.168.1.4 site/router/config-tool check --ap
chkr 30 "one DHCP server, the firewall" dhcp_one 192.168.1.1 $FWMAC
chk "the wifi test (seed-wifi-test@cutover), offline rows" wifi_cutover
(( FAILS == 0 )) || fail "$FAILS check(s) failed after the recabling"
log "the offline checks" ok "all passed"

# --- step 6: the internet (information only: the upstream's ARP refresh is the owner's step 5) ---
STEP=6
wait_for "the internet from the agent box (https://example.com)" $T_NET curl -s -o /dev/null -m 5 https://example.com/ \
  || { FAILS=$((FAILS-1)); log "the internet" INFO "not yet: the upstream's ARP refresh (the owner's step 5); no way back for this"; }
log "DONE" ok "the cut-over's offline part passed; the builder rejoins, reads this log and runs the remaining checks"
FINISHED=1
