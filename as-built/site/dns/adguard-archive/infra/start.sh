#!/bin/sh
# Each start replaces AdGuard's config with the one rendered from the repo (mounted read-only
# at /seed), the container form of NixOS's `mutableSettings = false`: a UI change lasts
# until the next restart and the drift check (bin/check-dns) reports it before that.
set -e
cp /seed/AdGuardHome.yaml /opt/adguardhome/conf/AdGuardHome.yaml
exec /opt/adguardhome/AdGuardHome --no-check-update -c /opt/adguardhome/conf/AdGuardHome.yaml -w /opt/adguardhome/work
