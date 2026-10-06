#!/usr/bin/env bash
# site-watch's pre-check (item 11, 20260930): the scripted half of Hermes's periodic task, run by Hermes's scheduler
# before the agent (`hermes cron … --script site-watch-check.sh`). On a healthy tick it does the whole task without
# the model and ends with {"wakeAgent": false}, so Hermes makes no model call; otherwise it prints what it found,
# which goes into Hermes's prompt, and Hermes does the periodic task as before.
#   healthy = the intake works, nothing arrived since the cursor, and nothing is firing (the Watchdog aside), or
#             only what was already firing at the last wake, under 2 hours ago (a long incident re-wakes every 2 h)
#   healthy tick: site-intake ack, a log line (site/agents/log/hermes.md, not committed), site-heartbeat
#   anything else: no ack, no heartbeat: the agent does them (and doesn't ping if the intake is broken)
set -uo pipefail
export SITE_AGENT=${SITE_AGENT:-hermes}
S=$HOME/.local/state/site-watch; mkdir -p -m 700 "$S"
log=${SEED_REPO:-/work/tender/hermes/seed-lab}/site/agents/log/hermes.md
now=$(date -u +%FT%TZ)
new=$(site-intake next 2>&1); rc=$?                 # 0 something new, 1 nothing new, 2 or 3 (or other) the intake is broken
firing=$(site-intake firing 2>&1); frc=$?
set_now=$(printf '%s\n' "$firing" | grep -E '^(CRITICAL )?FIRING ' | sed 's/ since .*//' | sort | sha256sum | cut -c1-16)
[ -z "$(printf '%s\n' "$firing" | grep -E '^(CRITICAL )?FIRING ')" ] && set_now=none
last_set=$(cat "$S/woken-set" 2>/dev/null || echo none); last_at=$(cat "$S/woken-at" 2>/dev/null || echo 0)
age=$(( $(date +%s) - last_at ))
# the hourly sweep (20261004): on the first tick of each hour, site-sweep; a finding wakes Hermes with it, like an alert
m=$(date -u +%M); if [ $((10#$m)) -lt 15 ] && [ $rc -ne 2 ] && [ $rc -ne 3 ]; then
  sw=$(site-sweep 2>&1); swrc=$?   # a sweep that fails is a finding too (Codex, 20261004)
  [ $swrc -ne 0 ] && sw="$sw
FINDING: UNCHECKED: site-sweep itself failed (exit $swrc)"
  if grep -q '^FINDING' <<<"$sw"; then echo "site-sweep (the hourly look where no alert may tell you):"; echo "$sw"; echo "$new"; exit 0; fi
elif [ $rc -ne 2 ] && [ $rc -ne 3 ]; then   # (a broken intake goes to its own path below, first)
  # every other tick, the quick sweep (20261006): failed units, reboot flags, stale producers. It wakes Hermes when its
  # findings differ from the last ones it woke for, or every 2 hours while they persist (a standing pending reboot
  # must not wake it every tick)
  q=$(site-sweep --quick 2>&1); qrc=$?
  [ $qrc -ne 0 ] && q="$q
FINDING: UNCHECKED: site-sweep --quick itself failed (exit $qrc)"
  # numbers out of the hash ("last ran N min ago" changes every tick: Codex, 20261006)
  qset=$(grep '^FINDING' <<<"$q" | sed 's/[0-9][0-9]*/N/g' | sort | sha256sum | cut -c1-16)
  [ -z "$(grep '^FINDING' <<<"$q")" ] && qset=none
  qlast=$(cat "$S/quick-set" 2>/dev/null || echo none); qat=$(cat "$S/quick-at" 2>/dev/null || echo 0)
  if [ "$qset" != none ] && { [ "$qset" != "$qlast" ] || [ $(( $(date +%s) - qat )) -ge 7200 ]; }; then
    echo "$qset" > "$S/quick-set"; date +%s > "$S/quick-at"
    echo "site-sweep --quick (between the hourly sweeps):"; echo "$q"; echo "$new"; exit 0
  fi
  [ "$qset" = none ] && echo none > "$S/quick-set"
fi
if [ $rc -eq 1 ] && [ $frc -eq 0 ] && { [ "$set_now" = none ] || { [ "$set_now" = "$last_set" ] && [ $age -lt 7200 ]; }; }; then
  if ! ackout=$(site-intake ack 2>&1); then
    echo "THE INTAKE IS BROKEN: site-intake ack failed ($ackout). An incident: diagnose it, do not ping, and tell Christoph with site-notify (your periodic task, step 5)."; echo "$new"; exit 0
  fi
  flag=$(cat /var/lib/site-agents/active 2>/dev/null || echo unreadable)
  if [ "$set_now" = none ]; then what="nothing new, nothing firing"; else what="nothing new; still firing what was handled at $(date -u -d @"$last_at" +%H:%MZ)"; fi
  # a tick that can't log or ping isn't healthy: wake Hermes with the reason (Codex's review)
  if ! printf -- '- %s intake: %s; active=%s (shadow unless hermes). Scripted check, no model call.\n' "$now" "$what" "$flag" >> "$log"; then
    echo "site-watch-check: the intake was healthy and acked, but the log line couldn't be written to $log. Find out why; ping the heartbeat only if you can log."; exit 0
  fi
  if ! hb=$(site-heartbeat 2>&1); then
    echo "site-watch-check: the intake was healthy, acked and logged, but site-heartbeat failed: $hb"; exit 0
  fi
  echo '{"wakeAgent": false}'
  exit 0
fi
# wake Hermes: record the firing set it is woken for, and hand it what the check saw
echo "$set_now" > "$S/woken-set"; date +%s > "$S/woken-at"
if [ $rc -ge 2 ] || [ $frc -ne 0 ]; then
  echo "THE INTAKE IS BROKEN (site-intake next exit $rc, firing exit $frc; 2 = a source unavailable, 3 = site-intake itself failed). An incident: diagnose it, do not ping, and tell Christoph with site-notify (your periodic task, step 5)."
fi
echo "The scripted pre-check found something (intake exit $rc; firing check exit $frc). What it saw:"
echo "--- site-intake next:"; printf '%s\n' "$new"
echo "--- site-intake firing:"; printf '%s\n' "$firing"
echo "Do the periodic task below as usual (site-intake next again shows the same, from the same cursor)."
