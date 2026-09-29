# sqlite3 for integrity checks and row counts of application dumps (R1.60, R1.61). Pinned like chrony.
FROM alpine:3.24@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6
RUN apk add --no-cache sqlite
ENTRYPOINT ["sqlite3"]
