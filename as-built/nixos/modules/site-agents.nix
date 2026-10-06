# The site agents (briefs/agents.md, the owner's decisions 20260929): Hermes, Claude Code and Codex run as one
# user, `tender` (the site agent's name); the builder stays on `agent`. The containment is this account and its
# credentials: home 0700, each agent its own working directory under /work/tender/<agent>. Rules for what they
# may do: the rulebook, deployed read-only at /etc/site-agents/RULEBOOK.md (its source nixos/modules/site-agents/RULEBOOK.md;
# site/agents/RULEBOOK.md links to it). The active flag, /var/lib/site-agents/active, is the orchestrator's (root)
# and holds hermes, claude or none (site/runbooks/agents-handover.md).
{ config, lib, pkgs, ... }:
let
  keys = import ../keys.nix;
  H = "/home/tender";
  # the pinned vendor installs (briefs/agents.md › C; site/agents/README.md › Versions): in tender's home, from
  # each vendor's own channel, checked by sha256
  claudeVersion = "2.1.285";
  # a symlink NAMED claude to the pinned version: the process is then called `claude`, which herdr needs to see it
  claudeBin = "${H}/.local/share/seed/claude/claude";
  # tender's own commands, first on its PATH. `claude` puts the Claude Code token (tmpfs) into the process's
  # environment at its start and nowhere else: not herdr's arguments, not its saved session, not a file.
  tenderBin = pkgs.runCommand "tender-bin" { nativeBuildInputs = [ pkgs.python3 pkgs.curl ]; } ''
    mkdir -p $out/bin
    cat > $out/bin/claude <<'SH'
