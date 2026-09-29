#!/bin/bash
# restic on infra, in the pinned container, with the 0600 env file (writer key: no delete).
# Paths are mounted at their own names, so snapshots show real paths. Cache on the pool.
exec docker run --rm -i --env-file /mnt/data/system/secrets/restic-infra.env --hostname infra \
  -v /mnt/data/system/restic-cache:/root/.cache/restic -v /mnt/data/appdata:/mnt/data/appdata:ro -v /mnt/data/system/restore-test:/mnt/data/system/restore-test \
  restic/restic:0.19.1@sha256:136600b6ff6843d61d355f7f71f460a166429f35de6fd11b568fece3c9a4d510 "$@"
