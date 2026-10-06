#!/usr/bin/env bash
# forgejo-add-reviewer.sh <user> <email>: a Forgejo account that can review, comment on and merge pull requests in
# seed/seed-lab (first: rigger, the orchestrator, 20261002). No site-admin credential is kept in the vault, so the
# account and its token come from the forge's own CLI inside its container on infra (as the first accounts did,
# diary 20260923-s3), each read from the CLI's stdout straight into a vault item: never an argument, never printed.
#   - the password: --random-password-length 40 -> vault "forgejo <user>" (Seed/routine)
#   - an API token (write:repository, write:issue: review, comment, merge; the CLI can't limit it to one repository,
#     the account's rights do: it is in no other repository) -> "forgejo <user> token"
#   - rights, as the builder (an org owner): the team "deployers" (write on seed-lab; the merge whitelist of `deploy`)
#     and the merge whitelist of `main`
#   - the proof: one read-only API call with the token (the repo), its HTTP code only
set -Eeuo pipefail; set +x   # never traced: secrets pass through variables
u=${1:?user}; mail=${2:?email}; R=${SEED_REPO:-/work/agent/seed-lab}
[[ $u =~ ^[a-z][a-z0-9-]{1,30}$ ]] || { echo "user: lowercase letters, digits, -"; exit 64; }
[[ $mail =~ ^[a-z0-9._-]+@[a-z0-9.-]+$ ]] || { echo "email: plain"; exit 64; }
INFRA=(ssh -o BatchMode=yes -o LogLevel=ERROR root@192.168.1.10)
. /tmp/forge.sh   # forge <METHOD> <path> [json]: the builder's API session (vault item "forgejo seed-builder")
# forge() takes the vault's lock itself: forge calls first, then the vault phases, each holding the lock
[ "$(forge GET "/users/$u" | jq -r '.login // empty')" = "" ] || { echo "$u exists already"; exit 1; }
team=$(forge GET /orgs/seed/teams | jq -r '.[]|select(.name=="deployers").id'); [ -n "$team" ] || { echo "no team deployers"; exit 1; }
vopen() { exec 9>/tmp/reh/bw.lock; flock 9; . "$R/tools/vault-env.sh"
  BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null); export BW_SESSION; unset BW_PASSWORD BW_CLIENTSECRET
  trap 'bw lock >/dev/null 2>&1' EXIT; bw sync >/dev/null; }
vclose() { bw lock >/dev/null 2>&1; unset BW_SESSION; trap - EXIT; exec 9>&-; }
vopen
for n in "forgejo $u" "forgejo $u token"; do
  bw list items --search "$n" | jq -e --arg n "$n" 'map(select(.name==$n)) | length == 0' >/dev/null || { echo "vault item '$n' exists"; exit 1; }; done
org=$(bw list organizations | jq -r '.[]|select(.name=="Seed").id'); col=$(bw list collections --organizationid "$org" | jq -r '.[]|select(.name=="routine").id')
[[ -n $org && -n $col ]] || { echo "org/collection lookup failed"; exit 1; }
item() {  # item <name> <notes>: a login item for $u, its password on stdin
  local pw; pw=$(cat); [[ $pw =~ ${PAT:?} ]] || { echo "item $1: the secret wasn't read as expected"; return 1; }
  # the secret reaches jq through a file descriptor, not its environment or argv
  bw get template item | N="$1" U="$u" NOTES="$2" O="$org" C="$col" \
    jq --rawfile pw <(printf '%s' "$pw") '.organizationId=env.O | .collectionIds=[env.C] | .name=env.N | .notes=env.NOTES | .fields=[] | .login={username:env.U,password:$pw,uris:[{uri:"https://git.seed.example.com"}]}' \
    | bw encode | bw create item | jq -r '"created: " + .name'; }
