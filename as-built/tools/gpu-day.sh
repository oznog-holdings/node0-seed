#!/usr/bin/env bash
# gpu-day.sh: the GPU day's switches (the orchestrator, 20261006): Hermes on Qwen3.8-27B (Unsloth UD-Q4_K_XL) served by
# llama-server on the tailnet node `gpu-test` (tag:gpu-test, ephemeral; infra may reach its :8080, it reaches nothing),
# through the site's gateway as the route `gpu-chat`. From the builder's account on the agent box. Nothing here runs by
# itself; each subcommand is one step, and says what it found.
#   status            the vault item, the node on the tailnet, the route deployed, the keys, Hermes's model
#   check             the node answers from infra (llama-server's /health, then /v1/models with the key): before route-on
#   route-on          the route deployed (site/bin/deploy-infra-config: spliced in only while the vault item "gpu-test
#                     model key" exists and gpu-test is on the tailnet), gpu-chat added to the keys tender and
#                     monitoring-probe, then one real completion through the gateway from infra (1 token, thinking off)
#   hermes-gpu <ctx>  Hermes's config for the GPU, rendered from the Mac's (nixos/modules/site-agents/hermes-config.yaml)
#                     into ~tender/.hermes/config.yaml: model gpu-chat, context <ctx> (the served one: 131072 or 81920),
#                     compression at 0.65 of it, timeouts for ~40 tok/s, thinking as before. Hermes's gateway restarted to
#                     load it; Hermes stays paused by its marker (its jobs don't run) until its block
#   hermes-mac        back to the Mac's config (tender-config reinstalls it), Hermes's gateway restarted, still paused
#   route-off         gpu-chat taken out of both keys, the route undeployed (deploy-infra-config, once the switch is off
#                     or the vault item gone)
# The switch (20261012): site/infra/litellm/gpu-chat.switch, "on" or "off". route-on needs it on; with it off the route
# and its key are never deployed, and the vault items, the ACL lines and gpu-chat.yaml stay for the next time
# (site/runbooks/gpu-agent-on-off.md). teardown is the full removal and needs the owner's word.
#   model-cut add <min>|remove|status   block 34's cut 3m: gpu-chat out of tender's gateway key, its revert timer armed
#                     first (absolute deadline, as the root cut helper's); logged to tender-test-private/gpu-model-cut.log
#   teardown          hermes-mac, the vault item deleted, route-off; then prints what's left for the orchestrator (the
#                     flag back to claude by his root file, the ACL lines he removes live)
set -euo pipefail
cd "$(dirname "$0")/.."
INFRA="ssh -o BatchMode=yes root@192.168.1.10"; T="ssh -o BatchMode=yes tender@localhost"
log() { echo "$(date -u +%FT%TZ) $*"; }
gip() { $INFRA "tailscale status --json" | jq -r '[.Peer[] | select(.HostName=="gpu-test") | .TailscaleIPs[0]] | first // empty'; }
vault_item() {  # prints the item's id, or nothing (the key itself is never printed)
  ( . tools/vault-env.sh; BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null); export BW_SESSION; unset BW_PASSWORD BW_CLIENTSECRET
    bw sync >/dev/null; bw list items --search 'gpu-test model key' | jq -r '[.[] | select(.name=="gpu-test model key")] | if length==1 then .[0].id else "" end'
    bw lock >/dev/null 2>&1 ); }
# the gateway's admin API on infra, with its master key read there (by reference, never printed)
gwadm() { $INFRA "MK=\$(sed -n 's/^LITELLM_MASTER_KEY=//p' /mnt/data/system/secrets/litellm.env); curl -s -m 30 -K <(printf 'header = \"Authorization: Bearer %s\"\n' \"\$MK\") -H 'Content-Type: application/json' $1"; }
key_models() { gwadm "'http://127.0.0.1:4000/key/list?key_alias=$1&return_full_object=true'" | jq -c '.keys[0].models'; }
key_set_models() {  # alias, jq expression on the models list
  local tok; tok=$(gwadm "'http://127.0.0.1:4000/key/list?key_alias=$1&return_full_object=true'" | jq -r '.keys[0].token')
  local m; m=$(key_models "$1" | jq -c "$2")
  gwadm "-X POST --data-binary '$(jq -nc --arg k "$tok" --argjson m "$m" '{key: $k, models: $m}')' http://127.0.0.1:4000/key/update" | jq -c '{alias: .key_alias, models: .models}'; }
