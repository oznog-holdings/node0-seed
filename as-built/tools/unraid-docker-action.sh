#!/usr/bin/env bash
# The Docker page's own container action (Events.php: start|stop|restart), with the UI session
# from tools/unraid-login.sh and the page's CSRF token (never printed).
set -euo pipefail
action=$1 name=$2; J=$HOME/.local/state/seed/unraid/cookies
id=$(ssh root@192.168.1.10 "docker inspect -f '{{.Id}}' $name" | cut -c1-12)
csrf=$(curl -s -b "$J" http://192.168.1.10/Docker | grep -oP 'var csrf_token\s*=\s*"\K[^"]+')
[[ -n $csrf ]] || { echo "no UI session: run tools/unraid-login.sh"; exit 1; }
curl -s -b "$J" --data-urlencode "action=$action" --data-urlencode "container=$id" --data-urlencode "csrf_token=$csrf" \
  http://192.168.1.10/plugins/dynamix.docker.manager/include/Events.php; echo