# if a vault write fails after the account exists, its secret would be lost: the account goes again (and its item)
rollback() { trap - ERR INT TERM HUP; echo "FAILED: removing the half-made account $u"
  if ! "${INFRA[@]}" "docker exec -u git forgejo forgejo admin user delete --username $u" >/dev/null 2>&1; then
    echo "the account $u could NOT be removed: its vault items (if any) are kept; finish by hand"; bw lock >/dev/null 2>&1; exit 1; fi
  bw list items --search "forgejo $u" | jq -r --arg a "forgejo $u" --arg b "forgejo $u token" '.[]|select(.name==$a or .name==$b).id' | while read -r i; do bw delete item "$i" >/dev/null; done
  bw lock >/dev/null 2>&1; }
trap rollback ERR INT TERM HUP
# 1. the account: the CLI prints "generated random password is '<pw>'" once; exactly one 40-character value goes on
"${INFRA[@]}" "docker exec -u git forgejo forgejo admin user create --username '$u' --email '$mail' --random-password --random-password-length 40 --must-change-password=false" \
  | sed -n "s/^.*generated random password is '\([^' ]\{40\}\)'\$/\1/p" | PAT='^[A-Za-z0-9]{40}$' item "forgejo $u" "Forgejo account on git.seed.example.com: reviews, comments on and merges pull requests in seed/seed-lab (tools/forgejo-add-reviewer.sh)."
# 2. its token
"${INFRA[@]}" "docker exec -u git forgejo forgejo admin user generate-access-token -u '$u' -t '$u-api' --scopes write:repository,write:issue --raw" \
  | tr -d '\r' | PAT='^[0-9a-f]{40}$' item "forgejo $u token" "API token of forgejo $u (scopes write:repository, write:issue)."
trap - ERR INT TERM HUP; vclose
# 3. its rights (forge() doesn't report HTTP errors: each is read back)
forge PUT "/teams/$team/members/$u" >/dev/null
wl=$(forge GET /repos/seed/seed-lab/branch_protections/main | jq -c --arg u "$u" '.merge_whitelist_usernames + [$u] | unique')
forge PATCH /repos/seed/seed-lab/branch_protections/main "{\"merge_whitelist_usernames\":$wl}" | jq -c '{branch_name, merge_whitelist_usernames}'
forge GET "/teams/$team/members" | jq -e --arg u "$u" 'map(.login) | index($u)' >/dev/null || { echo "FAILED: $u not in deployers"; exit 1; }
forge GET /repos/seed/seed-lab/branch_protections/main | jq -e --arg u "$u" '.merge_whitelist_usernames | index($u)' >/dev/null || { echo "FAILED: $u not in main's merge whitelist"; exit 1; }
forge GET "/teams/$team/repos" | jq -e 'map(.full_name) | index("seed/seed-lab")' >/dev/null || { echo "FAILED: deployers has no seed-lab"; exit 1; }
[ "$(forge GET "/teams/$team" | jq -r '.units_map["repo.pulls"]')" = write ] || { echo "FAILED: deployers can't write pulls"; exit 1; }
forge GET /repos/seed/seed-lab/branch_protections/deploy | jq -e '.merge_whitelist_teams | index("deployers")' >/dev/null || { echo "FAILED: deploy doesn't let deployers merge"; exit 1; }
echo "rights: $u in deployers (write on seed-lab's code and pulls; deploy's merge whitelist) and in main's merge whitelist"
# 4. the proof: the token, from the vault into curl's config on stdin
vopen
bw list items --search "forgejo $u token" | jq -r --arg n "forgejo $u token" '.[]|select(.name==$n).login.password' \
  | sed 's/^/header = "Authorization: token /; s/$/"/' \
  | curl -s -K - -o /dev/null -w "%{http_code}" https://git.seed.example.com/api/v1/repos/seed/seed-lab/pulls?limit=1 > /tmp/reh/.proof-code
code=$(cat /tmp/reh/.proof-code); rm -f /tmp/reh/.proof-code
anon=$(curl -s -o /dev/null -w "%{http_code}" "https://git.seed.example.com/api/v1/repos/seed/seed-lab/pulls?limit=1")
echo "token proof: GET seed-lab's pulls -> HTTP $code with the token, $anon without (the repository is private)"; [ "$code" = 200 ] && [ "$anon" != 200 ]
