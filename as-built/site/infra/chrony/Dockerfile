# chrony for infra (design › Time: "Run chrony on the infra box"; index › Rung 1: as containers).
# No maintained image takes a repo-owned chrony.conf and disciplines the host clock
# (cturra/ntp generates its own config, runs `-x` and publishes only `latest`), so: Alpine's
# chrony, pinned by digest and version. The config is mounted read-only from appdata.
FROM alpine:3.24@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6
RUN apk add --no-cache 'chrony~4.8'
ENTRYPOINT ["/bin/sh", "-c", "chown chrony:chrony /var/lib/chrony && exec /usr/sbin/chronyd -d -u chrony -f /etc/chrony/chrony.conf"]
