#!/bin/bash
# Weekly verify sweep and restore test (design › Backups):
#  - "snapshot freshness per repository, then restic check --read-data-subset=N/26 with N
#    stepping from 1 to 26 across the weeks, kept in a state file and advanced only after a
#    green run"
#  - "a few small files per repository in rotation, compared by hash, with skipped raised as
#    its own alarm. Only restore proves a file comes back."
# Repositories: B2 (restic/infra, flow 1) and every rest-server repository (flow 2).
# Results go to /mnt/data/system/seed-state for the monitoring: <repo>.fresh-age,
# <repo>.check-N, <repo>.check.last, <repo>.restore.result (ok|fail|skipped), .restore.last.
set -uo pipefail
umask 077
state=/mnt/data/system/seed-state; ENVF=/mnt/data/system/secrets/restic-rest.env; ROOT=/mnt/data/backups/rest
scratch=/mnt/data/system/restore-test/weekly-$(date -u +%Y%m%dT%H%M%SZ); mkdir -p "$scratch"
IMG=restic/restic:0.19.1@sha256:136600b6ff6843d61d355f7f71f460a166429f35de6fd11b568fece3c9a4d510
log() { echo "$(date -u +%FT%TZ) $*"; }
rc_all=0

# one function per kind of repository: run restic with its credentials
r_b2()   { /mnt/data/system/seed-bin/restic.sh "$@"; }
r_rest() { local m=$1; shift; grep "^RESTIC_PASSWORD_$m=" "$ENVF" | cut -d= -f2- | tr -d '\n' | docker run --rm -i --hostname infra \
             -v "$ROOT:$ROOT:ro" -v /mnt/data/system/restore-test:/mnt/data/system/restore-test $IMG \
             -r "$ROOT/$m" --password-command 'cat /dev/stdin' --no-cache --no-lock "$@"; }

verify_repo() {  # name, runner..., max_age_seconds, restore_candidates_cmd
  local name=$1 runner=$2 maxage=$3; shift 3
  local N; N=$(cat "$state/$name.check-N" 2>/dev/null || echo 1)
  # freshness
  # newest snapshot in epoch seconds: times come in mixed offsets (Z and -06:00), so compare numbers, not strings
  local newest=0 t e; while read -r t; do e=$(date -d "$t" +%s) && [ "$e" -gt "$newest" ] && newest=$e; done < <($runner snapshots --json --latest 1 2>/dev/null | jq -r '.[].time')
  if [ "$newest" -eq 0 ]; then log "$name: no snapshots"; echo fail > "$state/$name.restore.result"; return 1; fi
  local age=$(( $(date +%s) - newest )); echo "$age" > "$state/$name.fresh-age"
  if [ "$maxage" = dormant ]; then log "$name: dormant, freshness not checked (newest snapshot ${age}s old)"
  else [ "$age" -le "$maxage" ] || { log "$name: newest snapshot ${age}s old (max ${maxage}s)"; rc_all=1; }; fi
  # check a 26th of the data, advancing N only after a green run
  if $runner check --read-data-subset="$N/26" >/dev/null 2>&1; then
    log "$name: check $N/26 ok"; date +%s > "$state/$name.check.last"; echo $(( N % 26 + 1 )) > "$state/$name.check-N"
  else log "$name: check $N/26 FAILED (N stays $N)"; rc_all=1; fi
  # restore test: up to 3 small files, rotating by week number
  local week; week=$(date +%V)
  mapfile -t files < <($runner ls latest --json 2>/dev/null | jq -r 'select(.type=="file" and .size > 0 and .size < 2000000) | .path' | sort)
  if [ ${#files[@]} -eq 0 ]; then log "$name: restore test SKIPPED (no candidates)"; echo skipped > "$state/$name.restore.result"; rc_all=1; return; fi
  local picks=() i; for i in 0 1 2; do picks+=("${files[$(( (10#$week * 3 + i) % ${#files[@]} ))]}"); done
  local tgt="$scratch/$name"; mkdir -p "$tgt"; local inc=(); for f in "${picks[@]}"; do inc+=(--include "$f"); done
  if $runner restore latest --target "$tgt" --verify "${inc[@]}" >/dev/null 2>&1; then
    local ok=1; for f in "${picks[@]}"; do
      [ -s "$tgt$f" ] || { ok=0; log "$name: $f not restored"; continue; }
      # compared with the live file where it is on infra and unchanged since the snapshot
      if [ -f "$f" ] && [ "$f" -ot "$state/backrest-site-data.last" ]; then
        [ "$(sha256sum < "$f")" = "$(sha256sum < "$tgt$f")" ] && log "$name: $f restored, hash = live" || { ok=0; log "$name: $f hash differs from live"; }
      else log "$name: $f restored and verified against the repository (source not on infra)"; fi
    done
    if [ $ok = 1 ]; then echo ok > "$state/$name.restore.result"; date +%s > "$state/$name.restore.last"; else echo fail > "$state/$name.restore.result"; rc_all=1; fi
  else log "$name: restore FAILED"; echo fail > "$state/$name.restore.result"; rc_all=1; fi
}

verify_repo b2-infra r_b2 $((36*3600))
# DORMANT (as in seed-metrics.sh): repositories kept for their snapshots, whose machine no longer
# writes on purpose. Integrity and the restore test still run on what they hold; freshness does not.
DORMANT="agentvm"
for dir in "$ROOT"/*/; do m=$(basename "$dir"); [ -f "$dir/config" ] || continue
  maxage=$((6*3600)); case " $DORMANT " in *" $m "*) maxage=dormant ;; esac
  runner="r_rest $m"; eval "r_$m() { r_rest $m \"\$@\"; }"; verify_repo "rest-$m" "r_$m" $maxage; done
rm -rf -- "$scratch"
[ $rc_all = 0 ] && date +%s > "$state/weekly-verify.last"
exit $rc_all
