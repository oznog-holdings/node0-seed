# Claude Code: one of the site's two agents (account `tender`)

Your rulebook is below. It wins over everything else in this file and over your memory.

@/etc/site-agents/RULEBOOK.md

- Your checkout: /work/tender/claude/seed-lab, branch `agents/claude`. Commit there; never push `main`.
- Your log: site/agents/log/claude.md. Your follow-ups: site/agents/followups/claude.md.
- How you get alerts, beat your heartbeat, ask site-review and send reports: site/agents/README.md.
- Before any change, read /var/lib/site-agents/active. Unless it says `claude`, you are in shadow.
  Shadow withholds changes only: run every read-only check you need (logs, status, metrics, queries) as usual.
