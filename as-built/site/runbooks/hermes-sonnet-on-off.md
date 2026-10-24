# Hermes on Sonnet 5.5: turning it on and off

Hermes keeps its own loop, tools, approvals and compaction. The model is Sonnet 5.5, reached through the logged-in
Claude Code CLI by Nous Research's model-provider plugin **claude-subscription-directsdk** (experimental). Each model
call starts one `claude -p` with Claude Code's own tools off; a loopback relay admits exactly one upstream request.
Every turn draws on the subscription's Agent SDK allowance (Anthropic's help article, updated 20261007), at the
`claude -p` rate (the plugin's README). Set up 20261021 for the orchestrator's harness test. The other model path is
gpu-chat (site/runbooks/gpu-agent-on-off.md), which is off.

## The parts

| part | where | pinned |
|---|---|---|
| the plugin | `~tender/.hermes/plugins/claude-subscription-directsdk/` | NousResearch/hermes-official-plugins at `adfe0378fdaaee40da4892f9e41884680ef8c9cb` (the directory's tree `93d7d00a…`); version 0.3.3; manifest sha256 `1381cc5065b73fd16cd2142aa097be9edb47901025dbd695d42ad0a9b7733499` (the vendor's files, `find . -type f -print0 \| LC_ALL=C sort -z \| xargs -0 sha256sum \| sha256sum`; Python's caches and the pin file `.seed-pin` left out; the plan's `9e638a50…` is the same files sorted in en_US.UTF-8). Not `hermes plugins install`, which tracks main |
| its requirements | Hermes ≥ 0.21.4 (we run v0.21.5); Claude Code ≥ 2.1.284 for Sonnet 5.5 (we run 2.1.285, the same binary as Claude's) | none |
| the claude it runs | tender's wrapper `~/.local/share/seed/tender-bin/claude`, first on the units' PATH: it reads `/run/secrets/tender_claude_token` into `CLAUDE_CODE_OAUTH_TOKEN` in the CLI's process only, then execs the pinned CLI | none |
| its Claude config directory | `~tender/.local/state/mc` (0700): native's state (feature flags, `.claude.json`) goes there, not into Claude's `~/.claude` | none |
| Hermes's config | rendered by `tools/hermes-sonnet.sh on` from `nixos/modules/site-agents/hermes-config.yaml` | provider `claude-subscription-directsdk-experimental`, model `claude-sonnet-5-5` (sent as its 1M route), context 1000000, effort medium, telemetry on |
| the switches | `tools/hermes-sonnet.sh` install, on, status, back | none |

**Security notes:**
- The token is never in Hermes's environment, never on an argv, and never copied into a file. Hermes's tools run as
  tender, though, so they *can* read the tmpfs secret: this is the one-user design, accepted by the orchestrator for
  this test (post-test item 3).
- The plugin refuses to start if any of these is set in its environment: a nonempty `ANTHROPIC_API_KEY`,
  `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL` or `ANTHROPIC_FOUNDRY_API_KEY`, or an enabled
  `CLAUDE_CODE_USE_{BEDROCK,VERTEX,FOUNDRY}`. Keep Hermes's units free of them.

## Turning it on

1. **Pause Hermes first:** its paused marker in place, and tender-hermes-startup masked.
2. **Install the plugin:** `tools/hermes-sonnet.sh install`. It fetches the pinned commit, checks the tree and the
   manifest, copies the plugin to tender over stdin, checks it again there, and moves it into place. It refuses to
   overwrite a different copy.
3. **Render the config:** `tools/hermes-sonnet.sh on --no-restart`, then restart the gateway while Hermes is still
   paused. Check:
   - the gateway's log has no "Failed to load user provider plugin";
   - `tools/hermes-sonnet.sh status` shows the provider, `claude-sonnet-5-5`, 1000000 and medium, and the plugin
     installed at the pin.
4. **Prove one call:** one `hermes chat -Q -q` as tender with a neutral prompt. Check that nothing new appears in
   `~tender/.claude` or `~tender/.claude.json`.
5. **Hermes working** (only on the owner's or the orchestrator's decision): as in gpu-agent-on-off.md › Turning it on
   › 8:
   - the paused marker set aside;
   - site-watch resumed and checked again after the gateway settles;
   - the first periodic tick seen;
   - hc hermes-work resumed by the API. It has manual_resume=true, so a ping alone doesn't resume it.

**After any agent-box deploy:** a deploy re-runs tender-config, which reinstalls the repository's config. Run
`tools/hermes-sonnet.sh on --no-restart` again, then restart the gateway while Hermes is paused.

## Turning it off

1. Pause Hermes: site-watch paused, any running site-watch run allowed to end, the paused marker back, and hc
   hermes-work paused.
2. `tools/hermes-sonnet.sh back` renders the gpu-chat config again (the state before 20261021).
3. **Keep** the plugin and `~/.local/state/mc`. Nothing is deleted without the owner's word.

## The token (shared with Claude)

- **Made:** 20260929, by the owner with `claude setup-token`. Stored in the site vault as **"claude code tender token"**
  at 20260930 04:03Z and never revised (read from the vault item's dates, not its value).
- **Expected expiry:** about **20270929**. Setup tokens last about a year.
- **One token for both:** Claude's arm and this path use the same token, so a lapsed token stops both.
  `claude auth status` (through the wrapper) then no longer reports the token, and the plugin fails with
  ClaudeCodeLoggedOut.
- **Renewal**, before the expiry:
  1. The owner runs `claude setup-token` again and replaces the vault item's password field. Same item, same name.
  2. `tools/tender-bundle-make.sh` rebuilds the sops bundle.
  3. Commit and promote. The agent box's deploy puts the new token in `/run/secrets/tender_claude_token`. That deploy
     touches tender's units: re-render as above.
  4. One `claude -p` through the wrapper proves it, then one Hermes call.
