#!/usr/bin/env bash
# fw-wan-admin-block.sh: the firewall's own ssh and web (22, 80, 443) refused from its WAN side (F-FW-GUI-WAN; the
# orchestrator's decision under the Seed authority, 20261002). One rule on WAN, ahead of the lab's fixture rules
# (sequence 50, 51), which stay exactly as they are: the second remains the lab's bridge to the LAN. The GUI and ssh
# are reached from the Seed LAN, its wifi, or through the agent box (ssh -J agent@agent-box root@192.168.1.1).
#   1. checks before: the GUI and ssh answer from the LAN; no such rule or alias yet; the fixture rules' hash
#   2. the way back, armed on the firewall (26.7's filter API has no rollback): /conf/config.xml copied for this run,
#      and a detached watchdog restores it and reloads the filter unless this run's confirm file appears within WIN s
#   3. the change through OPNsense's API: alias seed_fw_admin_ports (22, 80, 443), the rule (reject: a refusal, not
#      a silent drop), the filter applied; every answer checked
#   4. checks after: the rule as meant (read back), in pf as a block-return, the fixtures unchanged (hash), the GUI
#      and ssh from the LAN, the jump through the agent box; all pass and the window still open -> confirm
# A fresh connection from the WAN side can't be made from here (its addresses are outside the builder's ranges):
# that probe is the orchestrator's or the owner's. Nothing of the WAN's or the lab's values is read or printed.
set -euo pipefail; set +x
R=${SEED_REPO:-/work/agent/seed-lab}; FW=192.168.1.1; export FW; WIN=600; id=$(date -u +%Y%m%dT%H%M%SZ)
exec 8>/tmp/reh/fw-change.lock; flock -n 8 || { echo "another firewall change is running"; exit 1; }
S=(timeout 30 ssh -o BatchMode=yes -o LogLevel=ERROR -o ConnectTimeout=10 root@$FW)
api() { timeout 60 flock /tmp/reh/bw.lock "$R/tools/fw-api.sh" "$@"; }
rules() { api POST firewall/filter/search_rule '{"current":1,"rowCount":5000}' | jq -e 'if (.rows|length)==.total then . else error("search_rule: not every row") end'; }
aliases() { api POST firewall/alias/search_item '{"current":1,"rowCount":5000}' | jq -e 'if (.rows|length)==.total then . else error("search_item: not every row") end'; }
fixhash() { rules | jq -ce '[.rows[]|select(.description|startswith("fixture:"))]|sort_by(.uuid)|if length==2 then . else error("not the two fixture rules") end' | sha256sum | cut -c1-16; }
gui() { curl -sk -o /dev/null -m 10 -w '%{http_code}' https://$FW/; }
ok() { echo "ok   $*"; }; bad() { echo "FAIL $*"; fail=1; }
fail=0; t0=$(date +%s)
# 1.
c=$(gui); case $c in 200|302|303|403) ok "GUI from the LAN before: $c";; *) echo "the GUI doesn't answer from the LAN ($c): not starting"; exit 1;; esac
"${S[@]}" "sh -c true" && ok "ssh from the LAN before" || { echo "no ssh to the firewall: not starting"; exit 1; }
rules | jq -e '[.rows[]|select(.description|startswith("seed: no admin"))]|length==0' >/dev/null || { echo "the rule exists already"; exit 1; }
aliases | jq -e '[.rows[]|select(.name=="seed_fw_admin_ports")]|length==0' >/dev/null || { echo "the alias exists already"; exit 1; }
[ "$("${S[@]}" "sh -c 'ls /tmp/seed-wanadmin-*.armed 2>/dev/null | wc -l'" | tr -d ' ')" = 0 ] || { echo "an earlier run's way back is still pending on the firewall: wait for it"; exit 1; }
fh=$(fixhash) || { echo "the fixture rules couldn't be read: not starting"; exit 1; }; ok "the fixture rules (2) hashed before: $fh"
# 2.
B=/conf/seed-before-wanadmin-$id.xml; A=/tmp/seed-wanadmin-$id.armed; C=/tmp/seed-wanadmin-$id.confirmed; L=/tmp/seed-wanadmin.log
armed=$("${S[@]}" "sh -c 'cp -p /conf/config.xml $B && daemon -f sh -c \"sleep $WIN; if [ -e $C ]; then echo \\\$(date -u +%FT%TZ) $id confirmed >> $L; elif cp -p $B /conf/config.xml && configctl filter reload >/dev/null; then echo \\\$(date -u +%FT%TZ) $id ROLLED BACK >> $L; else echo \\\$(date -u +%FT%TZ) $id ROLLBACK FAILED >> $L; fi; rm -f $A\" && touch $A && echo armed'" || true)
[ "$armed" = armed ] || { echo "the way back could not be armed: nothing changed"; exit 1; }; ok "the way back armed ($WIN s, run $id)"
# 3.
api POST firewall/alias/add_item '{"alias":{"enabled":"1","name":"seed_fw_admin_ports","type":"port","content":"22\n80\n443","description":"seed: the firewall'"'"'s own ssh and web (F-FW-GUI-WAN)"}}' | jq -e '.result=="saved"' >/dev/null || { bad "alias not saved"; }
api POST firewall/alias/reconfigure '{}' | jq -e '.status=="ok"' >/dev/null || bad "alias reconfigure"
[ $fail = 0 ] && { api POST firewall/filter/add_rule '{"rule":{"enabled":"1","sequence":"40","action":"reject","quick":"1","interface":"wan","direction":"in","ipprotocol":"inet46","protocol":"TCP","source_net":"any","destination_net":"(self)","destination_port":"seed_fw_admin_ports","log":"1","description":"seed: no admin (ssh, web) on the firewall from its WAN side, ahead of the fixtures (F-FW-GUI-WAN)"}}' | jq -e '.result=="saved"' >/dev/null || bad "rule not saved"; }
[ $fail = 0 ] && { api POST firewall/filter/apply '{}' | jq -e '.status|tostring|test("^\\s*OK\\s*$")' >/dev/null || bad "filter apply"; }
# 4.
aliases | jq -e '[.rows[]|select(.name=="seed_fw_admin_ports")] | length==1 and (.[0].content|tostring|[splits("[\\s,]+")]|map(select(length>0))|sort)==["22","443","80"]' >/dev/null && ok "the alias: 22, 80, 443" || bad "the alias's ports"
r=$(rules | jq -c '[.rows[]|select(.description|startswith("seed: no admin"))]'); uuid=$(jq -r '.[0].uuid // empty' <<<"$r")
jq -e 'length==1 and (.[0]|.enabled=="1" and .action=="reject" and .interface=="wan" and .direction=="in" and .quick=="1" and .ipprotocol=="inet46" and .protocol=="TCP" and .source_net=="any" and .destination_net=="(self)" and .destination_port=="seed_fw_admin_ports" and (.sequence|tonumber)<50)' <<<"$r" >/dev/null \
  && ok "the rule as meant (reject TCP on WAN to the firewall's own 22/80/443, sequence 40, before 50 and 51)" || bad "the rule isn't as meant"
