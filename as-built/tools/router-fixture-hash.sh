#!/usr/bin/env bash
# D.06: hash of the lab-owned router state (the firewall sections whose name starts with
# "fixture:", and the wan/wan6 interfaces), read via rpcd uci. Run before and after any
# router change; the two hashes must be identical.
set -euo pipefail
cd "$(dirname "$0")"
fw=$(./router-ubus.sh call uci get '{"config":"firewall"}' | jq -S '[.result[1].values[] | select((.name // "") | startswith("fixture:"))] | sort_by(.name) | map(del(.[".index"]))')
wan=$(./router-ubus.sh call uci get '{"config":"network"}' | jq -S '[.result[1].values | (.wan, .wan6)] | map(del(.[".index"]))')
echo "fixture rules: $(jq length <<<"$fw") ($(jq -r 'map(.name) | join("; ")' <<<"$fw"))"
echo "wan sections: $(jq -r 'map(.[".name"]) | join(",")' <<<"$wan")"
printf '%s\n%s\n' "$fw" "$wan" | sha256sum | cut -d' ' -f1
