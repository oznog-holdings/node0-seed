# Another way up: laptop, agent, compute

**In plain terms.** Many people want agents and private models without running storage, DNS and
a monitoring server. This path skips the infrastructure and core boxes: the laptop you already
have, a small box for your agents, and a box for models, with hosted services standing in for the
rest. It costs less and needs less looking after, and it relies more on the internet and on
services you do not run.

**Status.** A design, not yet run end to end. Every piece was built on the bench, but on top of
the infrastructure and core boxes of the main ladder. A build of this path on its own, on a spare
mini PC, is planned; this page will say what it found.

## The path

| step | you add | from the main ladder |
|---|---|---|
| 0 | backups from the laptop to a cloud bucket | [rung 0](rungs/0-laptop/), unchanged |
| 1 | the agent's own small box | [rung 2](rungs/2-agent/), with the stand-ins below |
| 2 | a box for models | [rung 4](rungs/4-compute/) and [4b](rungs/4b-models/) |

**The agent box and the compute box can be one machine.** An Apple-silicon Mac with enough memory
can run the agents and the models. That is cheaper and fine for one person. Separate boxes keep
the agents working while models are swapped or benchmarked: on 20260930 a load test on the
compute Mac pushed it into swap and stopped its model server for 15 minutes, and an agent on the
same box would have stopped with it.

## What the infrastructure and core boxes did, and the stand-in

| on the main ladder | on this path |
|---|---|
| backups to a local server, then off-site | each box backs up straight to a cloud bucket, encrypted (restic) |
| a password manager on the site | a hosted one (Bitwarden) |
| a forge with the site's repository | a hosted git store (GitHub or similar); still strongly recommended, because it keeps the history and the record of every change |
| names and certificates for the site's services | Tailscale's own names and certificates |
| DNS and time | the router and public servers |
| the model gateway | on the agent box |
| alerts and their monitoring | a hosted ntfy topic, and a hosted heartbeat check |

**Rule: the watcher must not live on the box it watches.** On the main ladder the core box keeps
alerts alive when infrastructure is down. Here there is no second box, so the dead-man check must
be hosted: the agent box pings it, and the hosted service raises the alarm when the pings stop. A
watcher on the agent box itself goes silent when the agent box fails.

## What you give up

- **Your data at hosted services.** The vault and the backups are encrypted before they leave,
  but they live on someone else's machines.
- **A local copy to restore from.** Restores come over the internet, at its speed.
- **Names and alerts without the internet.** With the internet down, alerts cannot reach
  you, and anything that depends on the tailnet or a hosted service may stop; devices on the
  LAN still reach each other by address.
- **Anything kept alive when the agent box is down.** On the main ladder, core carries names,
  time and alerts through an infrastructure outage. Here, when the agent box is down, so are the
  gateway and the agents.

**Move to the main ladder when** a restore over the internet would take longer than you can wait,
when the data should not leave the house even encrypted, or when one box going down should not
take the agents and the alerts with it.

## Decisions and options

**A hosted heartbeat, not a self-hosted one.** It is the only thing on this path that must not
share the agent box's fate.
*Would change it:* a second always-on device you already own, such as a Raspberry Pi, can host the
dead-man check instead; that is the start of [rung 3](rungs/3-core/).

**A hosted git store, even though the site is small.** The agents' changes, their reasons and the
rulebook all live in it. Without it, there is no record of what an agent changed and no way to
roll a change back by its commit.

**Agents on a hosted model, models for utilities.** On a laptop-class compute box, local models
are right for search, transcription and redaction, and too slow for an agent that diagnoses
([rung 4](rungs/4-compute/), [the agents](agents/)).

## Costs

The hardware is rungs 2 and 4 of the main ladder ([costs](costs.md)), without the
infrastructure and core boxes. The stand-ins add subscriptions: a cloud bucket for backups, a
password manager, and the hosted heartbeat and ntfy plans, several of which have free tiers.
