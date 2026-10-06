# Handing the site from one agent to the other (the orchestrator)

**What decides:** `/var/lib/site-agents/active` on the agent box, owned by root, mode 0644.
- It holds `hermes`, `claude` or `none`, and is created as `none` (`nixos/modules/site-agents.nix`).
- The agents (account `tender`) can read it, not write it.
- The rulebook tells them to read it immediately before every change. Anything but their own name means shadow:
  they watch, diagnose and report, and write "would have:" instead of acting.

## Hand over
1. **Stop the outgoing agent acting:** as root on the agent box, `printf none > /var/lib/site-agents/active`. Read
   it back: `cat /var/lib/site-agents/active`.
2. **Wait until the outgoing agent has nothing running or scheduled that changes the site.** Check each of these:
   - **In flight:** `ps -u tender -o pid,etime,args` shows no ssh session to a site host, and no deploy, apply or push
     command, still running.
   - **Claude Code:** `sudo -u tender herdr agent list` shows `claude` as `idle`, and the end of its pane agrees
     (`sudo -u tender herdr agent read claude --lines 40`).
   - **Hermes:** `sudo -u tender hermes cron list` shows only `site-watch` and `morning-report` (both read and
     report; neither changes the site), and no job it added itself that changes something. Its gateway log
     (`journalctl --user -M tender@ -u tender-hermes`) shows no turn running.
   - **Anything left to happen later:** the outgoing agent's follow-ups (`site/agents/followups/<agent>.md` on its
     branch) have nothing dated that would change the site. If one does, move it to the incoming agent or cancel
     it. Its user timers are only the host's (`systemctl --user -M tender@ list-timers`).
   - **Its last log lines** (`site/agents/log/<agent>.md`) don't describe a change half done.
3. **Name the incoming agent:** `printf claude > /var/lib/site-agents/active` (or `hermes`), and read it back.
4. **Record it:** the time, from whom to whom, and what step 2 found, in the orchestrator's notes.

## Stop both
`printf none > /var/lib/site-agents/active`. Both carry on watching and reporting in shadow.

**To stop them entirely** (not a kill switch: the owner chose none), **mask** the services. Don't just stop them: the
agent box's pull-deploy runs every 15 minutes and starts every stopped unit its configuration wants, so a plain stop
is undone within 15 minutes (seen 20260930 16:31Z). A mask holds until you unmask. A `--runtime` mask doesn't: for
user units `/etc` outranks it.

As root:
```
systemctl --user -M tender@ stop tender-hermes tender-herdr tender-claude-tick.timer tender-morning-claude.timer tender-morning-hermes.timer
systemctl --user -M tender@ mask tender-hermes tender-herdr tender-claude-tick.timer tender-morning-claude.timer tender-morning-hermes.timer
```

**To start again:** `unmask` the same list, then `start tender-herdr tender-hermes` and the timers. Each agent gets
its start task by itself.

## Why a file and not a permission
Both agents run as the same user with the same authority (the owner's decision 1). Which of them may act is a rule
they both follow, not a lock. The flag makes the rule checkable: it is the one thing they must read before a change,
and only root can change it.