[ "$(fixhash)" = "$fh" ] && ok "the fixture rules unchanged" || bad "the fixture rules changed"
[ -n "$uuid" ] && { pf=$("${S[@]}" "sh -c 'pfctl -sr 2>/dev/null | grep \"$uuid\"'" || true); n=$(printf '%s\n' "$pf" | grep -c . || true); m=$(printf '%s\n' "$pf" | grep -cE "^block return in .*quick .*proto tcp" || true)
  [ "$n" -ge 1 ] && [ "$n" = "$m" ] && ok "in pf: $n line(s) by its id, every one block return in, quick, proto tcp" || bad "pf: $m of $n lines a block-return"; }
c=$(gui); case $c in 200|302|303|403) ok "GUI from the LAN after: $c";; *) bad "GUI from the LAN after: $c";; esac
"${S[@]}" "sh -c true" && ok "ssh from the LAN after" || bad "ssh from the LAN after"
# the jump's second hop (ssh -J agent@agent-box root@fw lands here, then this): run on the agent box itself
[ "$(hostname)" = agent ] && ok "the jump's hop, agent box -> firewall (the ssh above, from the agent box)" || bad "not on the agent box: the jump's hop unchecked"
el=$(( $(date +%s) - t0 ))
if [ $fail = 0 ] && [ $el -lt $((WIN - 30)) ]; then
  "${S[@]}" "sh -c '[ -e $A ] && touch $C && [ -e $A ] && echo confirmed'" | grep -q confirmed && ok "confirmed after $el s: the watchdog keeps it" || { echo "the window had closed: rolled back"; exit 1; }
else echo "NOT confirmed (failures, or $el s too close to the window): the watchdog restores the configuration"; exit 1; fi
