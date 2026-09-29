# Moving the builder from agentvm onto the agent box (PLAN, for when the logins are done)

**Status 20260924 08:25 MDT: step 7 done.** The builder works on the agent box; step-5 checks green there and a commit from it pushed to the forge (diary `20260924.md`). Step 8: the orchestrator says it was done earlier today. Step 9 waits one working day.

**Status 20260924 ~08:00 MDT: steps 1 to 6 done, READY for step 7.** Key SHA256:KEY-FINGERPRINT-PLACEHOLDER
(`seed-builder@agent seed`) on infra's root (UI form), the router (rpcd, D.06 hash
unchanged), the forge account, and `admin@core` (core arrived after this plan). Not added to
`keys.nix`: I work on the agent box itself, so no key into it is needed. seed-lab cloned from
the forge, equal to agentvm's tree (91df38b, the same hash over every tracked file); pages at
the pin, hashes equal; node0-seed (empty, no commits) re-made empty. Hosted vault by API key
and a fresh Vaultwarden profile work there. UI helpers copied without the browser profile.
Checks on the agent box as `agent`: check-after-reboot 16/16, check-dns both servers,
netbox-sync --check 0, vault compare (see the diary). Logins done by the person;
`claude mcp list` no servers, Codex `apps = false`.

index › Rung 2: the agent gets its own box; design › Development: "at the rung 2 move, retire
the old volume only once the new one is verified". The builder today works as `agent` on
agentvm (`/work/agent`), and as `agent` (unprivileged, named sudo) on the agent box.

## Before the move (the builder, from agentvm; nothing here stops agentvm)

1. **A key for the builder on the agent box** (one key per agent: design › Secrets): made there
   as `agent` (`~/.ssh/id_ed25519`, comment `seed-builder@agent seed`). From agentvm, where
   access exists, add its public key to: infra's root (Users › root › SSH authorized keys,
   the UI form as on 20260923), the router (rpcd `file.write`, D.06 hash before and after),
   the forge's `seed-builder` account (API), and the flake's `keys.nix` for the `agent`
   account on the agent box itself (a commit and a promotion). Old agentvm key stays until
   agentvm is retired.
2. **The record and the config repo** are cloned on the agent box **from the forge** (the
   repo of record), not copied: `git clone ssh://git@git.seed.example.com:2222/seed/seed-lab.git
   /work/agent/seed-lab`; then `git log -1` equal to agentvm's and to the forge's `main`, and a
   file-by-file hash of the tree against agentvm's (as on 20260923). `node0-seed` (still empty)
   the same way once it has a remote, else copied with its `.git` and checked by `git fsck`.
   `/work/agent/pages` re-cloned at the pin 4f6fc81 and its two pages' hashes compared with
   `evidence/20260923-pages-pin.txt`.
3. **Credentials, host to host, never printed:** `~/.config/seed/bw.env` streamed over ssh into
   a 0700 directory, 0600, the sha256 compared on both sides; `bw login --apikey` and
   `bw unlock` tested there, routine items listed by name. The Vaultwarden profile
   (`~/.config/seed/bw-local`) is made fresh there (`bw config server`, `bw login` with the
   builder's master password from the hosted vault), not copied.
4. **Tools:** the agent tools are declared already (`modules/agent-tools.nix`); the UI helpers
   (puppeteer, Chromium from nixpkgs) recreated in `~/.local/share/seed/ui` from the repo's
   notes (they hold no secrets; the Unraid session cookie is made fresh by
   `tools/unraid-login.sh`).
5. **Check list on the agent box as `agent`:** ssh to infra, the router and the forge with the
   new key; `site/bin/check-after-reboot`; `site/bin/check-dns`; `tools/vault-compare-routine.sh`
   (35 MATCH); `bin/netbox-sync --check`. All green before the restart.

## The move itself (the orchestrator)

6. **The person logs in** Claude Code and Codex as `agent` on the agent box (Needs hands);
   `ENABLE_CLAUDEAI_MCP_SERVERS=false` and Codex `apps = false` are already declared and
   re-checked after the login (`claude mcp list`, `codex features list`).
7. The orchestrator restarts the builder there (a new session on the agent box, working
   directory `/work/agent`). The builder's first acts there: the checks of step 5, a diary
   entry, and a commit **from the agent box** pushed to the forge (the proof the move worked).

## After (the orchestrator, then the builder)

8. The orchestrator runs the agentvm memory steps (`site/runbooks/d05-vm-memory-steps.md`).
9. agentvm's `/work/agent` stays until the new one is verified (step 5 and one working
   day); then it is retired as its own step (principle 10: copy, verify, delete), and the
   builder's agentvm key leaves infra, the router and the forge in the same step.
