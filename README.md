# The Seed

A small self-hosted site for a person and their agents, built one box at a time. This
repository is what you need to build your own: what each rung gives you, the decisions
behind it and the options we met, what it cost and measured, the steps, and the bench's
configuration as it ran.

It was written while an agent built a real Seed from the public pages at
oznog.com/node0/seed, on a bench of spare hardware, from 20260923 to 20260928. Everything
here was run on that bench; anything that was not says so where it appears.

## Where to start

Read [the ladder on the Seed page](https://oznog.com/node0/seed/#the-ladder) first. Then pick the rung you are on:

| Rung | You add | Folder |
|---|---|---|
| 0 | backups from the laptop you already have | [rungs/0-laptop](rungs/0-laptop/) |
| 1 | one infrastructure box: storage, DNS and time, HTTPS, a password manager, a forge, a model gateway, backups, monitoring, an agent VM | [rungs/1-infra](rungs/1-infra/) |
| 2 | the agent gets its own small box | [rungs/2-agent](rungs/2-agent/) |
| 3 | a core box that keeps names, time and alerts alive when infra is down | [rungs/3-core](rungs/3-core/) |
| 4 | a compute box for local models | [rungs/4-compute](rungs/4-compute/) |
| 4b | many kinds of models behind one gateway | [rungs/4b-models](rungs/4b-models/) |
| 5 | the router as the edge, three wifi networks, a second site (built 20260929; double NAT kept) | [rungs/5-edge](rungs/5-edge/) |
| 6 | a dedicated firewall (designed) | [rungs/6-firewall](rungs/6-firewall/) |

Every rung is a complete site for someone. Stop wherever the site does what you need.

## How each rung is written

Every rung folder has the same five parts:

1. **What you get.** The site as a whole at this rung, and what it still cannot do.
2. **Decisions and options.** Each choice we made, the alternatives we met, and what
   would change the choice for you.
3. **Costs and measurements.** What it cost and what we measured, with the conditions
   each figure was taken under.
4. **Runbooks.** The steps. Today each rung page lists its steps in order and links the
   bench's own procedures; full runbooks come from a fresh-agent build (below).
5. **Configuration.** Templates filled from one values file exist for a few pieces, listed in
   [templates/README.md](templates/README.md). For the rest, the rung page points to the
   bench's configuration as it ran.

The bench's actual configuration, scripts and monitoring, as they ran, are in
[as-built/](as-built/), scrubbed only where they touched things outside the Seed.

Across rungs:

- [data/](data/README.md): the measurements, with their conditions.
- [runbooks/](runbooks/): the procedures that span rungs. One is written so far, the recovery pack.
- [pitfalls.md](pitfalls.md): the traps we hit, each with what to do instead.
- [costs.md](costs.md): what each rung costs to buy and to run.
- [decisions/](decisions/): the choices across rungs (not yet written; each rung page carries
  its own).

## Making it yours

Copy [values.example.yaml](values.example.yaml) to `values.yaml` and change it: your
domain, your addresses, your names. The templates read from it. The example uses
documentation addresses (192.168.50.0/24, `site.example.com`). The templates and the example
values hold no real address. [as-built/](as-built/) keeps the bench's own Seed networks
(192.168.1.0/24, with guest and IoT at 192.168.20.0/24 and 192.168.30.0/24), with its domain
shown as `seed.example.com`; nothing in the repository is a serial, a device identifier or a
secret.

## Status

Being written as the build goes. Rungs 0 to 6 were built on the bench by 20260929 (the bench
keeps double NAT, by the owner's decision). Each
rung page gives its checks and figures, and [data/](data/README.md) has the measurements.
Sections not yet written say so.

## What is coming

Built on the same bench, in roughly this order, and added here once each passes its checks on the bench:

- **How to have an agent build your Seed.** The brief, the rules, the containment and the
  checks we used, and the requirements matrix as a checklist your agent can run.
- **The agent kit, two ways.** A long-running Hermes agent, with conversations over Telegram
  (Matrix when its guide lands); and Claude Code running under the herdr session manager,
  reached from a phone with Moshi. Alerts by ntfy for both.
- **Optional services, one guide each.** Home Assistant, Immich, Jellyfin and a media set,
  Paperless with Stirling, n8n, Sure with Fava, and a private Matrix server.
- **An agent that looks after the site.** It reads every alert, checks that backups and
  restore tests keep passing, and fixes routine problems within permissions you write down.
- **Runbooks from a fresh-agent build.** A fresh agent, given only this repository, rebuilds
  rungs 1 and 2, and its steps become the numbered runbooks.

## Licences

Two licences, by directory; [`LICENSE`](LICENSE) at the root maps them.

| What | Licence | What it asks of you |
|---|---|---|
| The writing and data (the rung pages, runbooks, decisions, data, costs, pitfalls) | [CC BY 4.0](LICENSE-content) | Credit Oznog Holdings LLC, link the licence, and say what you changed |
| The configuration and code (`templates/`, `as-built/`, `values.example.yaml`) | [MIT](LICENSE-code) | Keep the copyright and permission notice |
