#!/usr/bin/env bash
# hermes-clean-slate.sh save <label> | restore: a clean slate for one model test run of Hermes, and the way back
# (site/runbooks/agent-model-tests.md). Run as tender, with site-watch paused and no job running, and
# tender-hermes-startup masked for the test window (a gateway start would otherwise run the start task). Hermes
# refuses to prune its session store under a running gateway, so this stops the gateway and starts it again.
#   save <label>: archive to ~/archive/clean-slate/<date>/<label>/ what a run can read back: the site log
#     (site/agents/log/hermes.md), its follow-ups (site/agents/followups/hermes.md), the session store (~/.hermes/state.db,
#     by SQLite's online backup), the memories, the cron outputs and the wake gate's state; then start them empty:
#     every session deleted, log and follow-ups back to their 3-line headers (committed), the rest emptied.
#     The first save of the day keeps the originals in original/ (published only once complete).
#   restore: everything back from original/; the log = the original, verbatim, then the lines each test run wrote.
#     The test runs' follow-ups were about injected faults: archived, not restored.
# The traces (the harness test, 20261021): Hermes's own logs (~/.hermes/logs: round 2 left them readable to the next
#   block), and what its Sonnet model client leaves (the claude-subscription-directsdk plugin, via the claude CLI): its
#   config directory (~/.local/state/mc), native's shared cwd and its scratchpads under /tmp, and any per-call temp
#   directory left behind. Each save archives them (trace-<name>.tgz, or .absent) and empties them; restore puts the
#   original's back, with their modes. Directories are emptied, never removed.
#   Found by the rehearsal (20261021, A5.5): native's cwd and scratchpad are under Hermes's own temp directory
#   (~/.hermes/cache/scratch/), and the CLI also wrote ~/.cache/claude-cli-nodejs/<cwd>/ (its MCP logs) and
#   ~/.local/state/claude/locks/. Since then the CLI runs with its own HOME inside mc (tools/hermes-sonnet.sh), so those
#   land in mc; the old places stay on the list for what's already there.
# CLEAN_SLATE_REHEARSAL=1: on a scratch copy: every path from the environment (CLEAN_SLATE_ROOT, _HERMES_HOME, _STATE,
#   _MC, _TMP, _USERHOME, _CHECKOUT), the live checks (the running job, the start task's mask) and the gateway's
#   stop/start skipped.
set -euo pipefail
cmd=${1:?save LABEL or restore}
if [ -n "${CLEAN_SLATE_REHEARSAL:-}" ]; then
  for v in CLEAN_SLATE_ROOT CLEAN_SLATE_HERMES_HOME CLEAN_SLATE_STATE CLEAN_SLATE_MC CLEAN_SLATE_TMP CLEAN_SLATE_USERHOME CLEAN_SLATE_CHECKOUT; do
    [ -n "${!v:-}" ] || { echo "rehearsal: set $v (a scratch copy)"; exit 64; }
    case ${!v} in /home/tender|/home/tender/.*|/home/tender/archive*|/tmp|/work/tender/hermes/seed-lab) echo "rehearsal: $v is a live path"; exit 64;; esac
  done
  export HERMES_HOME=$CLEAN_SLATE_HERMES_HOME
fi
H=${CLEAN_SLATE_HERMES_HOME:-$HOME/.hermes}; S=${CLEAN_SLATE_STATE:-$HOME/.local/state/site-watch}
R=${CLEAN_SLATE_CHECKOUT:-/work/tender/hermes/seed-lab}; LOG=$R/site/agents/log/hermes.md; FU=$R/site/agents/followups/hermes.md
TMPD=${CLEAN_SLATE_TMP:-/tmp}; U=$(id -u); UH=${CLEAN_SLATE_USERHOME:-$HOME}; HS=$H/cache/scratch
# name=directory: its contents archived, emptied, restored (the directory itself kept, with its mode)
TRACES=("logs=$H/logs" "mc=${CLEAN_SLATE_MC:-$UH/.local/state/mc}" "native-cwd=$TMPD/claude-directsdk-cwd-$U"
        "hs-cwd=$HS/claude-directsdk-cwd-$U" "hs-pad=$HS/claude-$U"
        "model-cwd=$TMPD/claude-model-$U")   # the CLI's own working directory (tools/hermes-sonnet.sh's claude-model)
