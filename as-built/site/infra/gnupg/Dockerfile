# gpg for the recovery pack (symmetric AES256 with a passphrase a person can type). Pinned like chrony.
FROM alpine:3.24@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6
RUN apk add --no-cache gnupg
ENTRYPOINT ["gpg"]
