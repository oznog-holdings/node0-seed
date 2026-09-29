# Backrest's config for infra, rendered with jq (input: {"bcrypt64": "<base64 bcrypt of the admin password>"}).
# Applied through Backrest's API (SetConfig) and verified through GetConfig: "Backrest does not
# reload a hand-edited config. Verify through its local API, never the file" (design › Backups).
# No secret here: the repository, its password and the B2 keys are ${VARS} that Backrest expands
# from its environment (the 0600 env file /mnt/data/system/secrets/restic-infra.env).
{
  modno: $modno,
  version: 6,
  instance: "infra",
  auth: { disabled: false, users: [ { name: "admin", passwordBcrypt: .bcrypt64 } ] },
  repos: [ {
    id: "b2-infra",
    uri: "${RESTIC_REPOSITORY}",
    guid: $guid,
    env: [ "RESTIC_PASSWORD=${RESTIC_PASSWORD}", "AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}", "AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}" ],
    # the writer key cannot delete: no prune from here (F-B2KEY); the weekly verify sweep is its own job
    prunePolicy: { schedule: { disabled: true } },
    checkPolicy: { schedule: { disabled: true } },
    autoUnlock: false
  } ],
  plans: [ {
    id: "site-data",
    repo: "b2-infra",
    # design › Backups: documents, finance, photos, appdata, the Forgejo data (its dump) and the flash
    paths: [ "/mnt/data/documents", "/mnt/data/finance", "/mnt/data/photos", "/mnt/data/appdata",
             "/mnt/data/system/identity", "/boot" ],
    # live databases and repositories are covered by their dumps (R1.61); caches and the DNS query log are not backed up
    excludes: [ "/mnt/data/appdata/postgres/data", "/mnt/data/appdata/vaultwarden/data/db.sqlite3*",
                "/mnt/data/appdata/vaultwarden/data/tmp", "/mnt/data/appdata/forgejo/data",
                "/mnt/data/appdata/valkey", "/mnt/data/appdata/adguard/work", "/mnt/data/appdata/backrest",
                "/mnt/data/appdata/caddy/config" ],
    schedule: { cron: "0 1 * * *", clock: "CLOCK_LOCAL" },
    retention: { policyKeepAll: true },
    backup_flags: [ "--host infra" ],
    hooks: [
      { conditions: [ "CONDITION_SNAPSHOT_START" ], onError: "ON_ERROR_FATAL",
        actionCommand: { command: "set -e; now=$(date +%s); d=$(cat /mnt/data/system/seed-state/seed-dumps.last); [ $((now - d)) -lt 93600 ] || { echo \"dumps older than 26 h: refusing (fail closed)\"; exit 1; }; for p in /mnt/data/documents /mnt/data/finance /mnt/data/photos /mnt/data/system/identity /boot/config /mnt/data/appdata/vaultwarden/dumps /mnt/data/appdata/forgejo/dumps /mnt/data/appdata/postgres/dumps; do [ -n \"$(ls -A $p 2>/dev/null)\" ] || { echo \"$p empty or not mounted: refusing (fail closed)\"; exit 1; }; done" } },
      { conditions: [ "CONDITION_SNAPSHOT_SUCCESS" ], onError: "ON_ERROR_IGNORE",
        actionCommand: { command: "date +%s > /mnt/data/system/seed-state/backrest-site-data.last" } }
    ]
  } ]
}
