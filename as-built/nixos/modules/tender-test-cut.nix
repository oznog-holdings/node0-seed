# The Tender test's stage 3 (the dependency blocks): one narrow root helper, for the test window only (the
# NOT IMPORTED since the re-runs' restore (20261006): import it in hosts/agent for a dependency block only.
# orchestrator, 20261004; removed at restore). It takes away ONE of three named dependencies from the tender uid alone,
# on this box alone, and puts it back by itself:
#   3a  the model API (api.anthropic.com)                          40 min
#   3b  the second opinion (OpenAI: api.openai.com, chatgpt.com, auth.openai.com)   60 min
#   3c  the whole internet, except the site's own ranges           40 min
# Each cut is a chain (TT_3a, TT_3b, TT_3c) in iptables and ip6tables, jumped from OUTPUT for `-m owner --uid-owner
# tender` only. Its removal timer (a transient systemd timer) is armed BEFORE the chain is added. `prove <c>` is the
# same cut with a 2-minute timer (for its proofs). `remove <c>` takes a chain away now; the timer, when it fires, finds
# it gone and logs that. A boot clears it (not persistent); a firewall reload does NOT (Codex, 20261004), so the test's
# restore runs `remove` for all three and checks `status`. Add and remove are serialized (a lock): a removal that fires
# while an add is under way waits for it, then removes. A removal that cannot verify the chain gone fails, and its
# unit retries every 30 s.
# The builder (agent) may run exactly: add|prove|remove 3a|3b|3c, and status. Anything else is refused by sudo.
{ pkgs, lib, ... }:
let
  cut = pkgs.writeShellScriptBin "tender-test-cut" ''
    set -euo pipefail
    export PATH=${lib.makeBinPath [ pkgs.iptables pkgs.systemd pkgs.coreutils pkgs.gnugrep pkgs.gnused pkgs.dnsutils pkgs.gawk pkgs.util-linux ]}
    L=/var/log/tender-test-cut.log
    log() { echo "$(date -u +%FT%TZ) $*" | tee -a $L; }
    [ "$(id -u)" = 0 ] || { echo "root only" >&2; exit 1; }
    [ $# -ge 1 ] && [ $# -le 2 ] || { echo "usage: add|prove|remove 3a|3b|3c, or status" >&2; exit 64; }
    U=$(id -u tender)
    exec 9>/run/tender-test-cut.lock; flock 9   # add and remove one at a time
    # a name's addresses, or a refusal: the answer must be NOERROR (an empty answer is fine only for AAAA)
    res() { local t=$1 h=$2 o; o=$(dig +time=3 +tries=2 "$t" "$h") || return 1; echo "$o" | grep -q 'status: NOERROR' || return 1
            echo "$o" | awk -v t=$t '$4 == t {print $5}'; }
    jumps() { $1 -S OUTPUT 2>/dev/null | grep -- "-j TT_$2\$" | sed 's/^-A /-D /' || true; }
    present() { iptables -S TT_$1 >/dev/null 2>&1 || ip6tables -S TT_$1 >/dev/null 2>&1 || [ -n "$(jumps iptables $1)$(jumps ip6tables $1)" ]; }
    gone() {   # each family on its own; then verified, or a failure (the timer's unit retries)
      set +e
      for ipt in iptables ip6tables; do
        jumps $ipt $1 | while read -r spec; do $ipt $spec; done
        $ipt -F TT_$1 2>/dev/null; $ipt -X TT_$1 2>/dev/null
      done
      set -e
      ! present $1 || { log "$1: NOT fully removed: failing, to be retried"; exit 1; }; }
    case "''${1:-}:''${2:-}" in
      add:3a|add:3b|add:3c|prove:3a|prove:3b|prove:3c)
        c=$2; case $1:$c in add:3a) m=40;; add:3b) m=60;; add:3c) m=40;; prove:*) m=2;; esac
        present $c && { log "$c: already in place: refused"; exit 1; }
        systemctl is-active -q tender-test-cut-$c.timer && { log "$c: its timer is still pending: refused"; exit 1; }
        # the way back first: the removal timer armed before the chain exists
        # the addresses first: a name that does not resolve (NOERROR with an A record) refuses the cut
        A4=""; A6=""
        case $c in 3a) H="api.anthropic.com";; 3b) H="api.openai.com chatgpt.com auth.openai.com";; 3c) H="";; esac
        for h in $H; do
          a=$(res A $h) && [ -n "$a" ] || { log "$c: $h did not resolve (A): refused"; exit 1; }
          b=$(res AAAA $h) || { log "$c: $h did not resolve (AAAA): refused"; exit 1; }
          A4="$A4 $a"; A6="$A6 $b"
        done
        # an absolute deadline (UTC): a system manager reload re-bases a relative --on-active timer (3b ran 75 min
        # of 60, 3a 51 of 40, 20261004: the pull-deploy reloaded every 15 minutes)
        dl=$(date -u -d "+$m min" '+%Y-%m-%d %H:%M:%S UTC')
        systemd-run -q --unit tender-test-cut-$c --on-calendar="$dl" --timer-property=AccuracySec=1s -p Restart=on-failure -p RestartSec=30 \
          ${placeholder "out"}/bin/tender-test-cut remove $c
        # the timer must have a firing still ahead (a deadline already past would never fire): else no cut at all
        nx=$(systemctl show tender-test-cut-$c.timer -p NextElapseUSecRealtime --value)
        if [ -z "$nx" ] || [ "$(date -d "$nx" +%s 2>/dev/null || echo 0)" -le "$(date +%s)" ]; then
          systemctl stop tender-test-cut-$c.timer 2>/dev/null || true; log "$c: its removal timer has no firing ahead ($nx): refused"; exit 1
        fi
        for ipt in iptables ip6tables; do $ipt -N TT_$c; done
        case $c in
          3a|3b) for a in $A4; do iptables -A TT_$c -d $a -j REJECT; done; for a in $A6; do ip6tables -A TT_$c -d $a -j REJECT; done ;;
          3c) for n in 127.0.0.0/8 192.168.1.0/24 192.168.20.0/24 192.168.30.0/24 192.168.122.0/24 100.64.0.0/10; do iptables -A TT_3c -d $n -j RETURN; done
              iptables -A TT_3c -j REJECT
              for n in ::1/128 fe80::/10 fd00:0:0::/48; do ip6tables -A TT_3c -d $n -j RETURN; done
              ip6tables -A TT_3c -j REJECT ;;
        esac
        for ipt in iptables ip6tables; do $ipt -I OUTPUT -m owner --uid-owner $U -j TT_$c; done
        log "$c: added for $m min, until $dl (tender uid $U only): $(iptables -S TT_$c | grep -c REJECT) v4 + $(ip6tables -S TT_$c | grep -c REJECT) v6 reject rules; the timer armed first" ;;
      remove:3a|remove:3b|remove:3c)
        if present $2; then gone $2; log "$2: removed (verified)"; else log "$2: already gone: nothing to remove"; fi ;;
      status:)
        for c in 3a 3b 3c; do echo "$c: $(present $c && echo IN PLACE || echo absent); timer $(systemctl is-active tender-test-cut-$c.timer 2>/dev/null || true)"; done ;;
      *) echo "refused: only add|prove|remove 3a|3b|3c, or status" >&2; exit 64 ;;
    esac
  '';
  bin = "/run/current-system/sw/bin/tender-test-cut";
in {
  environment.systemPackages = [ cut ];
  # a harmless real change, for the proof that a cut's absolute timer fires on time through a switch (20261004)
  environment.etc."tender-test-cut/reload-proof".text = "a switch in the middle of a 2-minute cut, 20261004\n";
  security.sudo.extraRules = [{
    users = [ "agent" ];
    commands = map (a: { command = "${bin} ${a}"; options = [ "NOPASSWD" ]; })
      [ "add 3a" "add 3b" "add 3c" "prove 3a" "prove 3b" "prove 3c" "remove 3a" "remove 3b" "remove 3c" "status" ];
  }];
}
