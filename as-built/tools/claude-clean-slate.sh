#!/usr/bin/env bash
# claude-clean-slate.sh save NN-label | restore: Claude Code's clean slate for a test run (site/runbooks/agent-model-tests.md
# › 2, "by hand until scripted"; scripted 20261002 for the injection tests). As tender, with Claude exited and its
# tick timer stopped (the script refuses otherwise), and its heartbeat check paused by whoever runs the test.
#   save NN-label   archive what Claude can read back, then leave it empty:
#                   ~/.claude: projects (transcripts, memory), history.jsonl, sessions, session-env, shell-snapshots,
#                   paste-cache, todos, file-history, plans; the checkout: its log and follow-ups (headers only)
#                   The first save keeps the production state in original/; a later one keeps the previous run's
#                   state in that run's final/. Everything is MOVED, never deleted.
#   restore         the previous run's state to its final/; the original back; the log rebuilt as the original
#                   followed by every test run's lines (labelled), so the runs stay on record; follow-ups as originally
# The archive: ~/archive/clean-slate/<date>-claude/ (original/, run-NN-label/final/). Then start Claude again
# (systemctl --user restart tender-claude-pane) and its timer.
set -euo pipefail
A=${CLEAN_SLATE_DIR:-$HOME/archive/clean-slate/$(date -u +%Y%m%d)-claude}
C=${CLEAN_SLATE_CHECKOUT:-/work/tender/claude/seed-lab}; LOG=site/agents/log/claude.md; FU=site/agents/followups/claude.md
STATE=(projects history.jsonl sessions session-env shell-snapshots paste-cache todos file-history plans)
export PATH=$HOME/.local/bin:$PATH
die() { echo "claude-clean-slate: $*" >&2; exit 1; }
# CLEAN_SLATE_REHEARSAL=1: a rehearsal on copies (HOME and the checkout elsewhere): the live checks skipped
if [ -z "${CLEAN_SLATE_REHEARSAL:-}" ]; then
herdr agent list | jq -e '.result.agents[] | select(.name == "claude")' >/dev/null && die "Claude is running: exit it first"
systemctl --user is-active -q tender-claude-tick.timer && die "stop tender-claude-tick.timer first"
fi
[ "$(git -C $C branch --show-current)" = agents/claude ] || die "the checkout isn't on agents/claude"
keep() {  # keep <dir>: move Claude's state and copy its log and follow-ups there; into <dir>.partial first, renamed when
  # complete, so an interrupted keep is visible (and nothing is ever moved over an existing archive)
  [ -e "$1" ] || [ -e "$1.partial" ] && die "$1 or $1.partial exists: an earlier save or restore stopped midway; reconcile by hand"
  mkdir -p "$1.partial"
  for s in "${STATE[@]}"; do if [ -e ~/.claude/$s ]; then mv -n ~/.claude/$s "$1.partial/"; [ ! -e ~/.claude/$s ] || die "could not move ~/.claude/$s"; fi; done
  cp -a $C/$LOG "$1.partial/claude.md"; cp -a $C/$FU "$1.partial/followups.md"; git -C $C rev-parse HEAD > "$1.partial/HEAD"
  mv -n "$1.partial" "$1"; }
commit() { git -C $C add $LOG $FU; git -C $C commit -q -m "$1" || true; }
last_run() { { ls -d "$A"/run-* 2>/dev/null || true; } | sort | tail -1; }
case ${1:-} in
save)
  l=${2:?label NN-name}; [ -e "$A/run-$l" ] && die "$A/run-$l exists"
  [ -e "$A/RESTORED" ] && die "$A was restored: a new series needs a new CLEAN_SLATE_DIR"
  p=$(last_run); [ -z "$p" ] || [[ "run-$l" > "${p##*/}" ]] || die "labels must sort after the last run (${p##*/})"
  if [ ! -d "$A/original" ]; then keep "$A/original"; else p=$(last_run); [ -n "$p" ] || die "original/ but no run"; keep "$p/final"; fi
  mkdir -p "$A/run-$l"
  head -3 "$A/original/claude.md" > $C/$LOG; head -2 "$A/original/followups.md" > $C/$FU
  commit "claude: clean slate for test run $l (the log and follow-ups archived; restored after the tests)"
  echo "saved; run-$l starts empty: $(ls ~/.claude | tr '\n' ' ')" ;;
restore)
  [ -d "$A/original" ] || die "no $A/original"; [ -e "$A/RESTORED" ] && die "already restored"; p=$(last_run); [ -n "$p" ] && [ ! -d "$p/final" ] && keep "$p/final"
  for s in "${STATE[@]}"; do [ -e ~/.claude/$s ] && die "~/.claude/$s exists after keeping the last run: look first"; [ -e "$A/original/$s" ] && mv "$A/original/$s" ~/.claude/; done
  { cat "$A/original/claude.md"
    for r in $(ls -d "$A"/run-* 2>/dev/null | sort); do
      echo "- (test run ${r##*/run-}, a clean slate, its lines follow; site/runbooks/agent-model-tests.md)"; tail -n +4 "$r/final/claude.md"; done; } > $C/$LOG
  cp -a "$A/original/followups.md" $C/$FU; date -u +%FT%TZ > "$A/RESTORED"
  commit "claude: the clean slate restored (the original log, then the test runs' lines; follow-ups as before)"
  echo "restored: $(ls ~/.claude | tr '\n' ' ')" ;;
*) sed -n '2,13p' "$0"; exit 64 ;;
esac
