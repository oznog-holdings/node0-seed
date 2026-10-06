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
set -euo pipefail
cmd=${1:?save LABEL or restore}; H=$HOME/.hermes; S=$HOME/.local/state/site-watch
R=/work/tender/hermes/seed-lab; LOG=$R/site/agents/log/hermes.md; FU=$R/site/agents/followups/hermes.md
# the test window's folder: CLEAN_SLATE_DATE, else an open window (a folder with no final/ yet: a window can run past
# midnight, 20261002), else today
open=$(for d in "$HOME"/archive/clean-slate/*/; do [ -d "$d" ] && [ ! -d "$d/final" ] && basename "$d"; done 2>/dev/null | tail -1)
A=$HOME/archive/clean-slate/${CLEAN_SLATE_DATE:-${open:-$(date -u +%Y%m%d)}}; mkdir -p -m 700 "$A"
hermes cron runs bd48b40e4847 2>&1 | head -1 | grep -q running && { echo "a site-watch run is in progress: wait"; exit 1; }
[ "$(systemctl --user is-enabled tender-hermes-startup 2>/dev/null)" = masked ] || { echo "mask tender-hermes-startup first (the runbook)"; exit 1; }
backup() { python3 -c 'import sqlite3,sys; s=sqlite3.connect(sys.argv[1]); d=sqlite3.connect(sys.argv[2]); s.backup(d); d.close(); s.close()' "$1" "$2"; }
keep() {  # dir: everything a run could read back; written to dir.tmp, checked, then published
  local d=$1 t=$1.tmp; rm -rf "$t"; mkdir -m 700 "$t"
  backup "$H/state.db" "$t/state.db"
  cp -p "$LOG" "$t/hermes.md"; cp -p "$FU" "$t/followups.md"
  tar -C "$H" -czf "$t/memories+cron-output.tgz" memories cron/output
  mkdir "$t/site-watch"; for f in woken-set woken-at; do if [ -e "$S/$f" ]; then cp -p "$S/$f" "$t/site-watch/"; fi; done
  python3 -c 'import sqlite3,sys; sqlite3.connect(sys.argv[1]).execute("select count(*) from sessions").fetchone()' "$t/state.db"
  [ -s "$t/hermes.md" ] && [ -s "$t/followups.md" ] && tar -tzf "$t/memories+cron-output.tgz" >/dev/null
  touch "$t/.complete"; rm -rf "$d"; mv "$t" "$d"
}
complete() { [ -f "$1/.complete" ] && [ -s "$1/state.db" ] && [ -s "$1/hermes.md" ] && [ -s "$1/followups.md" ] && [ -s "$1/memories+cron-output.tgz" ]; }
up() { systemctl --user start tender-hermes; }
case $cmd in
save)
  label=${2:?label}
  [[ $label =~ ^[0-9]{2}-[A-Za-z0-9._-]+$ ]] || { echo "label: NN-name (01-27b-f2)"; exit 64; }
  [ -e "$A/$label" ] && { echo "$A/$label exists: a new label"; exit 1; }
  systemctl --user stop tender-hermes; trap up EXIT   # first: no chat writes between the archive and the slate
  [ -d "$A/original" ] || keep "$A/original"
  complete "$A/original" || { echo "$A/original is incomplete: fix it before any slate"; exit 1; }
  keep "$A/$label"                                   # before anything changes
  hermes sessions prune --older-than 0 --include-archived --include-pinned --yes >/dev/null
  # sessions that never ended (a killed run, an open chat) are beyond prune: deleted one by one
  for s in $(python3 -c 'import sqlite3,sys; [print(r[0]) for r in sqlite3.connect(sys.argv[1]).execute("select id from sessions")]' "$H/state.db"); do
    hermes sessions delete --yes "$s" >/dev/null; done
  left=$(python3 -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute("select count(*) from sessions").fetchone()[0])' "$H/state.db")
  [ "$left" = 0 ] || { echo "sessions left after the prune: $left"; exit 1; }
  find "$H/memories" "$H/cron/output" -mindepth 1 -delete
  rm -f "$S/woken-set" "$S/woken-at"                 # the wake gate wakes on whatever fires
  head -3 "$A/original/hermes.md" > "$LOG"; head -3 "$A/original/followups.md" > "$FU"
  git -C "$R" add site/agents/log/hermes.md site/agents/followups/hermes.md
  git -C "$R" commit -q -m "hermes: clean slate for model test run $label (archived in ~/archive/clean-slate)"
  echo "clean slate: $label (archived in $A/$label)" ;;
restore)
  complete "$A/original" || { echo "$A/original is incomplete: restore by hand"; exit 1; }
  [ -e "$A/final" ] && { echo "$A/final exists: restored already?"; exit 1; }
  systemctl --user stop tender-hermes; trap up EXIT
  keep "$A/final"
  backup "$A/original/state.db" "$H/state.db"
  find "$H/memories" "$H/cron/output" -mindepth 1 -delete; tar -C "$H" -xzf "$A/original/memories+cron-output.tgz"
  rm -f "$S/woken-set" "$S/woken-at"; for f in "$A/original/site-watch/"*; do if [ -e "$f" ]; then cp -p "$f" "$S/"; fi; done
  # each run's archive holds the lines the run before it wrote (the first one holds the original): appended in
  # label order (labels start with it: 01-, 02-, ...), then final/, the last run's
  { cat "$A/original/hermes.md"
    for d in $(ls -1 "$A"); do
      case $d in original|final|*.tmp) continue;; esac
      cmp -s "$A/$d/hermes.md" "$A/original/hermes.md" || tail -n +4 "$A/$d/hermes.md"
    done
    tail -n +4 "$A/final/hermes.md"; } > "$LOG.new"
  mv "$LOG.new" "$LOG"; cp -p "$A/original/followups.md" "$FU"
  git -C "$R" add site/agents/log/hermes.md site/agents/followups/hermes.md
  git -C "$R" commit -q -m "hermes: restored after the model tests (log: the original, then the test runs' lines; follow-ups: the original)"
  echo "restored from $A" ;;
*) echo "save LABEL | restore"; exit 64 ;;
esac
