#!/usr/bin/env bash
# rotate-compute-llama-key.sh: a new compute llama API key (the key compute's router and encoder service answer, and the
# gateway sends: vault "compute llama api key"). First 20261002, after 15 of the old key's characters appeared in a
# session's output. The key never reaches a command line or a terminal: it is held in shell variables, sent by stdin
# or through file descriptors, and compared by hash.
#   1. the vault item gets a new 48-character password
#   2. compute: ~/.config/seed/llama.key replaced (the old one kept as llama.key.old, 0600, until the proofs pass), and
#      the inference service restarted (the router and encoders.py read the key at start)
#   3. the gateway: deploy-infra-config renders litellm.env from the vault; LiteLLM RECREATED through Unraid's own
#      Apply (tools/ui/run.sh edit-container.js litellm): --env-file is read at creation, a restart keeps the old key
#   4. proofs, all required: on compute the old key 401 and the new 200, on both ports; through the gateway local-embed
#      answers 200 with a vector
#   5. only then the old copy removed
# Any failure after the vault changed rolls everything back to the old key (vault, compute, the gateway) and stops.
set -Eeuo pipefail; set +x
R=${SEED_REPO:-/work/agent/seed-lab}; MAC=seed@192.168.1.20; NAME='compute llama api key'
h() { sha256sum | cut -c1-12; }
S() { ssh -o BatchMode=yes -o LogLevel=ERROR "$@"; }
exec 9>/tmp/reh/bw.lock; flock 9
. "$R/tools/vault-env.sh"
BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null); export BW_SESSION; unset BW_PASSWORD BW_CLIENTSECRET
bw sync >/dev/null
S $MAC '[ ! -e ~/.config/seed/llama.key.old ]' || { echo "llama.key.old exists on compute (an earlier run?): stopping"; bw lock >/dev/null; exit 1; }
id=$(bw list items --search "$NAME" | jq -r --arg n "$NAME" '[.[] | select(.name==$n)] | if length==1 then .[0].id else error("not exactly one item") end')
old=$(bw get password "$id"); new=$(bw generate --length 48 -uln)
[ ${#new} -eq 48 ] && [ "$(printf %s "$new" | h)" != "$(printf %s "$old" | h)" ] || { echo "generate failed"; exit 1; }
[ "$(S $MAC 'cat ~/.config/seed/llama.key' | tr -d '\n' | h)" = "$(printf %s "$old" | h)" ] || { echo "compute's key isn't the vault's: stopping"; exit 1; }
echo "old $(printf %s "$old" | h), new $(printf %s "$new" | h)"
setvault() { bw get item "$id" | jq --rawfile p <(printf %s "$1") '.login.password=$p' | bw encode | bw edit item "$id" >/dev/null; bw sync >/dev/null
  [ "$(bw get password "$id" | h)" = "$(printf %s "$1" | h)" ]; }
setmac() { printf '%s' "$1" | S $MAC 'umask 077; cd ~/.config/seed && cat > llama.key.new && mv llama.key.new llama.key && chmod 600 llama.key'
  S $MAC 'before=$(pgrep -f '"'"'^/bin/bash [^ ]*/inference/supervise\.sh$'"'"' | head -1); sudo -n /bin/launchctl kickstart -k system/co.oznog.seed.inference || exit 1
    for i in $(seq 1 30); do now=$(pgrep -f '"'"'^/bin/bash [^ ]*/inference/supervise\.sh$'"'"' | head -1); [ -n "$now" ] && [ "$now" != "$before" ] && break; sleep 1; done
    [ -n "$now" ] && [ "$now" != "$before" ] || exit 1   # a new supervisor, not the old one still answering
    for p in 8080 8082; do ok=; for i in $(seq 1 100); do [ "$(curl -s -m 3 -o /dev/null -w %{http_code} http://192.168.1.20:$p/health)" = 200 ] && { ok=1; break; }; sleep 3; done; [ -n "$ok" ] || exit 1; done'; }
unlock() { BW_SESSION=$(. "$R/tools/vault-env.sh"; bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null); export BW_SESSION; }
setgateway() { local rc=0; bw lock >/dev/null   # deploy-infra-config unlocks and locks the vault itself
  ( cd "$R/site" && bin/deploy-infra-config >/dev/null 2>&1 ) || rc=1
  [ $rc = 0 ] && { "$R/tools/ui/run.sh" edit-container.js litellm >/dev/null 2>&1 || rc=1; }
  unlock
  [ $rc = 0 ] && S root@192.168.1.10 'for i in $(seq 1 60); do [ "$(curl -s -m 2 -o /dev/null -w %{http_code} http://127.0.0.1:4000/health/liveliness)" = 200 ] && exit 0; sleep 3; done; exit 1' || rc=1
  return $rc; }
rollback() { trap - ERR; set +e; echo "FAILED: rolling back to the old key"; unlock
  if setvault "$old"; then echo "  vault: back"; else echo "  the vault's rollback FAILED: by hand"; fi
  if setmac "$old"; then echo "  compute: back"; S $MAC 'rm -f ~/.config/seed/llama.key.old'
  else echo "  compute's rollback FAILED: by hand (the old key is in ~/.config/seed/llama.key.old)"; fi
  if setgateway; then echo "  gateway: back"; else echo "  the gateway's rollback FAILED: by hand"; fi
  unset old new; bw lock >/dev/null; exit 1; }
trap rollback ERR
setvault "$new"; echo "1. vault: $(bw get password "$id" | h)"
S $MAC 'cp -p ~/.config/seed/llama.key ~/.config/seed/llama.key.old && chmod 600 ~/.config/seed/llama.key.old'
setmac "$new"; echo "2. compute: $(S $MAC 'cat ~/.config/seed/llama.key' | h), inference restarted, both ports healthy"
setgateway; echo "3. gateway: litellm.env $(S root@192.168.1.10 'sed -n "s/^COMPUTE_LLAMA_API_KEY=//p" /mnt/data/system/secrets/litellm.env' | tr -d '\n' | h), LiteLLM recreated"
proofs=$(S $MAC 'k() { printf "header = \"Authorization: Bearer %s\"\n" "$(cat ~/.config/seed/$1)"; }
  for f in llama.key.old llama.key; do
    a=$(k $f | curl -s -m 20 -K - -o /dev/null -w "%{http_code}" http://192.168.1.20:8080/v1/models)
    b=$(k $f | curl -s -m 20 -K - -o /dev/null -w "%{http_code}" -H "Content-Type: application/json" -d "{\"text\":\"ok\"}" http://192.168.1.20:8082/v1/pii)
    echo "$f $a $b"; done')
g=$(S root@192.168.1.10 'MK=$(sed -n "s/^LITELLM_MASTER_KEY=//p" /mnt/data/system/secrets/litellm.env); printf "header = \"Authorization: Bearer %s\"\n" "$MK" | curl -sf -m 60 -K - -H "Content-Type: application/json" -d "{\"model\":\"local-embed\",\"input\":\"ok\"}" http://127.0.0.1:4000/v1/embeddings | jq -r "if (.data[0].embedding|type)==\"array\" and (.data[0].embedding|all(type==\"number\")) then (.data[0].embedding|length) else 0 end" || echo 0')   # -f: anything but 2xx is 0
echo "4. proofs: $(echo "$proofs" | tr '\n' ';') gateway local-embed: $g dimensions"
[ "$proofs" = "$(printf 'llama.key.old 401 401\nllama.key 200 200')" ] && [ "$g" = 2560 ] || { echo "the proofs failed"; false; }
trap - ERR
S $MAC 'rm -P ~/.config/seed/llama.key.old' && echo "5. the old copy removed (rm -P)"
unset old new; bw lock >/dev/null
