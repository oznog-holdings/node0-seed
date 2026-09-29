#!/bin/bash
# Flow 2 for the laptop (design › Backups: "Backrest on each machine backs up every two hours to a
# restic rest-server on the infra box started with --append-only, one repository per machine").
# compute's seed user: its home to rest:https://rest.seed.example.com/compute/, host pinned, no
# forget or prune here (the server is the one writer). Plain restic from launchd, as the agent
# box uses plain restic from systemd (F-LAPTOP-BACKUP). Installed as
# ~/.local/libexec/seed/backup.sh; launchd runs it at :30 past odd hours (co.oznog.seed.backup).
# Desktop, Documents and Downloads are excluded: macOS privacy control (TCC) denies them to a
# launchd job even for their owner (seen 20260924, rc 3), and seed keeps nothing there;
# check-laptop fails if any of them holds a file (F-LAPTOP-TCC).
# Credentials: ~/.config/seed/restic.env (0600; from the vault items "rest-server compute" and
# "restic seed compute"), never in this file, the plist or argv.
set -euo pipefail
umask 077
export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
H=/Users/seed; state=$H/.local/state/seed; mkdir -p "$state"
log() { echo "$(date -u +%FT%TZ) $*"; }
env=$H/.config/seed/restic.env
# fail closed at the source: the home, the key that makes this box a laptop, and the credentials
[ -s "$env" ] && [ -s "$H/.ssh/id_ed25519" ] && [ -d "$H/.ssh" ] || { log "FAIL: source or credentials missing"; echo 1 > "$state/backup.rc"; exit 1; }
set -a; . "$env"; set +a
rc=0
restic backup --host compute --tag laptop --retry-lock 10m --exclude-caches --one-file-system \
  --exclude "$H/.config/seed" --exclude "$H/Library" --exclude "$H/.Trash" \
  --exclude "$H/Desktop" --exclude "$H/Documents" --exclude "$H/Downloads" \
  --exclude "$H/.cache" --exclude "$H/.npm" --exclude "$H/.local/share/claude/versions" \
  --exclude "$H/.local/lib/node_modules" --exclude "$H/.local/state/seed/backup.log" \
  "$H" || rc=$?
# restic: 0 ok, 3 = snapshot made but some files unreadable (e.g. a privacy prompt denied): a failure
echo $rc > "$state/backup.rc"
if [ $rc = 0 ]; then date +%s > "$state/backup.last"; log "backup ok"; else log "backup FAILED rc=$rc"; fi
exit $rc