# LiteLLM reads its --env-file only at creation: recreated through Unraid's own Apply (as rotate-compute-llama-key.sh)
recreate() { local i; tools/ui/run.sh edit-container.js litellm >/dev/null 2>&1 || { log "the gateway's recreation failed"; exit 1; }
  for i in $(seq 1 30); do [ "$($INFRA "curl -s -m 5 -o /dev/null -w '%{http_code}' http://127.0.0.1:4000/health/liveliness")" = 200 ] && { log "the gateway recreated, healthy"; return 0; }; sleep 5; done
  log "the gateway recreated but NOT healthy after 150 s: stopped"; exit 1; }
gwenv() { $INFRA "docker exec litellm sh -c 'test -n \"\$$1\" && echo set || echo unset'"; }   # presence only, never the value
hermes_model() { $T "grep -m1 '^  default:' ~/.hermes/config.yaml; grep -m1 '^  context_length:' ~/.hermes/config.yaml" | tr -s ' ' | tr '\n' ' '; }

# the switch's value: its last line that isn't empty or a comment, trimmed (as site/bin/deploy-infra-config reads it)
switch() { awk '{ sub(/#.*/, ""); gsub(/^[ \t]+|[ \t]+$/, ""); if ($0 != "") v = $0 } END { print v }' site/infra/litellm/gpu-chat.switch; }

case ${1:-} in
status)
  log "the switch (site/infra/litellm/gpu-chat.switch): $(switch)"
  log "vault item 'gpu-test model key': $([ -n "$(vault_item)" ] && echo present || echo absent)"
  log "gpu-test on the tailnet: $(ip=$(gip); [ -n "$ip" ] && echo "yes ($ip)" || echo no)"
  log "the route deployed: $($INFRA "grep -c 'model_name: gpu-chat' /mnt/data/appdata/litellm/config.yaml" || true)"
  for k in tender monitoring-probe; do log "key $k: $(key_models $k)"; done
  log "Hermes: $(hermes_model); paused marker: $($T 'test -e ~/.config/site-agents/paused/hermes && echo yes || echo no')" ;;
check)
  ip=$(gip); [ -n "$ip" ] || { log "gpu-test is not on the tailnet"; exit 1; }
  log "gpu-test at $ip; /health from infra: $($INFRA "curl -s -m 10 -o /dev/null -w '%{http_code}' http://$ip:8080/health" || true)"
  [ -n "$(vault_item)" ] || { log "no vault item yet: /v1/models not tried"; exit 1; }
  # /v1/models with the key: the key from the vault to infra over ssh's stdin, never on an argument
  ( . tools/vault-env.sh; BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null); export BW_SESSION; unset BW_PASSWORD BW_CLIENTSECRET
    bw get password 'gpu-test model key' | $INFRA "IFS= read -r K; curl -s -m 20 -K <(printf 'header = \"Authorization: Bearer %s\"\n' \"\$K\") http://$ip:8080/v1/models" | jq -r '"models served: \([.data[]?.id] | join(", "))"'
    bw lock >/dev/null 2>&1 ) ;;
