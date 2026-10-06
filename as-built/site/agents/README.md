# The site agents: working notes

Two agents look after the site under one rulebook (`RULEBOOK.md`, which wins over this file): **Hermes** (Nous
Research's Hermes Agent on the local Qwen3.8-27B) and **Claude Code** (Sonnet 5.5). Both run on the agent box as the
account `tender`. The brief: `briefs/agents.md`. The orchestrator's handover: `site/runbooks/agents-handover.md`.

## Where things are
| | Hermes | Claude Code |
|---|---|---|
| checkout (your own; never push `main`) | `/work/tender/hermes/seed-lab`, branch `agents/hermes` | `/work/tender/claude/seed-lab`, branch `agents/claude` |
| log (reasoning as you go) | `site/agents/log/hermes.md` | `site/agents/log/claude.md` |
| follow-ups (dated; the scheduler second) | `site/agents/followups/hermes.md` | `site/agents/followups/claude.md` |
| runs as | the service `tender-hermes` (Hermes's gateway: Telegram, its scheduler) | a herdr pane (workspace `claude`), service `tender-claude-pane` |
| model | the gateway route `local-chat`: Qwen3.8-27B, 131,072 tokens | `claude-sonnet-5-5` (the owner's subscription) |
| loads the rulebook | `AGENTS.override.md` in the checkout → `/etc/site-agents/RULEBOOK.md` | `~/.claude/CLAUDE.md` imports `/etc/site-agents/RULEBOOK.md` |

- **Your git author name** says which of you committed. Push your own branch; the orchestrator merges.
- **Which of you may act:** `/var/lib/site-agents/active` holds `hermes`, `claude` or `none`. Read it immediately
  before every change. Anything but your own name means shadow.

## At every start
The host hands you the rulebook's start steps (`start-task.txt`). Claude Code gets them when its pane starts it;
Hermes gets them from its job `startup`, run by `tender-hermes-start` whenever its gateway starts. Read what
changed, replay the alerts since your cursor, beat your heartbeat, and say you are up.

## Every 10 minutes (Claude Code) or 15 (Hermes): the periodic task
The host hands it to you: Claude Code gets it from the timer `tender-claude-tick` when it is idle; Hermes from its
scheduled job `site-watch`. The steps:
1. `site-intake next`: what arrived since your cursor. That is:
   - every alert Alertmanager sent to ntfy (firing and resolved; ntfy keeps 24 h);
   - Prometheus's list of alerts that fired in the same window, including those about core or ntfy, which go to a
     hosted topic you can't read.

   It doesn't move the cursor. If you restart, the next `next` replays from where you last acknowledged.
2. Handle what it shows. `site-intake firing` shows what is firing now.
3. Write a line in your log.
4. `site-intake ack`: the cursor moves to what `next` showed.
5. `site-heartbeat`: pings your Healthchecks check. **Only here, after the work, and only if your intake worked:** a silent check means you are
   stuck, dead or blind, and Healthchecks tells the owner.

## A second opinion: `site-review`
`site-review "the question and the few lines of evidence it needs"` asks Codex (gpt-6.1-sol, medium effort) and
prints the answer.
- It runs confined: it can't read the site's files or secrets.
- What you send leaves the site: never a secret, never a whole log or config file, never personal data.
- If it says Codex is unavailable, carry on without it and say so.
- Your calls are logged in `~/.local/state/site-review/<you>.log`.

## A pull request: `site-pr`
`site-pr "<title>" [<body file>]` (or the body on stdin) opens a pull request from your branch into main, without your
forge token ever reaching you (20261004).
- Your branch is `<you>/<name>` (`claude/...`, `hermes/...`), pushed first. The body is your plan and what you checked.
- If a PR from that branch is already open, it says so and gives you that one.
- It doesn't merge: merging into main and promoting to deploy are the owner's. Ask him through site-notify and wait.
- Your calls are logged in `~/.local/state/site-pr/<you>.log`.

## Reaching Christoph
- **Hermes:** Telegram, to the owner's chat only; every other sender is ignored.
- **Claude Code:** `site-notify "title" "message"` (ntfy topic `seed-agents` on core, read by his phone).
  `--urgent` is for "act now" only.
- **The morning report:** 07:01 local, prompted by the host (`tender-morning-claude`, `tender-morning-hermes`).

## Using the site's tools
- Run them from your own checkout, with `SEED_REPO` set to it.
- The few vault items they need come from a read-only bundle (`SEED_VAULT=bundle`, `site/agents/vault-bundle.txt`).
  You have no vault login, and the rulebook forbids reading credentials out.
- ssh: `root@192.168.1.10` (infra), `admin@192.168.1.12` (core), `root@192.168.1.4` (the access point),
  `root@192.168.1.1` (the firewall), `admin@100.64.0.12` (site2, over the tailnet; since 20261004, Christoph), and
  the sandbox (`site/runbooks/sandbox.md`).
- site2's deploys: only `tools/site2-deploy.sh` (`dry-run`, then `test` with its self-reverting timer, then `confirm`
  after checking it's healthy; `site/runbooks/site2.md`).

## For the orchestrator
- **Start (after the smoke test):** as tender, `touch ~/.config/site-agents/started` and
  `hermes cron resume <site-watch's id>` (`hermes cron list`). Until then the host's periodic and morning timers do
  nothing and Hermes's `site-watch` is paused. `morning-report` and `startup` stay paused: the host runs them.
  `tender-hermes-start` keeps the three jobs' prompts to the repo's texts (`nixos/modules/site-agents/*.txt`).
- **A vanished Claude Code** (its process gone from the pane) is started again by the next tick, with the start task.
- **Stop the periodic work:** remove the marker and `hermes cron pause <site-watch's id>`.
- **Pause one agent by decision:** as tender, write the reason into `~/.config/site-agents/paused/<agent>`, pause
  its periodic work (Hermes: `hermes cron pause <site-watch's id>`; Claude: `systemctl --user stop
  tender-claude-tick.timer`) and its Healthchecks check. While the file exists, `site-heartbeat` never pings for that
  agent and the host's morning and startup runs skip it, so nothing resumes the paused check (20261002: a morning
  run pinged Hermes's paused check, which then went down). To resume: remove the file, resume the work.
- **Versions** (pinned, from each vendor's own channel, sha256-checked):
  - Claude Code 2.1.285;
  - Codex 0.159.2;
  - herdr 0.9.3;
  - Hermes Agent v2026.9.24 (v0.21.5, commit f97608f1).
- **Revoke everything:** `tools/site-agents-revoke.sh`.
