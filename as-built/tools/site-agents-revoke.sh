#!/usr/bin/env bash
# Revoke every credential of the site agents (the account `tender`: Hermes, Claude Code, Codex) in one run
# (briefs/agents.md › B). Run by the builder or the orchestrator from the agent box, with the keys that reach the
# hosts. Each step prints what it did; a step that fails doesn't stop the others.
#   - the ssh key "tender@agent site agents": removed from infra (flash and live), core (admin), site2 (admin: LIVE ONLY
#     here; its Nix config re-declares it at the next activation or reboot, so the durable step is removing keys.tender
#     from nixos/hosts/site2 and deploying it, which this run prints and doesn't do), the access point,
#     the firewall (root's keys in OPNsense), the sandbox (root, when it's running);
#   - the gateway key (LiteLLM alias tender): deleted;
#   - the forge user tender (and its token): deleted by Forgejo's admin CLI (its pushed branches stay in the repo);
#   - ntfy: the tender user is refused at once (ntfy access tender seed deny on core); remove it from
#     site/core/apply and tools/core-secrets-make.sh afterwards so the next deploy doesn't bring it back;
#   - on the agent box (needs root): stop tender's services and lock the account;
#   - by hand, at the vendors: the Claude Code token (claude.ai), Codex's login (OpenAI), the Telegram bot (BotFather);
#   - the vault items named "tender …" stay as the record (the owner deletes them).
set -uo pipefail
C='tender@agent site agents'
S="ssh -o BatchMode=yes -o LogLevel=ERROR -o ConnectTimeout=10"
step() { echo "== $1"; }
step "infra: ssh key"; $S root@192.168.1.10 "for f in /boot/config/ssh/root/authorized_keys /root/.ssh/authorized_keys; do sed -i '/$C/d' \$f; echo \"\$f: \$(grep -c '$C' \$f) left\"; done"
step "core: ssh key"; $S admin@192.168.1.12 "sed -i '/$C/d' ~/.ssh/authorized_keys; echo \"left: \$(grep -c '$C' ~/.ssh/authorized_keys)\""
step "site2: ssh key (live; then remove keys.tender from nixos/hosts/site2 so the next deploy doesn't bring it back)"
$S admin@100.64.0.12 "f=/etc/ssh/authorized_keys.d/admin; sudo sh -c 'grep -v \"$C\" \$0 > \$0.new; rm -f \$0; mv \$0.new \$0; chmod 444 \$0' \$f; echo \"left: \$(grep -c '$C' \$f)\""
step "access point: ssh key"; $S root@192.168.1.4 "sed -i '/$C/d' /etc/dropbear/authorized_keys; echo \"left: \$(grep -c '$C' /etc/dropbear/authorized_keys)\""
step "firewall: ssh key"; $S -o HostKeyAlias=192.168.1.2 root@192.168.1.1 php <<'EOF'
<?php
require_once 'config.inc'; require_once 'util.inc'; require_once 'auth.inc';
global $config;
$single = isset($config['system']['user']['name']); $users = $single ? [$config['system']['user']] : $config['system']['user'];
foreach ($users as $i => $u) { if ($u['name'] != 'root') continue;
  $keep = array_filter(explode("\n", base64_decode($u['authorizedkeys'] ?? '')), fn($l) => trim($l) !== '' && strpos($l, 'tender@agent site agents') === false);
  $users[$i]['authorizedkeys'] = base64_encode(implode("\n", $keep) . "\n");
  if ($single) $config['system']['user'] = $users[$i]; else $config['system']['user'][$i] = $users[$i];
  write_config("seed: the site agents' key revoked"); local_user_set($users[$i]); echo "removed\n"; }
EOF
step "sandbox: ssh key (if running)"; $S root@192.168.1.10 "virsh domstate sandbox 2>/dev/null" | grep -q running && echo "remove it inside the sandbox: see site/runbooks/sandbox.md (reach)" || echo "sandbox not running: remove it at its next start"
step "gateway key"; $S root@192.168.1.10 'MK=$(sed -n "s/^LITELLM_MASTER_KEY=//p" /mnt/data/system/secrets/litellm.env); tok=$(curl -s -m 20 -H "Authorization: Bearer $MK" "http://127.0.0.1:4000/key/list?return_full_object=true&size=100" | jq -r ".keys[] | select(.key_alias==\"tender\") | .token"); [ -n "$tok" ] && curl -s -m 20 -H "Authorization: Bearer $MK" -H "Content-Type: application/json" -d "{\"keys\":[\"$tok\"]}" http://127.0.0.1:4000/key/delete | jq -c . || echo "no key tender"; unset MK tok'
step "forge user tender"; $S root@192.168.1.10 'docker exec -u git forgejo forgejo admin user delete --username tender 2>&1 | tail -1'
step "ntfy (live; then remove from the repo)"; $S admin@192.168.1.12 'sudo -n ntfy access tender seed deny 2>&1 | tail -1'
step "agent box (as root)"; echo "systemctl stop 'tender-*' 'user@1002'; usermod -L tender; loginctl disable-linger tender"
step "by hand at the vendors"; echo "claude.ai: revoke the setup token; OpenAI: sign Codex out (the device login); BotFather: /revoke for the bot"
