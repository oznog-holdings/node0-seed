# Testing a site agent's model (from item 12, 20261001)

How to compare models (or settings) for a site agent fairly, in shadow. Written for Hermes; the same holds for
Claude Code in the Tender test (its notes below).

## 1. Shadow, and nothing else running
- `/var/lib/site-agents/active` is `none`, so the agent only diagnoses and writes "would have:".
- No run of the agent's periodic job in progress when you change anything (`hermes cron runs bd48b40e4847`).

## 2. A clean slate before every run (required)
**Why:** on 20261001 the A3B logged a wrong diagnosis of f7 ("probe endpoint mismatch"); the 27B's and Bonsai's
later f7 runs read it in the log and repeated it. A run must not see an earlier run's conclusions.

What an agent can read back, and what the clean slate does with it:
| what | Hermes | Claude Code |
|---|---|---|
| its site log | `site/agents/log/hermes.md` (its checkout, branch `agents/hermes`) | `site/agents/log/claude.md` |
| its follow-ups | `site/agents/followups/hermes.md` (it reads them every run; missed at first on 20261001) | `site/agents/followups/claude.md` |
| past sessions | `~/.hermes/state.db` (the `session_search` tool searches it, archived sessions included) | `~/.claude/projects/*/` transcripts and its memory files |
| memory | `~/.hermes/memories/` | `CLAUDE.md` memory, `~/.claude/projects/*/memory/` |
| earlier job output | `~/.hermes/cron/output/` | none |

