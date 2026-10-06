#!/usr/bin/env bash
# The site agents' (tender) secrets into nixos/secrets/agent.yaml (sops), from the site vault: vault -> jq -> sops
# (--value-stdin) with the master age key held in memory; nothing printed, nothing in argv. On the agent box
# sops-nix puts each in /run/secrets (tmpfs), owned by tender, 0400 (nixos/modules/site-agents.nix).
#   tender_vault_items    the items in site/agents/vault-bundle.txt, as `bw list items` JSON (name, login)
#   tender_claude_token   "claude code tender token"  (CLAUDE_CODE_OAUTH_TOKEN, read at start)
#   tender_gateway_key    "tender gateway key"         (LiteLLM alias tender)
#   tender_forge_token    "tender forge token"         (Forgejo user tender)
#   tender_ntfy_token     "tender ntfy token"          (read-only on topic seed; tk_ + this)
#   tender_telegram_token "telegram tender bot"        (Hermes's Telegram bot; skipped, and said, when missing)
#   tender_hc_*           Healthchecks ping URLs, when present (G)
# Run again after any of these vault items change; then commit, promote, let the agent box deploy.
set -euo pipefail
cd "$(dirname "$0")/.."
F=nixos/secrets/agent.yaml
. tools/vault-env.sh
BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null); export BW_SESSION; unset BW_PASSWORD BW_CLIENTSECRET
trap 'bw lock >/dev/null 2>&1 || true; unset ITEMS SOPS_AGE_KEY' EXIT
bw sync >/dev/null; ITEMS=$(bw list items); bw lock >/dev/null 2>&1; unset BW_SESSION
one() { N="$1" jq -e '[.[] | select(.name==env.N)] | if length==1 then .[0] else empty end' <<<"$ITEMS"; }
export SOPS_AGE_KEY=$(one 'sops master age key' | jq -r '.login.password // .notes' | grep -o 'AGE-SECRET-KEY-[A-Z0-9]*')
[ -n "$SOPS_AGE_KEY" ] || { echo "sops master age key not found"; exit 1; }
put() { nix-shell -p sops --run "sops set --value-stdin $F '[\"$1\"]'" 2>/dev/null && echo "set $1" || { echo "FAILED $1"; return 1; }; }
# the bundle: only the listed items, only name and login
names=$(grep -v '^#' site/agents/vault-bundle.txt | grep . | jq -R . | jq -s .)
jq --argjson n "$names" '[.[] | select(.name as $x | $n | index($x)) | {name, login: {username: .login.username, password: .login.password}}]' <<<"$ITEMS" \
  | tee >(jq -r --argjson n "$names" '"bundle: \(length) of \($n | length) items"' >&2) | jq -c . | jq -Rs . | put tender_vault_items
for pair in "tender_claude_token:claude code tender token" "tender_gateway_key:tender gateway key" \
            "tender_forge_token:tender forge token" "tender_ntfy_token:tender ntfy token" "tender_telegram_token:telegram tender bot"; do
  key=${pair%%:*}; item=${pair#*:}
  if it=$(one "$item"); then jq -r '.login.password' <<<"$it" | tr -d '\n' | jq -Rs . | put "$key"
  else echo "MISSING in the vault: '$item' ($key not set)"; fi
done
for it in $(jq -r '.[] | select(.name | startswith("tender hc ")) | .name | sub("tender hc "; "")' <<<"$ITEMS"); do
  one "tender hc $it" | jq -r '.login.password' | tr -d '\n' | jq -Rs . | put "tender_hc_${it//-/_}"; done