#!/bin/sh
[ -r /run/secrets/tender_claude_token ] || { echo "claude: no token at /run/secrets/tender_claude_token" >&2; exit 1; }
CLAUDE_CODE_OAUTH_TOKEN=$(cat /run/secrets/tender_claude_token); export CLAUDE_CODE_OAUTH_TOKEN
exec ${claudeBin} "$@"
SH
    install -m 755 ${./site-agents/site-review} $out/bin/site-review
    install -m 755 ${./site-agents/site-intake} $out/bin/site-intake
    install -m 755 ${./site-agents/site-heartbeat} $out/bin/site-heartbeat
    install -m 755 ${./site-agents/site-notify} $out/bin/site-notify
    install -m 755 ${./site-agents/site-redact} $out/bin/site-redact
    install -m 755 ${./site-agents/site-sweep} $out/bin/site-sweep
    install -m 755 ${./site-agents/site-pr} $out/bin/site-pr
    install -D -m 644 ${./site-agents/site-urls.txt} $out/share/site-urls.txt   # site-redact's own probe URLs (tools/site-urls.sh)
    install -D -m 644 ${./site-agents/site-names.txt} $out/share/site-names.txt   # and the site's host and service names
    chmod 755 $out/bin/*
    # the intake's failures never read as "nothing new", and the heartbeat refuses past them: tested at every build,
    # so a regression fails the build check (site-agents/test-site-intake.sh)
    sh ${./site-agents/test-site-intake.sh} $out/bin
  '';
  # stable paths only: a store path here changes every unit that uses it, and a deploy then restarts the agents
  # (seen 20260930 22:17Z). tender-config links ~/.local/share/seed/tender-bin to the tools' store path.
  path = "${H}/.local/share/seed/tender-bin:${H}/.local/bin:/etc/profiles/per-user/tender/bin:/run/current-system/sw/bin";
  files = ./site-agents;
  # a host-run Hermes job (startup, morning-report) alone on Qwen: site-watch paused while it runs and resumed after,
  # only if it was active. Two Hermes sessions on the model's two slots made single calls take 21 min (20260930).
  hermesSolo = pkgs.writeShellScript "hermes-solo" ''
    J=${H}/.hermes/cron/jobs.json
    id() { jq -r --arg n "$1" '(.jobs? // .)[] | select(.name == $n) | .id' "$J"; }
    w=$(id site-watch); resume=
    if [ -n "$w" ] && [ "$(jq -r --arg i "$w" '(.jobs? // .)[] | select(.id == $i) | .enabled' "$J")" = true ]; then
      hermes cron pause "$w" >/dev/null && resume=1 && echo "site-watch paused for $1"
      trap '[ -n "$resume" ] && hermes cron resume "$w" >/dev/null && echo "site-watch resumed"' EXIT
    fi
    # and a site-watch run already under way finishes first (up to an hour): one Hermes session at a time
    for i in $(seq 1 120); do
      hermes cron runs "$w" 2>/dev/null | head -1 | grep -q ' running ' || break
      [ "$i" = 1 ] && echo "waiting for the site-watch run under way"; sleep 30
    done
    hermes cron run "$(id "$1")"
  '';
in
{
  users.groups.tender.gid = 1002;
  users.users.tender = {
    isNormalUser = true; uid = 1002; group = "tender";
    home = "/home/tender"; homeMode = "700"; createHome = true;
    linger = true;                    # its services run without a login session
    # the orchestrator; and the builder FOR THE SETUP (installs, proofs), removed by one line once the agents run
    openssh.authorizedKeys.keys = [ keys.orchestrator keys.builderAgent keys.ownerMbp keys.ownerFwl ];   # owner's: 20260930
    packages = with pkgs; [ git jq curl python3 uv nodejs_22 ripgrep openssh gnutar gzip unzip file tmux gcc gnumake pkg-config ];
  };

  # tender's credentials (tools/tender-bundle-make.sh: vault -> sops), in tmpfs, readable by tender only. The Claude
  # Code token and the Telegram token are read into the process at its start and never written elsewhere.
  sops.secrets = lib.genAttrs [ "tender_claude_token" "tender_gateway_key" "tender_forge_token" "tender_ntfy_token"
                                "tender_hc_hermes_work" "tender_hc_claude_work" "tender_hc_qwen_route" "tender_hc_telegram" "tender_telegram_token" ]
    (n: { owner = "tender"; mode = "0400"; }) // {
    # the few vault items the site's tools need (site/agents/vault-bundle.txt), read by tools/vault-env.sh (bundle)
    tender_vault_items = { owner = "tender"; mode = "0400"; path = "/run/secrets/tender-vault-items"; };
  };
  # tender's tools read the bundle, not a vault login
  # the rulebook, deployed read-only (the orchestrator, under the Seed authority, 20261006): both agents load it from
  # here, not from their own branches, so it always matches what's deployed, needs no merge into agent branches, and
  # an agent can't edit its own rulebook (a root-owned link into the read-only store)
  environment.etc."site-agents/RULEBOOK.md".source = ./site-agents/RULEBOOK.md;
  environment.extraInit = ''
    if [ "$(id -un)" = tender ]; then export SEED_VAULT=bundle PATH="${path}:$PATH"; fi
  '';

  systemd.user.timers = let t = cal: { unitConfig.ConditionUser = "tender"; wantedBy = [ "timers.target" ]; timerConfig = { OnCalendar = cal; Persistent = false; }; }; in {
    tender-claude-tick = t "*:0/10";
    tender-qwen-check = t "*:0/5";
    tender-telegram-check = t "*:2/5";
    tender-morning-claude = t "*-*-* 07:01:00";
    tender-morning-hermes = t "*-*-* 07:01:00";
  };

  # --- tender's services (systemd user units, this user only; lingering starts them at boot)
  systemd.user.services = let only = { ConditionUser = "tender"; }; env = { PATH = lib.mkForce path; SEED_VAULT = "bundle";
    # NixOS puts glibc's and tzdata's store paths here; their updates would restart the agents
    LOCALE_ARCHIVE = lib.mkForce "/run/current-system/sw/lib/locale/locale-archive"; TZDIR = lib.mkForce "/etc/zoneinfo";
    # Hermes's scheduled jobs: 50 min without progress before a run is killed (default 600 s; a cold prefill is longer)
    HERMES_CRON_TIMEOUT = "3000";
    # Hermes resolves the gateway as provider "custom" at run time, so providers.seed-gateway.*_timeout_seconds in its
    # config is never read (seen 20260930: still 180 s); these are the fallbacks it does read
    HERMES_STREAM_STALE_TIMEOUT = "2700"; HERMES_API_TIMEOUT = "3600"; }; in {
    # the agents' configuration, from the repository, put in place at every start (the repository is the source)
    tender-config = {
      unitConfig = only; wantedBy = [ "default.target" ]; environment = env;
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      script = ''
        set -eu
        install -D -m 600 ${files}/herdr-config.toml ${H}/.config/herdr/config.toml
        install -D -m 600 ${files}/claude-CLAUDE.md ${H}/.claude/CLAUDE.md
        # merged, not overwritten: herdr's Claude integration keeps its hooks in the same file
        s=${H}/.claude/settings.json; [ -f $s ] || echo '{}' > $s
        jq -s '.[0] * .[1]' $s ${files}/claude-settings.json > $s.new && mv $s.new $s && chmod 600 $s
        # Claude Code's state: onboarding done, the checkout trusted, prompts-off accepted (only if new)
        c=${H}/.claude.json
        [ -f $c ] || echo '{"hasCompletedOnboarding":true,"theme":"dark","bypassPermissionsModeAccepted":true,"projects":{"/work/tender/claude/seed-lab":{"hasTrustDialogAccepted":true,"hasCompletedProjectOnboarding":true}}}' > $c
        chmod 600 $c
        mkdir -p ${H}/.local/share/seed/claude
        ln -sfn ${H}/.local/share/claude/versions/${claudeVersion} ${claudeBin}
        install -D -m 600 ${files}/hermes-config.yaml ${H}/.hermes/config.yaml
        install -D -m 600 ${files}/hermes-SOUL.md ${H}/.hermes/SOUL.md
        install -D -m 700 ${files}/site-watch-check.sh ${H}/.hermes/scripts/site-watch-check.sh   # site-watch's pre-check (item 11)
        # Codex for site-review: the pinned derivation (nixos/pkgs/codex.nix), its tools' helper beside it; this replaced a
        # hand-installed copy of the same release without the helper (20260930)
        install -d -m 700 ${H}/.local/bin; ln -sfn ${pkgs.callPackage ../pkgs/codex.nix { }}/bin/codex ${H}/.local/bin/codex
        install -d -m 700 ${H}/.local/share/seed; ln -sfn ${tenderBin}/bin ${H}/.local/share/seed/tender-bin
        # the prompts the host hands the agents, at a stable path: units that name them don't change (and restart an
        # agent) when a prompt does
        for f in periodic-task start-task morning-report; do install -D -m 600 ${files}/$f.txt ${H}/.config/site-agents/prompts/$f.txt; done
        # Hermes loads AGENTS.override.md from its working directory at every start: the rulebook as deployed
        h=/work/tender/hermes/seed-lab
        if [ -d $h/.git ]; then
          ln -sfn /etc/site-agents/RULEBOOK.md $h/AGENTS.override.md
          grep -qx AGENTS.override.md $h/.git/info/exclude || echo AGENTS.override.md >> $h/.git/info/exclude
        fi
      '';
    };
    # herdr's headless server: Claude Code's pane lives here and survives a closed session
    tender-herdr = {
      unitConfig = only; wantedBy = [ "default.target" ]; after = [ "tender-config.service" ]; wants = [ "tender-config.service" ];   # wants: a config refresh at a deploy must not restart the agent
      environment = env;
      serviceConfig = { ExecStart = "${H}/.local/bin/herdr server"; Restart = "always"; RestartSec = 5; WorkingDirectory = H; };
    };
    # Claude Code in its herdr pane (workspace `claude`), started if it isn't running; the pane outlives any client
    tender-claude-pane = {
      unitConfig = only; wantedBy = [ "default.target" ]; after = [ "tender-herdr.service" ]; requires = [ "tender-herdr.service" ];
      environment = env;
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; Restart = "on-failure"; RestartSec = 30; };
      script = ''
        set -eu
        for i in $(seq 1 30); do herdr status server >/dev/null 2>&1 && break; sleep 2; done
        # the owner's layout (20260930): workspace `tender`, tabs `Tender-claude` (this agent) and `Tender-hermes` (not
        # ours). Each is created only if missing; never a second workspace
        ws=$(herdr workspace list | jq -r '.result.workspaces[] | select(.label == "tender") | .workspace_id' | head -1)
        if [ -z "$ws" ]; then
          ws=$(herdr workspace create --cwd /work/tender/claude/seed-lab --label tender --no-focus | jq -r .result.workspace.workspace_id)
          herdr tab rename "$(herdr tab list --workspace "$ws" | jq -r '.result.tabs[0].tab_id')" Tender-claude >/dev/null
        fi
        tab=$(herdr tab list --workspace "$ws" | jq -r '.result.tabs[] | select(.label == "Tender-claude") | .tab_id' | head -1)
        [ -n "$tab" ] || tab=$(herdr tab create --workspace "$ws" --cwd /work/tender/claude/seed-lab --label Tender-claude | jq -r '.result.tab.tab_id')
        pane=$(herdr pane list --workspace "$ws" | jq -r --arg t "$tab" '[.result.panes[] | select(.tab_id == $t)][0].pane_id')
        echo "workspace $ws (tender), tab $tab (Tender-claude), pane $pane"
        if herdr agent list | jq -e '.result.agents[] | select(.name == "claude")' >/dev/null; then echo "claude is running"; exit 0; fi
        herdr agent start claude --kind claude --pane "$pane" --timeout 180000
        # the rulebook's "at every start", once the orchestrator has started the agents
        if [ -e ${H}/.config/site-agents/started ]; then
          for i in $(seq 1 60); do case "$(herdr agent list | jq -r '.result.agents[] | select(.name == "claude") | .agent_status')" in idle|done) break;; esac; sleep 5; done
          herdr agent prompt claude "$(cat ${H}/.config/site-agents/prompts/start-task.txt)" >/dev/null && echo "prompted claude with the start task"
        fi
      '';
    };
    # Claude Code's periodic task, handed to it by the host every 10 minutes when it is idle (its heartbeat is pinged
    # by Claude Code itself at the end of the task, so a stuck session goes silent)
    tender-claude-tick = {
      unitConfig = only; environment = env // { SITE_AGENT = "claude"; };
      serviceConfig.Type = "oneshot";
      script = ''
        [ -e ${H}/.config/site-agents/started ] || { echo "the agents are not started yet (site/agents/README.md › Start)"; exit 0; }
        [ -e ${H}/.config/site-agents/paused/claude ] && [ "$(cat /var/lib/site-agents/active)" != claude ] && { echo "claude is paused by decision ($(head -1 ${H}/.config/site-agents/paused/claude)): skipped"; exit 0; }
        s=$(herdr agent list | jq -r '.result.agents[] | select(.name == "claude") | .agent_status')
        # herdr: idle and done both mean ready for input (done = idle, not yet viewed)
        if [ "$s" = idle ] || [ "$s" = done ]; then herdr agent prompt claude "$(cat ${H}/.config/site-agents/prompts/periodic-task.txt)" >/dev/null && echo "prompted claude"
        elif [ -z "$s" ]; then echo "claude is absent: starting it again"; systemctl --user restart tender-claude-pane
        else echo "claude is $s: no prompt this time"; fi
      '';
    };
    # compute's local backend answers the agents' key: an embedding (local-embed, always resident). From 20261002 (the
    # utility tier) the chat models load on demand and swap, and a chat probe every 5 minutes would load one beside the
    # other. The key reaches curl through a file descriptor, not its arguments.
    tender-qwen-check = {
      unitConfig = only; environment = env;
      serviceConfig.Type = "oneshot";
      script = ''
        c=$(printf '%s' '{"model":"local-embed","input":"ok"}' \
          | curl -s -m 180 -o /dev/null -w '%{http_code}' -H @<(printf 'Authorization: Bearer %s\n' "$(cat /run/secrets/tender_gateway_key)") -H 'Content-Type: application/json' --data-binary @- https://gw.seed.example.com/v1/embeddings)
        if [ "$c" = 200 ]; then curl -fsS -m 10 --retry 3 -o /dev/null "$(cat /run/secrets/tender_hc_qwen_route)"; echo "qwen route ok"; else echo "qwen route: HTTP $c"; exit 1; fi
      '';
    };
    # Telegram connected, as Hermes's gateway reports it
    tender-telegram-check = {
      unitConfig = only; environment = env;
      serviceConfig.Type = "oneshot";
      script = ''
        # paused by decision (the orchestrator, 20261006: Telegram deferred until Hermes's GPU day; 1678 failures since
        # 20260928 numbed alerting): no check, no failure, no ping (a ping would resume the paused healthcheck)
        [ -e ${H}/.config/site-agents/paused/telegram ] && { echo "telegram is paused by decision ($(head -1 ${H}/.config/site-agents/paused/telegram)): skipped"; exit 0; }
        if hermes gateway status 2>&1 | grep -iE 'telegram' | grep -qiE 'connected|running|online|ok' && ! hermes gateway status 2>&1 | grep -iE 'telegram' | grep -qiE 'disconnected|not configured|error'; then
          curl -fsS -m 10 --retry 3 -o /dev/null "$(cat /run/secrets/tender_hc_telegram)"; echo "telegram connected"
        else echo "telegram not connected"; exit 1; fi
      '';
    };
    # the morning report at 07:01 local, prompted by the host (briefs/agents.md › K)
    tender-morning-claude = {
      unitConfig = only; environment = env // { SITE_AGENT = "claude"; };
      serviceConfig.Type = "oneshot";
      script = ''
        [ -e ${H}/.config/site-agents/started ] || { echo "the agents are not started yet"; exit 0; }
        [ -e ${H}/.config/site-agents/paused/claude ] && [ "$(cat /var/lib/site-agents/active)" != claude ] && { echo "claude is paused by decision ($(head -1 ${H}/.config/site-agents/paused/claude)): skipped"; exit 0; }
        for i in $(seq 1 60); do case "$(herdr agent list | jq -r '.result.agents[] | select(.name == "claude") | .agent_status')" in idle|done) break;; esac; sleep 30; done
        herdr agent prompt claude "$(cat ${H}/.config/site-agents/prompts/morning-report.txt)" >/dev/null && echo "prompted claude for the morning report"
      '';
    };
    tender-morning-hermes = {
      unitConfig = only; environment = env;
      serviceConfig = { Type = "oneshot"; TimeoutStartSec = "150min"; };   # the job runs in this process (after up to an hour waiting its turn)
      script = ''
        [ -e ${H}/.config/site-agents/started ] || { echo 'the agents are not started yet'; exit 0; }
        # paused by decision: no job runs, so nothing pings its check (20261002: this timer's run pinged the paused check
        # at 13:28Z, which resumed it, and it went down)
        [ -e ${H}/.config/site-agents/paused/hermes ] && [ "$(cat /var/lib/site-agents/active)" != hermes ] && { echo "hermes is paused by decision ($(head -1 ${H}/.config/site-agents/paused/hermes)): skipped"; exit 0; }
        ${hermesSolo} morning-report
      '';
    };
    # Hermes's scheduled jobs, kept to the repo's prompts at every gateway start (created paused: site-watch is resumed
    # by the orchestrator at start; morning-report and startup are run by the host), then the start task
    tender-hermes-start = {
      unitConfig = only; wantedBy = [ "tender-hermes.service" ]; after = [ "tender-hermes.service" ]; partOf = [ "tender-hermes.service" ];
      environment = env;
      # `hermes cron run` runs the job in this process (a Qwen turn: minutes)
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      script = ''
        set -eu
        J=${H}/.hermes/cron/jobs.json
        # Telegram only once its token exists (Hermes refuses a job whose delivery has no credentials); until then
        # local, and the prompts have the agent send by site-notify too
        # scheduled jobs deliver to Telegram only when the orchestrator turns it on (the flag file); until then Telegram
        # is connected but dormant, and the prompts send by site-notify
        tg=local; [ -r /run/secrets/tender_telegram_token ] && [ -e ${H}/.config/site-agents/telegram-deliver ] && tg=telegram
        # while there is no Telegram, say so plainly in the prompt (the start task of 14:16Z left its "up" undelivered)
        prompt() { cat "$1"; [ "$tg" = telegram ] || printf '\nTelegram is not in use for reports yet: whatever you would send Christoph, send it with site-notify.\n'; }
        job() {  # name schedule deliver prompt-file [--paused]: created if missing, else schedule, delivery and prompt set
          id=$(jq -r --arg n "$1" '(.jobs? // .)[] | select(.name == $n) | .id' "$J" 2>/dev/null | head -1)
          if [ -z "$id" ]; then
            hermes cron create --name "$1" --deliver "$3" --failure-deliver local --workdir /work/tender/hermes/seed-lab \
              ''${5:+--paused --paused-reason site/agents/README.md} "$2" "$(prompt "$4")" >/dev/null && echo "created $1"
          else hermes cron edit "$id" --schedule "$2" --deliver "$3" --prompt "$(prompt "$4")" >/dev/null && echo "$1 ($id): $2, to $3, prompt from the repo"; fi
        }
        # site-watch: every 10 minutes, created paused (the orchestrator resumes it at start). morning-report and
        # startup: run by the host; active (Hermes won't run a paused job) on a ten-year interval, so never on their own
        # every 15 min: measured 20260930 with Qwen to itself, a run with a small replay took 8.5 min (8 calls, 16-95 s each)
        job site-watch "every 15m" local ${H}/.config/site-agents/prompts/periodic-task.txt paused
        # its scripted pre-check: a healthy tick makes no model call ({"wakeAgent": false})
        hermes cron edit "$(jq -r '(.jobs? // .)[] | select(.name == "site-watch") | .id' "$J")" --script site-watch-check.sh >/dev/null && echo "site-watch: pre-check site-watch-check.sh"
        job morning-report "every 3650d" "$tg" ${H}/.config/site-agents/prompts/morning-report.txt
        job startup "every 3650d" "$tg" ${H}/.config/site-agents/prompts/start-task.txt
        # the start task in its own unit, not waited for (a switch waited 19 min on it, 20260930)
        # only when the gateway itself has just started: a deploy that changes this unit re-runs it without a Hermes start
        up=$(( $(cut -d' ' -f1 /proc/uptime | cut -d. -f1) - $(systemctl --user show tender-hermes -p ActiveEnterTimestampMonotonic --value) / 1000000 ))
        if [ -e ${H}/.config/site-agents/started ] && [ "$up" -lt 180 ]; then systemctl --user start --no-block tender-hermes-startup && echo "hermes: start task started"
        else echo "hermes: no start task (gateway up ''${up}s)"; fi
      '';
    };
    # Hermes's start task (the rulebook's "at every start"): `hermes cron run` runs it in this process
    tender-hermes-startup = {
      unitConfig = only; after = [ "tender-hermes.service" ]; environment = env;
      serviceConfig = { Type = "exec"; TimeoutStartSec = "infinity"; RuntimeMaxSec = "150min"; };
      script = ''
        [ -e ${H}/.config/site-agents/paused/hermes ] && [ "$(cat /var/lib/site-agents/active)" != hermes ] && { echo "hermes is paused by decision ($(head -1 ${H}/.config/site-agents/paused/hermes)): skipped"; exit 0; }
        sleep 20   # the gateway settled
        ${hermesSolo} startup
      '';
    };
    # Hermes's gateway (Telegram when its token exists; its scheduler either way)
    tender-hermes = {
      unitConfig = only; wantedBy = [ "default.target" ]; after = [ "tender-config.service" ]; wants = [ "tender-config.service" ];   # wants: a config refresh at a deploy must not restart the agent
      environment = env // { SITE_AGENT = "hermes"; SEED_REPO = "/work/tender/hermes/seed-lab"; };
      serviceConfig = { Restart = "always"; RestartSec = 10; WorkingDirectory = "/work/tender/hermes/seed-lab"; };
      script = ''
        # Telegram only once bound to the owner's chat (his id from his /start): unbound, it would take any sender
        if [ -r /run/secrets/tender_telegram_token ] && [ -s ${H}/.config/site-agents/telegram-chat ]; then
          c=$(cat ${H}/.config/site-agents/telegram-chat); TELEGRAM_BOT_TOKEN=$(cat /run/secrets/tender_telegram_token)
          export TELEGRAM_BOT_TOKEN TELEGRAM_ALLOWED_USERS=$c TELEGRAM_HOME_CHANNEL=$c
        fi
        exec ${H}/.local/bin/hermes gateway run
      '';
    };
  };

  # vendor builds (Claude Code, Hermes's Python from uv) are dynamically linked for generic Linux
  programs.nix-ld.enable = true;

  # the sandbox (site/runbooks/sandbox.md): on libvirt's NAT network on infra, reached through infra
  # site2, in Tender's scope since 20261004 (Christoph): its host key, checked against the recorded one
  programs.ssh.knownHosts.site2 = { hostNames = [ "100.64.0.12" "site2" ]; publicKey = "ssh-ed25519 AAAA...REPLACE-WITH-YOUR-PUBLIC-KEY"; };
  programs.ssh.knownHosts.sandbox = { hostNames = [ "192.168.122.155" ]; publicKey = "ssh-ed25519 AAAA...REPLACE-WITH-YOUR-PUBLIC-KEY"; };
  programs.ssh.extraConfig = ''
    Host sandbox
      HostName 192.168.122.155
      ProxyJump root@192.168.1.10
  '';

  systemd.tmpfiles.rules = [
    "d /work/tender 0700 tender tender -"
    "d /var/lib/site-agents 0755 root root -"
    # the active flag: written only by the orchestrator (root); `none` until the orchestrator names an agent
    "f /var/lib/site-agents/active 0644 root root - none"
    # site-redact's metric (seed_redaction_ok, RedactionUnavailable): the node exporter's textfile, written by tender
    "f /var/lib/prometheus-node-exporter-text/site-redact.prom 0644 tender tender -"
  ];

  # flow 2 carries the agents' homes (transcripts, memory, schedulers, logs) and the flag, from before they start
  services.restic.backups.work.paths = lib.mkAfter [ "/home/tender" "/var/lib/site-agents" ];
}
