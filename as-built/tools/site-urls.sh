#!/usr/bin/env bash
# site-urls.sh [--check]: the site's own host and service names (site/dns/rewrites.yaml) into
# nixos/modules/site-agents/site-names.txt (20261006: "ns1" was masked as a person's name), and its probe URLs (site/infra/monitoring/targets) into
# nixos/modules/site-agents/site-urls.txt, the list site-redact lets through with their paths (20261004: a failing
# probe's URL must reach the agent; any other path on a site host masks). The flake's root is nixos/, so the list lives
# there; run this after changing the targets. --check: exit 1 if the list differs from the targets.
set -euo pipefail
cd "$(dirname "$0")/.."
out=nixos/modules/site-agents/site-urls.txt
want=$(grep -rho 'https\?://[^" ,]*' site/infra/monitoring/targets/ | sed 's|/$||' | sort -u)
names_out=nixos/modules/site-agents/site-names.txt
names=$(python3 -c 'import yaml; n=yaml.safe_load(open("site/dns/rewrites.yaml")); print("\n".join(sorted(set(n["hosts"]) | set(n.get("services") or {}))))')
if [ "${1:-}" = --check ]; then diff <(echo "$want") "$out" >/dev/null && diff <(echo "$names") "$names_out" >/dev/null && echo "site-urls: as the targets and rewrites.yaml" || { echo "site-urls: differs from the targets or rewrites.yaml: run tools/site-urls.sh"; exit 1; }
else echo "$want" > "$out"; echo "$names" > "$names_out"; echo "$out: $(wc -l < "$out") URLs; $names_out: $(wc -l < "$names_out") names"; fi