route-on)
  [ "$(switch)" = on ] || { log "the switch is $(switch): set it on in site/infra/litellm/gpu-chat.switch first (the runbook)"; exit 1; }
  [ -n "$(vault_item)" ] || { log "no vault item 'gpu-test model key': nothing enabled"; exit 1; }
  [ -n "$(gip)" ] || { log "gpu-test is not on the tailnet: nothing enabled"; exit 1; }
  out=$(cd site && bin/deploy-infra-config 2>&1) || { echo "$out" | tail -5; log "deploy-infra-config failed: stopped"; exit 1; }
  echo "$out" | grep -E 'gpu-chat|litellm'
  [ "$($INFRA "grep -c 'model_name: gpu-chat' /mnt/data/appdata/litellm/config.yaml" || true)" = 1 ] || { log "the route isn't in the deployed config: stopped"; exit 1; }
  recreate; [ "$(gwenv GPU_TEST_API_KEY)" = set ] || { log "the gateway has no GPU_TEST_API_KEY after its recreation: stopped"; exit 1; }
  for k in tender monitoring-probe; do key_set_models $k '(. + ["gpu-chat"]) | unique' >/dev/null
    key_models $k | jq -e 'index("gpu-chat")' >/dev/null || { log "key $k: gpu-chat NOT added: stopped"; exit 1; }; log "key $k: $(key_models $k)"; done
  code=$($INFRA "GWK=\$(sed -n 's/^GATEWAY_PROBE_KEY=//p' /mnt/data/system/secrets/monitoring-probe.env); printf '%s' '{\"model\":\"gpu-chat\",\"messages\":[{\"role\":\"user\",\"content\":\"ok\"}],\"max_tokens\":1,\"chat_template_kwargs\":{\"enable_thinking\":false}}' | curl -s -m 120 -o /dev/null -w '%{http_code}' -K <(printf 'header = \"Authorization: Bearer %s\"\n' \"\$GWK\") -H 'Content-Type: application/json' --data-binary @- http://127.0.0.1:4000/v1/chat/completions")
  log "a completion through the gateway (probe key, 1 token, thinking off): HTTP $code"; [ "$code" = 200 ] || exit 1 ;;
hermes-gpu)
  ctx=${2:?the served context: 131072 or 81920}; [[ $ctx =~ ^[0-9]+$ ]] || { echo "ctx: a number"; exit 64; }
  th=$(( ctx * 65 / 100 ))
  python3 - nixos/modules/site-agents/hermes-config.yaml "$ctx" "$th" > /tmp/claude-hermes-gpu.$$ <<'PY'
import re, sys
src, ctx, th = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
s = open(src).read()
R = [('  default: "local-chat"', '  default: "gpu-chat"'),
     ('  context_length: 131072          # the served context (evidence/20260930-qwen38): one slot, f16 KV, no YaRN',
      f'  context_length: {ctx}          # the GPU day (20261006): gpu-test\'s served context'),
     ('    context_length: 131072\n    models: ["local-chat"]', f'    context_length: {ctx}\n    models: ["gpu-chat"]'),
     ('    stale_timeout_seconds: 2700\n    request_timeout_seconds: 3600', '    stale_timeout_seconds: 300   # the GPU day: ~40 tok/s and a fast prefill\n    request_timeout_seconds: 900'),
     ('  gateway_timeout: 3600           # a turn waiting on a cold prefill is not idle', '  gateway_timeout: 900            # the GPU day'),
     ('  context_timeout_seconds: 2700\n  context_total_ceiling_seconds: 3000\n  hygiene_total_ceiling_seconds: 3000',
      '  context_timeout_seconds: 600    # the GPU day: a compression in minutes, not ~18\n  context_total_ceiling_seconds: 900\n  hygiene_total_ceiling_seconds: 900'),
     ('  compression: { provider: "main", timeout: 2700,', '  compression: { provider: "main", timeout: 600,')]
for a, b in R:
    assert s.count(a) == 1, a[:50]
    s = s.replace(a, b)
s, n = re.subn(r'(?m)^  threshold_tokens: \d+', f'  threshold_tokens: {th}', s); assert n == 1
s = '# THE GPU DAY (20261006): rendered by tools/gpu-day.sh hermes-gpu from hermes-config.yaml; hermes-mac restores the Mac\'s.\n' + s
print(s, end='')
PY
  $T "umask 077; cat > ~/.hermes/config.yaml.gpu && mv ~/.hermes/config.yaml.gpu ~/.hermes/config.yaml" < /tmp/claude-hermes-gpu.$$; rm -f /tmp/claude-hermes-gpu.$$
  [ "${3:-}" = --no-restart ] || $T "systemctl --user restart tender-hermes; systemctl --user is-active tender-hermes"
  log "Hermes: $(hermes_model) threshold_tokens $th (0.65 of $ctx); paused marker: $($T 'test -e ~/.config/site-agents/paused/hermes && echo kept || echo ABSENT')" ;;