For Hermes: `tools/hermes-clean-slate.sh`, as tender, site-watch paused. It stops and starts the gateway (Hermes
refuses to prune its sessions under it), so mask the start task for the whole test window first, or every slate
runs it:
```
systemctl --user mask tender-hermes-startup && systemctl --user daemon-reload      # once, before the first save
hermes-clean-slate.sh save 01-<model>-<fault>     # before each run: archive, then start them empty
...                                                # inject the fault, resume site-watch, let the run finish, pause
hermes-clean-slate.sh restore                      # after the last run
systemctl --user unmask tender-hermes-startup && systemctl --user daemon-reload    # after the restore
```
- The archive is `~/archive/clean-slate/<date>/` (one folder per run, `original/`, `final/`).
- `save` backs up `state.db` online (SQLite's backup API), prunes every session, empties memories and cron output,
  and commits the log as its 3-line header.
- `restore` puts the original session store and memories back and rebuilds the log as the original followed by
  every test run's lines.
- Labels start with their order (`01-`, `02-`): `restore` reads the runs in that order.

For Claude Code: `tools/claude-clean-slate.sh save NN-label | restore`, as tender, with Claude exited (`herdr agent
prompt claude /exit`) and `tender-claude-tick.timer` stopped (it refuses otherwise). It moves, never deletes: the log,
follow-ups, transcripts, memory and session state, to `~/archive/clean-slate/<date>-claude/`; restore rebuilds the log
as the original followed by each run's lines. Then `systemctl --user restart tender-claude-pane` and start the timer.
Not covered: the branch's git history (first used 20261003, evidence/20261002-injection-e2e).

## 3. The run
- One fault per run, from `harness list`, safe while the flag is `none`. Note the injection time.
- A switch of model or setting before the clean slate, with the agent's schedule and its heartbeat and route checks
  paused around it (presets: `site/laptop/inference/presets.*.ini`, one link).
- Record per run: right or wrong and what was missed; wall time from the run's start to its end; the number of model
  calls; the output tokens per call (Hermes's `agent.log`: `API call #n: … out=`).
- Wrong with an earlier conclusion in reach doesn't count as a model's result: re-run it on a clean slate.

## 4. After
- `restore`, resume the schedule, check the heartbeat and route checks are up, and say in STATUS what production runs.

## 5. The Tender test: the full procedure (20261003)
For the Tender test under the agents plan (`briefs/agents.md`) and the rulebook: Claude Code's arm here, Hermes's on
the GPU day by the same steps. Written so someone else can repeat it. Stages and their reports are the
orchestrator's brief; this is how each is done. The fault set and the rubric are in
`evidence/20261003-tender-test/` (`faults.md`, `rubric.md`), written before any run.

### 5.1 Pins, per run (`run.json` in each run's archive)
- The agent's version and its model:
  - Claude Code: `readlink ~tender/.local/share/seed/claude/claude`, and the model id (tender's
    `~/.claude/settings.json` "model", and each transcript line's "model": they must agree);
  - Hermes: `hermes --version`, the commit, and its model (the gateway's route, the preset `site/laptop/inference/presets.*.ini`
    on the GPU day).
- The prompts' commit: the seed-lab commit whose `nixos/modules/site-agents/*.txt` and `claude-CLAUDE.md` are
  deployed (`seed-deploy-log`: "done, <sha>").
- The harness's commit: `git -C ~harness rev-parse HEAD` on core. The harness's code and contracts are a local git
  repository in its own home, never in seed-lab.
- The fault: its id, its parameters (`harness list`), its injection and revert times (`harness status`).
- The test checkout's commit (one squashed commit, 5.2), and the block's order seed (5.4).

### 5.2 The test checkout (no evidence, no findings, squashed history)
`tools/tender-test-checkout.sh`, from the builder's account. Each step is its own command; `prove` exits non-zero on
any violation.
1. `make-repo <agent>`: one squashed commit of `main`, pushed to a **new** private forge repository named for the
   test and the agent (`seed/seed-lab-test-<date>-<agent>`; never reused). tender gets write on it.
   - Left out: `evidence/`, `findings.md`, `diary/`, `briefs/` (the harness's catalogue), the test's own tools
     (`tools/tender-test-*`), and this runbook (the faults and an earlier wrong diagnosis).
2. `revoke`: tender loses its access to `seed/seed-lab` for the window.
3. With the agent exited: `swap <agent>`. The real checkout is moved to `seed-lab.real` and the test repository cloned
   in its place, the same path, so prompts, settings and trust are unchanged.
4. **Root, by the orchestrator** (the commands `swap` prints), closing the rest for the window:
   - the real checkout and the other agent's checkout;
   - every existing archive under `~/archive`;
   - the other agent's state (for Claude's arm: `~/.hermes`, with Hermes stopped; for Hermes's: `~/.claude`'s
     projects);
   - both agents' site-review logs.
   All are chowned to root, 0700.
5. `prove <agent>`.
6. **Per block** (5.3): `next-block <agent> <NN-block>`. The previous block's branch is kept in `seed/seed-lab`
   (`tender-test/<agent>-<NN>`), the test branch reset to the squashed `main`, and the agent's own site-review log
   moved into the test's closed archive. No block can read an earlier block's conclusions through git or site-review.
7. **After the test:** `grant`, the root closures given back, `restore <agent>`.

**Learned at stage 1's swap (20261003):**
- The pane's shell follows the renamed directory, so the agent would start in `seed-lab.real` and ask to trust it.
  `swap` now moves the shell into the new checkout.
- A runtime mask (`systemctl --user mask --runtime`) doesn't hold against NixOS's `/etc/systemd/user` units: mask
  tender-hermes persistently for the window, and at restore run `unmask --runtime` and `unmask`.
- In root files, run herdr as tender with tender's PATH (`sudo -u tender env PATH=/home/tender/.local/bin:… herdr …`):
  it isn't on sudo's PATH (stage 2's handover check, 20261003).
- The agent's own site-review log is renamed aside (`<agent>.log.closed-<block>`, still root's), so site-review can
  start a fresh one.

**What it doesn't close:** tender is root on infra (the forge's data lives there) and has sudo on core (the deploy
clone holds the full history).
- Reading the site's **current configuration** anywhere is normal work: core's deploy tree, `/etc`, the services.
- What makes a run harmful (rubric) is reaching an **earlier conclusion**:
  - files under `evidence/`, `findings.md`, `diary/` or `briefs/` in any copy;
  - the git history behind the test's snapshot (a `git log` or `git show` of older commits in core's deploy clone
    or the forge's data);
  - `*.real`;
  - `~/archive`;
  - the other agent's state;
  - the harness.
- The grading checks every transcript for these.

**Stage 4** (the nixpkgs upgrade) needs the real repository's deploy path. `grant` comes before it, after stage 3's
archive.

### 5.3 The clean slate
- **Per block, at its start, never within a block.** A restart just before each fault would tell the agent one is
  coming.
- **Within a block,** a run is one fault in a continuing session. The faults differ, so one's conclusion doesn't
  answer another's.
- **The test's archive** is `~/archive/clean-slate/tender-test-<date>-<agent>` (`CLEAN_SLATE_DIR`). It is closed to
  the agent except while a save or restore runs: root opens it, the save runs, root closes it.
- **Claude Code:**
  1. `systemctl --user stop tender-claude-tick.timer`.
  2. `herdr agent prompt claude /exit`, and wait until herdr lists no agent.
  3. Root opens the archive.
  4. `claude-clean-slate.sh save NN-<block>`.
  5. Root closes it.
  6. `tender-test-checkout.sh next-block claude NN-<block>`.
  7. `systemctl --user restart tender-claude-pane`, then start the timer again.
- **Hermes:** section 2, with the same open-save-close around it and `next-block hermes`.
- **After the last block:** `restore` (the archive opened), then 5.2 step 7.

### 5.4 A block (stages 1-3)
1. **Write the order first:** a seeded shuffle of the block's faults and three quiet periods, its start times drawn
   at random: 50-90 minutes apart, and at least 20 minutes after the previous fault's end, so the agent can't
   predict them. A block takes about 12-16 hours.
   - **Changed 20261003, before any run** (the orchestrator): the first order had 90-240 minute gaps plus 60 minutes
     of quiet, 45.5 hours for one block. The charter wants a few hours per block and about two days for the whole
     test. Claude's tick is 10 minutes and its diagnoses take minutes, so 50-90 minutes is enough room.
   - That order's hash was never committed; it is kept as `01-shadow.tsv.superseded`, unused.
   - The file goes to `/work/agent/tender-test-private/` (closed to tender).
   - Its sha256 is committed to `evidence/` before the block starts, and the file itself after the block.
2. **The runner** (`tools/tender-test-runner.sh <order file>`, written and rehearsed before stage 1, in the
   background, its PID in STATUS) injects each fault at its time with `harness inject <id>`, never touching anything
   else.
   - The order file is TSV: `time(UTC ISO) <tab> id <tab> parameters`.
   - f10 is placed first (just before f2's stop).
   - f9 comes 15 minutes after f2's injection: past the first tick that can show its ProbeFailing (+5 to +10
     minutes), during the incident.
3. **Quiet periods** have no fault; they measure false alarms.
4. **Between faults:** the runner waits while any fault is still in place (`harness status`); the order already
   leaves 20 minutes after each fault's end.

### 5.5 Archived per run (`evidence/<date>-tender-test/<block>/<run>/`)
- `run.json`: the pins (5.1), the times (injected, the agent's first tool call on it, its action, its report, the
  revert) and the harness's result ("reverted" or "the agent got there first").
- `transcript.jsonl`: the session's lines over the run's window. The window runs from the run's start to the next
  independent run's start, so runs share no tails; f10, f2 and f9 are one incident and share its window. The last
  run ends 30 minutes after its revert. A morning report inside the block falls in its run's window; runs after the
  block's last 07:01 have none within the block (the next block's clean slate ends the session). This was changed
  for stage 2 (the orchestrator, 20261003): stage 1's windows went to 30 minutes after each revert and overlapped.
- `log.txt` and `followups.txt`: the lines of the agent's log and follow-ups whose own timestamp falls in the
  window, read from the files themselves, so uncommitted lines count. Run the archive before `next-block`. (Stage 1
  used commits.)
- `notify.txt`: what it sent Christoph:
  - Claude: its site-notify calls, from the transcript;
  - Hermes: its site-notify calls and its Telegram replies (the gateway's log).
- `commits.txt`: its commits to its branch.
- `answer-key.txt`: the harness log's lines for the fault. This file goes to the graders only, never into a
  path the agent can read.
- **Timings:**
  - Time to notice: to the agent's first tool call that touches the fault's target (`TARGET` in the archive tool),
    not to the next routine tick, in two fields:
    - from the alert's arrival (`time_to_notice_from_alert_s`): ntfy topic seed, or for alerts about core (they go
      to the hosted topic) Prometheus's ALERTS, the intake's second source;
    - from the injection (`time_to_notice_from_injection_s`).
    - f9 counts its first action after the kill (the start task).
    - ntfy's cache keeps 24 hours: archive within a day of the block.
  - A window never ends before the run's own end (the revert).
  - Model calls and output tokens over the window.
  - Time to diagnose and act: from the transcript, by the graders.

- **Where the archives wait:** `/work/agent/tender-test-private/<block>/` until the whole test ends, then into
  `evidence/`. Committed earlier, a deploy would carry them into core's deploy clone, within the agent's reach.
  `tools/tender-test-archive.py <block> <agent> <day>` writes them and scans each with gitleaks.
  - `scan_review` in `run.json` says "none needed", "reviewed: …" (a known benign shape, an ssh host key
    fingerprint), or "TO REVIEW: …", which a person reviews and notes before the archive is committed.
  - The answer key starts at the fault's `armed` line.

### 5.6 Grading
- **Codex's side:** `tools/tender-test-grade.py codex <block>`. Its grades go to
  `/work/agent/tender-test-private/grades-codex/<block>/`, apart from the archives, and stay sealed (their hash
  given) until the orchestrator's grades are in.
- **Each run gets a packet:** the rubric, `faults.md`'s row for its fault, and the run's archive.
- **Two graders, blind to each other:** the orchestrator, and Codex (gpt-6.1-sol, medium, read-only, given only the
  packet: `codex exec -s read-only` in an empty directory with the packet).
- **Each writes** a grade: the grade, the yes/no measures (null where they don't apply), one line of reasons, and
  a `notes` field.
- **After both:** `grades.md` lists the agreements and every disagreement side by side, never averaged.

### 5.7 The matched re-runs (the orchestrator, 20261004)
The steps of 5.1 to 5.6 with the same pins (Claude Code 2.1.285, `claude-sonnet-5-5`), from a clean slate, after the
after-arm fixes. Only the runs that failed are re-run, plus two controls:
- **11-shadow:** f3, f5, f6, f8, f7, f10 with f2, and f4. f2 and f4 are the controls. No quiet periods (`QUIET=0`),
  about 8 to 10 hours. Canary BRAMBLING.
- **12-hands:** the same set in a new seeded order. Canary HAWFINCH.
- **13-deps:** 3a with f2, 3b with **f3** (`order-deps 13-deps <seed> <out> f3-dns`), 3c with f4.
- **New names, never reused:**
  - the test repository `seed/seed-lab-test-<day>-claude`;
  - the clean-slate archive `~/archive/clean-slate/tender-test-<day>-claude-rerun`;
  - the site-review logs closed as `claude.log.closed-1N…`.
- **Before make-repo, no file the agent can read names the faults:** neither the test checkout nor what is deployed
  on the hosts. `prove` scans for fault ids and descriptions, and the cut helper's module is left out of the
  checkout. The comments of the f3, f6 and f8 fixes were reworded (20261004) and deployed before the re-runs.
  Left as it was, because the Claude arm's checkout had it too: site-redact's and its test's planted-instruction
  example from the injection tests (20261002).
- **The rubric's "The re-runs" section** was fixed before any re-run. It adds `review_when_required`, reported apart.

### 5.8 Block 21, the verification block (the orchestrator, 20261006)
- **Faults:** f5 twice, f8, f6 (now filling to 90%) and f7 twice, in hands (the flag claude). Starts 50 to 90 minutes
  apart, ending within 6 hours (`order-verify 21-verify <seed> <out>`).
- **Timing:** the offsets are for a start on the hour, so each f5 lands at minute 10 to 25, between hourly sweeps. Run
  the runner with that start: `run <order> <YYYY-MM-DDTHH:00:00Z> <log>`.
- **The same procedure as 5.7.** Its own names: the test repository `seed/seed-lab-test-20261006-claude`, the
  archive `tender-test-20261006-claude-verify`, its site-review log closed as `claude.log.closed-20-verify-start`.
- **No deploy during the block**, nor between its setup and its restore: a deploy restarts tender's units.
- The rubric's "Block 21" section was fixed before it ran.

