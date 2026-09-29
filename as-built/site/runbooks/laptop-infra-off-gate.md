# The laptop's last gate: one real operation from compute with infra off and caches cold

**Status: PASSED 20260924 10:08 MDT** (diary `20260924.md`). infra off 09:59:39 (clean powerdown)
to 10:03:25 (vault 200); the operation at 10:01:02 to 10:01:17 restored doc-08.txt from B2,
sha256 ada7d557…; the dead-man paused 15:59:14Z to 16:03:48Z, up 16:05:06Z; after-checks 16/16,
compute READY, snapshot 544709b6. infra powered on by itself after plug2 came back.

Why: the laptop is where a person stands when the site is broken (design › Secrets: "every host
gets every laptop's key, or the laptop in the shop is the one that locks you out"; the recovery
pack is rehearsed "with the infra box off"). compute takes the laptop role only after it has
done real work with infra gone. Then laptop can go back to its owner (its own step, below).

**Roles.** The orchestrator shuts infra down and powers it up (clean shutdown, then plug2 off
and on: infra powers on after AC loss). The builder runs everything else from the agent box
over ssh to compute (`seed@192.168.1.20`). Nothing here changes a configuration.

**The operation** (`site/laptop/infra-off-op.sh`, on compute as seed): restore a document of the
site's (`/mnt/data/documents/doc-08.txt`) from the offsite store (B2, flow 1), with the
credentials the laptop decrypts from core's `secrets.age` with its own key; restic with
`--no-cache`; read-only on the bucket. On the way it ssh-es to core by name and asks core's
ntfy for its health. Rehearsed with infra up on 20260924 14:51Z: snapshot 12043725, 648 bytes,
sha256 ada7d557…, equal to the live file on infra.

## Preconditions (the builder, before asking for the window)

- `site/laptop/admin-setup.sh` has been run on compute by a person with an admin account
  (Needs hands), and `check-laptop` on compute says **READY** with infra up.
- The window avoids the backup jobs: start on an **even hour at :00**, done by :25 (compute
  backs up at :30 past odd hours, the agent box at :45 past odd hours, the rest-server prunes
  at 02:00). Not 01:00 to 03:00 (backups, prune) or 03:30 (nightly build).
- The external dead-man is **paused for the window** (orchestrator, 20260924: a planned test
  must not page the owner): `tools/healthchecks-window.sh pause` just before the shutdown,
  `resume` once infra is back. Pause sets `manual_resume` first, because Healthchecks.io
  un-pauses a check at its next ping and Alertmanager pings every 1 to 2 min. Tested 20260924
  14:59 to 15:10Z: a ping sent while paused (Alertmanager's webhook counter 207 → 208) was
  ignored; resume gave `new`, then `up` at the next ping.
- Expected noise while infra is off, not faults: the agent box's watcher
  posts "FAILING" for the front door; pull-deploys on the agent box and core fail closed (the
  forge is on infra); core's power watch loses infra's apcupsd. The UPS has no shutdown
  master during the window: keep it short.

## The sequence

| step | who | what | pass |
|---|---|---|---|
| 0 | builder | on the agent box: `site/bin/check-after-reboot` (baseline); on compute: `check-laptop` | 16/16; READY |
| 0b | builder | on the agent box: `tools/healthchecks-window.sh pause`; say "ready" to the orchestrator | `status=paused manual_resume=true` |
| 1 | orchestrator | clean shutdown of infra: Unraid web UI, Main › Array Operation › **Shutdown** (Unraid stops VMs, containers and the array itself) | infra stops answering ping; plug2's draw falls to standby |
| 2 | orchestrator | **plug2 off**; say the time | |
| 3 | builder | caches cold. compute: `sudo -n /usr/bin/dscacheutil -flushcache; sudo -n /usr/bin/killall -HUP mDNSResponder` (seed's named sudo). Router: `killall -HUP dnsmasq` over ssh (clears dnsmasq's cache and re-reads its hosts; no configuration change, D.06 hash before and after) | both commands exit 0; D.06 unchanged |
| 4 | builder | compute: `check-laptop --infra-off` | READY, with "ssh root@infra: unreachable, as expected" |
| 5 | builder | compute: `~/.local/share/seed/laptop/infra-off-op.sh` | "infra: unreachable"; restored, sha256 ada7d557… (the file hasn't changed since 20260923 21:51 MDT; a different hash means it changed on infra, compared after step 7) |
| 6 | orchestrator | **plug2 on**; say the time. infra boots by itself (firmware: power on after AC loss) | |
| 6b | builder | when infra answers and Alertmanager runs: `tools/healthchecks-window.sh resume` (waits for the next ping) | `status=up manual_resume=false` |
| 7 | builder | when infra answers: on the agent box `site/bin/check-after-reboot`; on compute start the backup (`sudo -n /bin/launchctl kickstart system/co.oznog.seed.backup`), then `check-laptop` | 16/16 (the dead-man is up after 6b); READY |
| 8 | builder | diary: times, outputs, anything that alerted and when it resolved | |

Stop on any failure at steps 4 to 5 and go straight to step 6: the gate is failed, not the site.
If the window is abandoned before step 1, run `resume` at once: a paused dead-man watches nothing.

## After the gate: laptop goes back to its owner (its own step)

laptop (`seed-builder@laptop`) leaves every place it was put, in one commit and its checks:
`nixos/keys.nix` (`laptop`) and the agent box's `admin` and `agent`; `.sops.yaml` `&laptop_rung0`
and `tools/secrets-rekey.sh` (both secrets files); infra's root (UI form), the router (rpcd,
D.06), `admin@core`, compute's `seed`, agentvm's `admin` and `agent`; and laptop's seed key deleted on
laptop itself. **Done 20260927** (owner: remove and re-encrypt, **don't rotate**; the owner deletes
laptop's seed user). Checked from outside with the public key alone: `tools/key-probe.sh` asks each
login whether it would accept the key (SSH publickey query), before (positive control) and after.
Recorded: old encrypted versions stay in git history, readable with laptop's key while that key exists.
