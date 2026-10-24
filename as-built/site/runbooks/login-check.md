# The login check (from 20261024)

Every login the site depends on is used once an hour with its cheapest real use, and each service has its own
Healthchecks check: a failure hits the check's fail endpoint at once (a page within the hour, by the account's email
channel), with the failed login's NAME in the ping body, never a value. Silence (the checker itself stopped) pages
after 1 h + 30 min grace. `tools/login-check.sh` (the orchestrator's brief, 20261024; Codex-reviewed).

| check | logins (vault item names) | the real use |
|---|---|---|
| login-claude-keel | Keel's own Claude login (agent's ~/.claude) | `claude auth status`, a one-word `claude -p`; warns 7 days before its refresh token expires (about 30 days at a fresh sign-in: the owner signs Keel in again) |
| login-claude-tender | claude code tender token (/run/secrets) | the same through tender's model-client wrapper (its own HOME); warns from 30 days before 20270929 |
| login-vault | the builder's Bitwarden API login | `bw unlock`, `bw sync` |
| login-forge | forgejo seed-builder; tender forge token; forgejo seed-buildcheck token | GET /api/v1/user (buildcheck: its repository) |
| login-healthchecks | healthchecks api key | GET /api/v3/checks/ |
| login-gateway | tender gateway key; gateway key agent; gateway key monitoring-probe; litellm master key; compute llama api key | GET /v1/models (the gateway; compute's server) |
| login-zai | zai api key | GET the provider's /models |
| login-ntfy | ntfy core power, watcher, orchestrator read; tender ntfy token; ntfy core alertmanager password; ntfy core phone | GET /v1/account, a named (not anonymous) user |
| login-backup | b2 seed-writer, seed-machines-writer, seed-restore-reader; rest-server agent, agentvm, compute | b2_authorize_account (API v4); HEAD of each repository's config |
| login-netbox | netbox api token builder | GET /api/dcim/sites/?limit=1 |
| login-dns-net | dnsimple example.com; opnsense api root; the tailnet's node keys | GET /v2/whoami; the fw's firmware status (its self-signed LAN cert); any node key expiring within 30 days |
| login-bots | telegram tender bot; huggingface read token | getMe; whoami-v2 |

Not checked here: web logins of people (netbox admin, monitoring ui, syncthing gui, the Vaultwarden admin token),
services' internal passwords (postgres, valkey: their containers fail visibly), ssh keys, and "ntfy core alertmanager"
(the token: Alertmanager signs in by password since 20261003; the token no longer signs in).

**Running it:** the agent box, user agent (linger on): `~/.config/systemd/user/login-check.{service,timer}`, hourly
at :07. Its service runs `bash tools/login-check.sh run` in the checkout with PATH
`/home/agent/.local/bin:/etc/profiles/per-user/agent/bin:/run/current-system/sw/bin`, TimeoutStartSec 20min. The
checks are made by `login-check.sh create-checks` (ping URLs in ~/.config/seed/login-check.pings, 0600).
`LOGIN_CHECK_DRY=1` pings nothing; `LOGIN_CHECK_ONLY=<check>` runs one.

**Proved 20261024:** `LOGIN_CHECK_BREAK="netbox api token builder"` (a wrong copy in memory; the real token untouched)
took login-netbox down at 17:47:23Z by its fail endpoint (HTTP 403 named in the ping); a normal run brought it up.
