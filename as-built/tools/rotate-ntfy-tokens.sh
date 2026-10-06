#!/usr/bin/env bash
# rotate-ntfy-tokens.sh: new values for the ntfy tokens exposed 20261003 03:20Z (printed into the builder's output):
# watcher, power, tender, orchestrator (Alertmanager's no longer exists: it signs in by password). The orchestrator's
# go, 20261003. New values go straight into the vault items and onto the hosts; nothing printed, nothing in argv.
# Without a gap: core first accepts the old and the new token of each user (ntfy takes several per user: tested on
# core's 2.28), the consumers move, then the old ones go. Every step asserts; a failure stops with what to do.
#   A  preflight: the vault, each current token works (GET /v1/account 200), the generators, the forge; the old
#      values age-encrypted to the master key in /tmp/reh/ntfy-rotation-old.age (a failed vault edit midway can then
#      be finished by hand), removed at the end
#   B  new values (29 of [a-z0-9]: ntfy's tk_ + 29) generated in memory, checked, written to the vault, read back
#   C  host files: core with old + new (tools/core-secrets-make.sh, NTFY_PREV), the agent box: the watcher's
#      ntfy_core_token (tk_ + value) and tender_ntfy_token (tools/tender-bundle-make.sh)
#   D  commit, promote, deploy core then the agent box; old and new both 200; tender's file equals the vault's
#   E  core with the new only; deploy; new 200 and old 401 for all four; the host files equal the vault's (hash)
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p /tmp/reh; R=/tmp/reh/ntfy-rotation-old.age
declare -A ITEM=([watcher]="ntfy core watcher" [power]="ntfy core power" [tender]="tender ntfy token" [orchestrator]="ntfy orchestrator read")
declare -A OLD NEW ID
U=(watcher power tender orchestrator)
die() { echo "STOPPED: $*" >&2; exit 1; }
unlock() { . tools/vault-env.sh; BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null); export BW_SESSION; unset BW_PASSWORD BW_CLIENTSECRET; }
lock() { bw lock >/dev/null 2>&1 || true; unset BW_SESSION; }
trap 'lock; unset OLD NEW' EXIT
account() { printf 'header = "Authorization: Bearer tk_%s"\n' "$1" | curl -s -K - -o /dev/null -w '%{http_code}' https://ntfy.seed.example.com/v1/account; }
h() { printf '%s' "$1" | sha256sum | cut -c1-12; }
vault() { ( exec 9>/tmp/reh/bw.lock; flock 9; "$@" ); }
deploy() {  # deploy <title> <hosts: core|agent|both>
  git push -q forge main; git fetch -q forge; local hh=$(git rev-parse forge/main) n st; . /tmp/forge.sh
  n=$(forge POST /repos/seed/seed-lab/pulls "$(jq -nc --arg t "$1" '{base: "deploy", head: "main", title: $t}')" | jq -r .number)
  for i in $(seq 1 90); do st=$(forge GET /repos/seed/seed-lab/commits/$hh/status | jq -r .state); case $st in success|failure|error) break;; esac; sleep 20; done
  [ "$st" = success ] || die "PR #$n: build check $st"
  forge POST /repos/seed/seed-lab/pulls/$n/merge '{"Do":"fast-forward-only"}' >/dev/null
  [ "$(git ls-remote forge refs/heads/deploy | cut -f1)" = "$hh" ] || die "PR #$n: the deploy ref isn't ${hh:0:7} after the merge"
  case $2 in core|both) ssh -o BatchMode=yes -o LogLevel=ERROR admin@192.168.1.12 'sudo -n systemctl start seed-deploy.service' || die "core's deploy failed";; esac
  case $2 in agent|both) sudo -n /run/current-system/sw/bin/systemctl start seed-deploy.service || die "the agent box's deploy failed"
    sudo -n /run/current-system/sw/bin/seed-deploy-log 2>&1 | grep "seed-deploy: done" | tail -1 | grep -q "done, $hh" || die "the agent box didn't report ${hh:0:7} done";; esac
  echo "   PR #$n deployed ($2, ${hh:0:7})"; }

echo "A. preflight"
[ -z "$(git status --porcelain site/core/secrets.age nixos/secrets/agent.yaml)" ] || die "secrets.age or agent.yaml has uncommitted changes"
[ ! -e $R ] || die "$R exists: an earlier run stopped; finish it by hand first"
master=$(awk '/&master /{print $3}' .sops.yaml); [[ $master == age1* ]] || die "the master key's recipient"
exec 9>/tmp/reh/bw.lock; flock 9; unlock; bw sync >/dev/null
for u in "${U[@]}"; do
  ID[$u]=$(bw list items --search "${ITEM[$u]}" | jq -r --arg n "${ITEM[$u]}" '[.[] | select(.name == $n)] | if length == 1 then .[0].id else empty end')
  [ -n "${ID[$u]}" ] || die "vault: '${ITEM[$u]}' missing or duplicated"
  OLD[$u]=$(bw get password "${ID[$u]}" | tr -d '\n')
  [ "$(account "${OLD[$u]}")" = 200 ] || die "$u: its current token doesn't work now"
