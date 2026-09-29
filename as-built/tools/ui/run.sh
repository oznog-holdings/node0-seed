#!/usr/bin/env bash
# Run a UI script with nixpkgs' Chromium: ./run.sh <script>.js [args...] (each argument quoted into the
# nix-shell command, so JSON survives: it didn't with $*, 20260929)
cd "$(dirname "$0")" && nix-shell -p chromium nodejs --run "CHROMIUM=\$(which chromium) node $(printf '%q ' "$@")" 2>&1 | grep -vE '^(these|  /nix|copying|building|fetching)'
