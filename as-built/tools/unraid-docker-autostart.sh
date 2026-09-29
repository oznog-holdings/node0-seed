#!/usr/bin/env bash
# The Docker page's own autostart switch (UpdateConfig.php action=autostart), with the UI session of
# tools/unraid-login.sh. Written 20260929: the technitium container (ns2) was created through the page
# with autostart off, so it stayed down after infra's power-off test. Usage: unraid-docker-autostart.sh <container> on|off
set -euo pipefail
c=$1; case ${2:-} in on) a=true ;; off) a=false ;; *) echo "on|off"; exit 2 ;; esac
J=${UNRAID_STATE:-$HOME/.local/state/seed/unraid}/cookies
csrf=$(curl -s -b "$J" http://192.168.1.10/Docker | grep -oP 'var csrf_token\s*=\s*"\K[^"]+')
[[ -n $csrf ]] || { echo "no UI session: run tools/unraid-login.sh"; exit 1; }
curl -s -b "$J" --data-urlencode "action=autostart" --data-urlencode "container=$c" --data-urlencode "auto=$a" --data-urlencode "wait=" \
  --data-urlencode "csrf_token=$csrf" http://192.168.1.10/plugins/dynamix.docker.manager/include/UpdateConfig.php >/dev/null
ssh -o BatchMode=yes -o LogLevel=ERROR root@192.168.1.10 "grep -qx '$c' /var/lib/docker/unraid-autostart" && echo "$c: autostart on (read back)" || echo "$c: autostart OFF (read back)"
