#!/usr/bin/env bash
# User Scripts: add a script through the plugin's own backend (exec.php addScript, then saveScript),
# as the build has done since 20260923 (diary 20260923-s3: "Scripts added with the plugin's own
# backend"). The script is a wrapper around a versioned file in /mnt/data/system/seed-bin; its schedule
# is set afterwards on the page (us-schedule3.js for cron, us-schedule-named.js for "start").
# Uses the web session of tools/unraid-login.sh; the CSRF token goes from infra's var.ini into a
# variable, never printed. Usage: us-add-script.sh <name> <seed-bin file> "<one-line purpose>"
set -euo pipefail
name=$1 file=$2 purpose=$3
JAR=${UNRAID_STATE:-$HOME/.local/state/seed/unraid}/cookies
tok=$(ssh -o BatchMode=yes -o LogLevel=ERROR root@192.168.1.10 "sed -n 's/^csrf_token=\"\\(.*\\)\"\$/\\1/p' /var/local/emhttp/var.ini")
[[ $tok =~ ^[A-F0-9]{16}$ ]] || { echo "csrf token not found"; exit 1; }
U=http://192.168.1.10/plugins/user.scripts/exec.php
curl -s -b "$JAR" --data-urlencode "action=addScript" --data-urlencode "scriptName=$name" --data-urlencode "csrf_token=$tok" "$U" >/dev/null
body=$(printf '#!/bin/bash\n# Seed: %s\n# Runs /mnt/data/system/seed-bin/%s (versioned in the site repo). The pool must be mounted; if it is\n# not, this fails loudly.\nexec /mnt/data/system/seed-bin/%s\n' "$purpose" "$file" "$file")
curl -s -b "$JAR" --data-urlencode "action=saveScript" --data-urlencode "script=$name" --data-urlencode "scriptContents=$body" --data-urlencode "csrf_token=$tok" "$U"; echo
unset tok
ssh -o BatchMode=yes -o LogLevel=ERROR root@192.168.1.10 "cat /boot/config/plugins/user.scripts/scripts/$name/name; echo; sha256sum /boot/config/plugins/user.scripts/scripts/$name/script"
printf '%s' "$body" | sha256sum