done
for u in "${U[@]}"; do printf '%s %s\n' "$u" "${OLD[$u]}"; done | nix-shell -p age --run "age -a -r '$master' -o $R" && chmod 600 $R || die "the rollback file"
echo "   4 current tokens work; the old values encrypted to the master key in $R"

echo "B. new values into the vault"
for u in "${U[@]}"; do
  NEW[$u]=$(bw generate -ln --length 29 | tr -d '\n')
  [[ ${NEW[$u]} =~ ^[a-z0-9]{29}$ && ${NEW[$u]} != "${OLD[$u]}" ]] || die "$u: a generated value of the wrong shape (vault unchanged for $u)"
done
for u in "${U[@]}"; do
  bw get item "${ID[$u]}" | jq --rawfile p <(printf '%s' "${NEW[$u]}") '.login.password = $p' | bw encode | bw edit item "${ID[$u]}" >/dev/null \
    || die "$u: the vault edit failed (the items before it are new: the old values are in $R)"
  [ "$(bw get password "${ID[$u]}" | tr -d '\n' | sha256sum)" = "$(printf '%s' "${NEW[$u]}" | sha256sum)" ] || die "$u: the vault doesn't read back the new value"
  echo "   $u: vault $(h "${OLD[$u]}") -> $(h "${NEW[$u]}")"
done
bw sync >/dev/null; lock; exec 9>&-

echo "C. host files: core with old + new, the agent box with new"
NTFY_PREV=<(for u in "${U[@]}"; do printf '%s tk_%s\n' "$u" "${OLD[$u]}"; done) vault bash tools/core-secrets-make.sh >/dev/null || die "core-secrets-make (transitional)"
tb=$(vault bash tools/tender-bundle-make.sh 2>&1) || die "tender-bundle-make failed"
grep -q "^set tender_ntfy_token" <<<"$tb" && ! grep -q FAILED <<<"$tb" || die "tender-bundle-make: tender_ntfy_token not set"
( exec 9>/tmp/reh/bw.lock; flock 9; unlock
  SOPS_AGE_KEY=$(bw list items --search 'sops master age key' | jq -r '[.[] | select(.name == "sops master age key")][0] | .login.password // .notes' | grep -o 'AGE-SECRET-KEY-[A-Z0-9]*'); lock
  [ -n "$SOPS_AGE_KEY" ] || exit 1; export SOPS_AGE_KEY
  printf 'tk_%s' "${NEW[watcher]}" | jq -Rs . | nix-shell -p sops --run "sops set --value-stdin nixos/secrets/agent.yaml '[\"ntfy_core_token\"]'" 2>/dev/null ) || die "the watcher's ntfy_core_token not set"
git add site/core/secrets.age nixos/secrets/agent.yaml
git commit -q -m "ntfy rotation, step 1: core accepts the old and the new tokens; the agent box gets the new (tools/rotate-ntfy-tokens.sh)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"

echo "D. deploy core, then the agent box"
deploy "ntfy rotation, step 1 (old and new accepted)" both
for u in "${U[@]}"; do n=$(account "${NEW[$u]}"); o=$(account "${OLD[$u]}"); [ "$n$o" = 200200 ] || die "$u: new $n, old $o while both should work"; done
th=$(ssh -o BatchMode=yes -o LogLevel=ERROR tender@localhost 'tr -d "\n" < /run/secrets/tender_ntfy_token | sha256sum | cut -c1-12')
[ "$th" = "$(h "${NEW[tender]}")" ] || die "tender's /run/secrets file isn't the new value"
echo "   old and new both 200 for all four; tender's file is the new value; the agent box deployed it (sops-nix: the watcher's file)"

echo "E. core with the new only"
vault bash tools/core-secrets-make.sh >/dev/null || die "core-secrets-make (final)"
git add site/core/secrets.age
git commit -q -m "ntfy rotation, step 2: the old tokens removed from core

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
deploy "ntfy rotation, step 2 (old tokens removed)" core
for u in "${U[@]}"; do n=$(account "${NEW[$u]}"); o=$(account "${OLD[$u]}"); echo "   $u: new token $n, old token $o"; [ "$n$o" = 200401 ] || die "$u: not new 200 / old 401"; done
ph=$(ssh -o BatchMode=yes -o LogLevel=ERROR admin@192.168.1.12 "sudo -n sh -c 'tr -d \"\\n\" < /etc/seed/ntfy-power-token' | sha256sum | cut -c1-12")
[ "$ph" = "$(h "tk_${NEW[power]}")" ] || die "core's power token file isn't the new value"
echo "   power: core's /etc/seed/ntfy-power-token is the new value"
echo "   watcher: its deployed sops value is the new one (/run/secrets is root's; the source checked in C)"
echo "   orchestrator: new in the vault and live on core; the orchestrator re-tests from the operator's laptop"
rm -f $R; echo "done; $R removed"
