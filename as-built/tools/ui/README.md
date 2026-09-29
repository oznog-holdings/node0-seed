# UI helpers (headless Chromium on the Unraid and Vaultwarden web UIs)

The builder configures Unraid the Unraid way (annex): the web UI first. These scripts drive the
UI's own forms and buttons with puppeteer-core and nixpkgs' Chromium, reusing the session cookie
that `tools/unraid-login.sh` makes (`~/.local/state/seed/unraid/cookies`), so no password reaches
them; the Vaultwarden ones take the builder's master password from the environment only.

Committed 20260924 (F-REBUILD-STATE): until then they lived only in the builder's home.

    cd tools/ui && npm ci          # node_modules (not in git)
    ./run.sh create-container.js <name>

`profile/` (the browser profile) and `node_modules/` stay out of git. Most scripts were written
for one step of the build and are kept as the record of how that step was done (see the diary).