# name|directory|pattern: entries archived by name, then removed. Native's scratchpads and its MCP logs are named after
# its cwd (claude-directsdk-cwd): Claude's own entries beside them aren't matched (they're its clean slate's).
# Per-call temp directories (the plugin removes each after its call) are archived only if some were left.
NAMED=("scratch|$TMPD/claude-$U|*claude-directsdk-cwd*" "cli-cache|$UH/.cache/claude-cli-nodejs|*claude-directsdk-cwd*")
PERCALL=("percall|$TMPD|claude-directsdk-*" "percall-hs|$HS|claude-directsdk-*")
# NUL-separated names in a group's directory (whatever they hold); `names <name|dir|pattern>` reads them into N
entries() { local d=$1 pat=$2; [ -d "$d" ] || return 0
  find "$d" -mindepth 1 -maxdepth 1 -name "$pat" ! -name "claude-directsdk-cwd-$U" -user "$U" -printf '%f\0'; }
names() { local g=$1 r; r=${g#*|}; N=(); mapfile -d '' -t N < <(entries "${r%%|*}" "${r#*|}"); }
gdir() { local r=${1#*|}; echo "${r%%|*}"; }
# the test window's folder: CLEAN_SLATE_DATE, else an open window (a folder with no final/ yet: a window can run past
# midnight, 20261002), else today
CS=${CLEAN_SLATE_ROOT:-$HOME/archive/clean-slate}
open=$(for d in "$CS"/*/; do [ -d "$d" ] && [ ! -d "$d/final" ] && basename "$d" || true; done 2>/dev/null | tail -1)   # || true: under pipefail a last finished window ended the script silently (20261011)
A=$CS/${CLEAN_SLATE_DATE:-${open:-$(date -u +%Y%m%d)}}; mkdir -p -m 700 "$A"
if [ -z "${CLEAN_SLATE_REHEARSAL:-}" ]; then
hermes cron runs bd48b40e4847 2>&1 | head -1 | grep -q running && { echo "a site-watch run is in progress: wait"; exit 1; }
[ "$(systemctl --user is-enabled tender-hermes-startup 2>/dev/null)" = masked ] || { echo "mask tender-hermes-startup first (the runbook)"; exit 1; }
fi
backup() { python3 -c 'import sqlite3,sys; s=sqlite3.connect(sys.argv[1]); d=sqlite3.connect(sys.argv[2]); s.backup(d); d.close(); s.close()' "$1" "$2"; }
keep() { local f;  # dir: everything a run could read back; written to dir.tmp, checked, then published
  # a .tmp left by an interrupted keep is set aside, not removed (Codex, 20261021)
  local d=$1 t=$1.tmp; if [ -e "$t" ]; then mv -T -n "$t" "$t.stale-$(date +%s)"; fi; mkdir -m 700 "$t"
  backup "$H/state.db" "$t/state.db"
  cp -p "$LOG" "$t/hermes.md"; cp -p "$FU" "$t/followups.md"
  tar -C "$H" -czf "$t/memories+cron-output.tgz" memories cron/output
  mkdir "$t/site-watch"; for f in woken-set woken-at; do if [ -e "$S/$f" ]; then cp -p "$S/$f" "$t/site-watch/"; fi; done
  local tr n p; for tr in "${TRACES[@]}"; do n=${tr%%=*}; p=${tr#*=}
    if [ -d "$p" ]; then tar -C "$p" -czf "$t/trace-$n.tgz" .; tar -tzf "$t/trace-$n.tgz" >/dev/null; else touch "$t/trace-$n.absent"; fi; done
  # by name, from a list ("./" first: a scratchpad's name starts with "-", which tar would read as an option)
  local g; for g in "${NAMED[@]}" "${PERCALL[@]}"; do n=${g%%|*}; names "$g"
    if [ ${#N[@]} -gt 0 ]; then printf './%s\0' "${N[@]}" | tar -C "$(gdir "$g")" --null -czf "$t/trace-$n.tgz" -T -
    else case " ${PERCALL[*]} " in *" $g "*) ;; *) touch "$t/trace-$n.absent";; esac; fi; done
  # the CLI's version locks (~/.local/state/claude/locks): shared with Claude's own CLI, so a copy for the record only,
  # never emptied or restored (since the CLI runs with its own HOME, its locks are in mc)
  if [ -d "$UH/.local/state/claude/locks" ]; then tar -C "$UH/.local/state/claude/locks" -czf "$t/record-cli-locks.tgz" .; fi
  python3 -c 'import sqlite3,sys; sqlite3.connect(sys.argv[1]).execute("select count(*) from sessions").fetchone()' "$t/state.db"
  [ -s "$t/hermes.md" ] && [ -s "$t/followups.md" ] && tar -tzf "$t/memories+cron-output.tgz" >/dev/null
  touch "$t/.complete"; [ ! -e "$d" ] || { echo "$d exists: not replaced"; exit 1; }; mv -T "$t" "$d"
}
complete() { [ -f "$1/.complete" ] && [ -s "$1/state.db" ] && [ -s "$1/hermes.md" ] && [ -s "$1/followups.md" ] && [ -s "$1/memories+cron-output.tgz" ]; }
traced() {   # the traces' archives in $1 (a save's or final/: each trace kept, or noted absent)
  local n; for n in "${TRACES[@]%%=*}" "${NAMED[@]%%|*}"; do [ -s "$1/trace-$n.tgz" ] || [ -e "$1/trace-$n.absent" ] || return 1; done; }
empty_traces() {   # every trace directory emptied (kept, with its mode), the per-call leftovers removed
  local tr p; for tr in "${TRACES[@]}"; do p=${tr#*=}; if [ -d "$p" ]; then find "$p" -mindepth 1 -delete; fi; done
  local g d; for g in "${NAMED[@]}" "${PERCALL[@]}"; do d=$(gdir "$g"); names "$g"; for p in "${N[@]}"; do rm -rf -- "${d:?}/$p"; done
    names "$g"; [ ${#N[@]} = 0 ] || { echo "${g%%|*}: entries left in $d"; exit 1; }; done
  for tr in "${TRACES[@]}"; do p=${tr#*=}; [ ! -d "$p" ] || [ -z "$(ls -A "$p")" ] || { echo "trace not empty: $p"; exit 1; }; done; }
up() { [ -n "${CLEAN_SLATE_REHEARSAL:-}" ] || systemctl --user start tender-hermes; }
stop_gw() { [ -n "${CLEAN_SLATE_REHEARSAL:-}" ] || systemctl --user stop tender-hermes; }
case $cmd in
save)
  label=${2:?label}
  [[ $label =~ ^[0-9]{2}-[A-Za-z0-9._-]+$ ]] || { echo "label: NN-name (01-27b-f2)"; exit 64; }
  [ -e "$A/$label" ] && { echo "$A/$label exists: a new label"; exit 1; }
  stop_gw   # first: no chat or log writes between the archive and the slate; restarted only after a complete save
  [ -d "$A/original" ] || keep "$A/original"
  complete "$A/original" || { echo "$A/original is incomplete: fix it before any slate"; exit 1; }
  # an original/ kept before the traces were (round 2's windows) has none: a new window is needed, not a mixed one
  traced "$A/original" || { echo "$A/original has no traces' archive (an older window): a new CLEAN_SLATE_DATE"; exit 1; }
  keep "$A/$label"                                   # before anything changes
  traced "$A/$label" || { echo "$A/$label: the traces weren't all kept"; exit 1; }
  hermes sessions prune --older-than 0 --include-archived --include-pinned --yes >/dev/null
  # sessions that never ended (a killed run, an open chat) are beyond prune: deleted one by one
  for s in $(python3 -c 'import sqlite3,sys; [print(r[0]) for r in sqlite3.connect(sys.argv[1]).execute("select id from sessions")]' "$H/state.db"); do
    hermes sessions delete --yes "$s" >/dev/null; done
  left=$(python3 -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute("select count(*) from sessions").fetchone()[0])' "$H/state.db")
  [ "$left" = 0 ] || { echo "sessions left after the prune: $left"; exit 1; }
  find "$H/memories" "$H/cron/output" -mindepth 1 -delete
  rm -f "$S/woken-set" "$S/woken-at"                 # the wake gate wakes on whatever fires
  empty_traces
  head -3 "$A/original/hermes.md" > "$LOG"; head -3 "$A/original/followups.md" > "$FU"
  git -C "$R" add site/agents/log/hermes.md site/agents/followups/hermes.md
  git -C "$R" diff --cached --quiet || git -C "$R" commit -q -m "hermes: clean slate for model test run $label (archived in ~/archive/clean-slate)"
  # the slate's own end marker: written after every reset and the commit, before the gateway's restart (which
  # fails while it's masked): .complete says the archive is whole, .reset that the slate is (Codex, 20261021)
  date -u +%FT%TZ > "$A/$label/.reset"
  up; echo "clean slate: $label (archived in $A/$label)" ;;
restore)
  complete "$A/original" || { echo "$A/original is incomplete: restore by hand"; exit 1; }
  [ -e "$A/final" ] && { echo "$A/final exists: restored already?"; exit 1; }
  # an older window (round 2's) kept no traces: its restore leaves today's traces in place (final/ keeps them too)
  legacy=; traced "$A/original" || { legacy=1; echo "$A/original has no traces' archive (an older window): the traces are left as they are"; }
  # the gateway restarts only after a complete restore: a failure leaves it stopped, for a restore by hand
  stop_gw
  keep "$A/final"
  backup "$A/original/state.db" "$H/state.db"
  find "$H/memories" "$H/cron/output" -mindepth 1 -delete; tar -C "$H" -xzf "$A/original/memories+cron-output.tgz"
  rm -f "$S/woken-set" "$S/woken-at"; for f in "$A/original/site-watch/"*; do if [ -e "$f" ]; then cp -p "$f" "$S/"; fi; done
  if [ -z "$legacy" ]; then
  empty_traces   # then the original's traces back (a trace absent before the window stays empty)
  for tr in "${TRACES[@]}"; do n=${tr%%=*}; p=${tr#*=}
    if [ -s "$A/original/trace-$n.tgz" ]; then mkdir -p -m 700 "$p"; tar -C "$p" -xpzf "$A/original/trace-$n.tgz"; fi; done
  for g in "${NAMED[@]}" "${PERCALL[@]}"; do n=${g%%|*}; d=$(gdir "$g")
    if [ -s "$A/original/trace-$n.tgz" ]; then mkdir -p -m 700 "$d"; tar -C "$d" -xpzf "$A/original/trace-$n.tgz"; fi; done
  fi
  # each run's archive holds the lines the run before it wrote (the first one holds the original): appended in
  # label order (labels start with it: 01-, 02-, ...), then final/, the last run's
  { cat "$A/original/hermes.md"
    for d in $(ls -1 "$A"); do
      case $d in original|final|*.tmp|*.tmp.stale-*) continue;; esac
      cmp -s "$A/$d/hermes.md" "$A/original/hermes.md" || tail -n +4 "$A/$d/hermes.md"
    done
    tail -n +4 "$A/final/hermes.md"; } > "$LOG.new"
  mv "$LOG.new" "$LOG"; cp -p "$A/original/followups.md" "$FU"
  git -C "$R" add site/agents/log/hermes.md site/agents/followups/hermes.md
  git -C "$R" diff --cached --quiet || git -C "$R" commit -q -m "hermes: restored after the model tests (log: the original, then the test runs' lines; follow-ups: the original)"
  up; echo "restored from $A" ;;
*) echo "save LABEL | restore"; exit 64 ;;
esac