hermes-mac)
  $T "systemctl --user restart tender-config; systemctl --user restart tender-hermes; systemctl --user is-active tender-hermes"
  log "Hermes: $(hermes_model); paused marker: $($T 'test -e ~/.config/site-agents/paused/hermes && echo kept || echo ABSENT')" ;;
route-off)
  for k in tender monitoring-probe; do log "key $k: $(key_set_models $k 'map(select(. != "gpu-chat"))')"; done
  if [ "$(switch)" = off ] || [ -z "$(vault_item)" ]; then out=$(cd site && bin/deploy-infra-config 2>&1) || { echo "$out" | tail -5; log "deploy-infra-config failed"; exit 1; }
    echo "$out" | grep -E 'gpu-chat|litellm'; recreate; log "the gateway's GPU_TEST_API_KEY: $(gwenv GPU_TEST_API_KEY)"
  else log "the switch is on and the vault item exists: the route stays deployed (set the switch off first)"; fi
  log "the route deployed: $($INFRA "grep -c 'model_name: gpu-chat' /mnt/data/appdata/litellm/config.yaml" || true)" ;;
teardown)
  "$0" hermes-mac
  id=$(vault_item)
  if [ -n "$id" ]; then
    ( . tools/vault-env.sh; BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null); export BW_SESSION; unset BW_PASSWORD BW_CLIENTSECRET
      bw delete item "$id" && echo "vault item 'gpu-test model key' deleted" || echo "COULD NOT delete the vault item: the owner's (admin collection)"
      bw lock >/dev/null 2>&1 )
  fi
  "$0" route-off
  $INFRA "rm -f /mnt/data/system/metrics/.state/inference.gpu-chat.last" && log "the probe's state for gpu-chat removed"
  echo "Left for the orchestrator: the active flag back to claude if it isn't (his root file), and the tailnet policy's"
  echo "gpu-test lines removed live (then site/tailnet/acl.hujson updated to match)." ;;
model-cut)   # block 34's cut "its model away" (3m): gpu-chat out of tender's key for <min> minutes, its revert armed first
  L=/work/agent/tender-test-private/gpu-model-cut.log; clog() { echo "$(date -u +%FT%TZ) $*" >> $L; echo "$(date -u +%FT%TZ) $*"; }
  case ${2:-} in
    add) m=${3:?minutes}; [[ $m =~ ^[0-9]+$ ]] || exit 64
         systemctl --user is-active -q gpu-model-cut-revert.timer && { clog "3m: its revert timer is still pending: refused"; exit 1; }
         dl=$(date -u -d "+$m min" '+%Y-%m-%d %H:%M:%S UTC')
         systemd-run --user -q --unit gpu-model-cut-revert --on-calendar="$dl" --timer-property=AccuracySec=1s \
           -p Restart=on-failure -p RestartSec=30 "$PWD/tools/gpu-day.sh" model-cut remove
         systemctl --user is-active -q gpu-model-cut-revert.timer || { clog "3m: the revert timer didn't arm: refused"; exit 1; }
         key_set_models tender 'map(select(. != "gpu-chat"))' >/dev/null
         if key_models tender | jq -e 'index("gpu-chat")' >/dev/null; then clog "3m: gpu-chat still in tender's key: the cut FAILED"; exit 1; fi
         clog "3m: added for $m min, until $dl (gpu-chat out of tender's gateway key; the probe's key keeps it); the timer armed first" ;;
    remove) key_set_models tender '(. + ["gpu-chat"]) | unique' >/dev/null
         if key_models tender | jq -e 'index("gpu-chat")' >/dev/null; then clog "3m: removed (verified: gpu-chat back in tender's key)"
         else clog "3m: removal NOT verified"; exit 1; fi
         systemctl --user stop gpu-model-cut-revert.timer 2>/dev/null || true ;;
    status) echo "3m: $(key_models tender | jq -e 'index("gpu-chat")' >/dev/null && echo absent || echo 'IN PLACE'); timer $(systemctl --user is-active gpu-model-cut-revert.timer 2>/dev/null || true)" ;;
    *) echo "model-cut add <min> | remove | status"; exit 64 ;;
  esac ;;
*) sed -n '2,25p' "$0"; exit 64 ;;
esac
