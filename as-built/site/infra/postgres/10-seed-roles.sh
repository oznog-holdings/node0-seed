#!/bin/sh
# Runs once, when the postgres container initialises an empty data directory
# (/docker-entrypoint-initdb.d). One role and one database per application; passwords come
# from the container's env file (/mnt/data/system/secrets/postgres.env), never from the repo.
set -eu
for app in litellm netbox; do
  pw=$(eval "printf %s \"\${$(echo "$app" | tr a-z A-Z)_DB_PASSWORD}\"")
  [ -n "$pw" ] || { echo "no password for $app"; exit 1; }
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres \
    -v app="$app" -v pw="$pw" <<'SQL'
CREATE ROLE :"app" LOGIN PASSWORD :'pw';
CREATE DATABASE :"app" OWNER :"app";
REVOKE ALL ON DATABASE :"app" FROM PUBLIC;
SQL
done
