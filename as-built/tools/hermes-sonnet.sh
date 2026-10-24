#!/usr/bin/env bash
# hermes-sonnet.sh: Hermes on Sonnet 5.5 through the claude CLI (the harness test, the orchestrator 20261021; the plan
# tender-test-private/harness-plan-20261021.md › A1-A3; site/runbooks/hermes-sonnet-on-off.md). From the builder's
# account on the agent box; nothing here runs by itself, and each subcommand says what it found.
#   install       Nous Research's model-provider plugin claude-subscription-directsdk, at the pinned commit, checked by
#                 its manifest's sha256 and its git tree, into ~tender/.hermes/plugins/claude-subscription-directsdk/
#                 (refuses a different copy already there)
#   on [--no-restart]   Hermes's config rendered from nixos/modules/site-agents/hermes-config.yaml into
#                 ~tender/.hermes/config.yaml: the plugin's provider, model claude-sonnet-5-5 (the plugin sends its 1M
#                 route), context 1000000, reasoning effort medium (Claude Code's default for Sonnet 5.5), the plugin's
#                 own Claude config directory (~tender/.local/state/mc, 0700), telemetry on (as Claude's CLI). The
#                 seed-gateway provider block stays. Hermes's gateway restarted to load it unless --no-restart
#                 The CLI runs through ~tender/.local/share/seed/claude-model (Hermes's .env names it as the plugin's
#                 command): its own HOME and TMPDIR inside mc (the orchestrator's ruling, 20261021: the CLI reads
#                 ~/.claude/state/ and writes ~/.cache, ~/.local/state from HOME, whatever CLAUDE_CONFIG_DIR says), then
#                 tender's wrapper, which reads the token. Only the CLI's process gets that HOME: never Hermes or its tools
#   status        named keys only: the provider, model, context, effort, the plugin's settings and install, the paused marker
#   back [--no-restart]   the gpu-chat config again (tools/gpu-day.sh hermes-gpu 131072): today's, before this test
# The claude CLI is tender's wrapper (first on its units' PATH): the token from tmpfs into the CLI's process only, never
# into Hermes's environment or onto an argv. Any agent-box deploy re-runs tender-config, which reinstalls the repo's
# config: re-render after one (on --no-restart, then restart the gateway while paused).
set -euo pipefail
cd "$(dirname "$0")/.."
T="ssh -o BatchMode=yes tender@localhost"
REPO=https://github.com/NousResearch/hermes-official-plugins
COMMIT=adfe0378fdaaee40da4892f9e41884680ef8c9cb       # main, 20261021; the plugin's directory last changed in 9b074e1
TREE=93d7d00ab48177f255fc24d11807871751b9c842         # claude-subscription-directsdk/ at that commit
# the manifest's sha256 ($M below, in the C locale); the plan's 9e638a50… is the same files sorted in en_US.UTF-8
SHA=1381cc5065b73fd16cd2142aa097be9edb47901025dbd695d42ad0a9b7733499
DEST='~/.hermes/plugins/claude-subscription-directsdk'
MC=/home/tender/.local/state/mc
CM=/home/tender/.local/share/seed/claude-model     # the model client's claude: HOME and TMPDIR in mc, then the wrapper
log() { echo "$(date -u +%FT%TZ) $*"; }
# the vendor's files only: Python's caches (an import writes __pycache__) and our pin file are left out
# sorted in the C locale (the order, and so the hash, would otherwise follow the locale)
M="find . -type f ! -name .seed-pin ! -name '*.pyc' ! -path '*/__pycache__/*' ! -path './.pytest_cache/*' -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -c1-64"
manifest() { eval "$M"; }
installed() { $T "cd $DEST 2>/dev/null && $M" || true; }
restart() { $T "systemctl --user restart tender-hermes; systemctl --user is-active tender-hermes"; }
paused() { $T 'test -e ~/.config/site-agents/paused/hermes && echo kept || echo ABSENT'; }

case ${1:-} in
install)
  have=$(installed)
  if [ "$have" = "$SHA" ]; then log "the plugin is installed at the pin already ($SHA)"; exit 0; fi
  [ -z "$have" ] || { log "a different copy is installed (manifest $have): stopped (look first; nothing is overwritten)"; exit 1; }
  w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
  git -C "$w" init -q; git -C "$w" fetch -q --depth 1 "$REPO" "$COMMIT"
  [ "$(git -C "$w" rev-parse FETCH_HEAD)" = "$COMMIT" ] || { log "fetched commit isn't $COMMIT: stopped"; exit 1; }
  [ "$(git -C "$w" rev-parse "FETCH_HEAD:claude-subscription-directsdk")" = "$TREE" ] || { log "the directory's tree isn't $TREE: stopped"; exit 1; }
  mkdir "$w/p"; git -C "$w" archive FETCH_HEAD:claude-subscription-directsdk | tar -x -C "$w/p"
  [ "$(cd "$w/p" && manifest)" = "$SHA" ] || { log "the manifest's sha256 isn't the pin: stopped"; exit 1; }
  # to tender over ssh's stdin, unpacked beside the destination, checked there, then moved into place
  printf '%s %s\n' "$COMMIT" "$SHA" > "$w/p/.seed-pin"   # the provenance, for the archive's pins
  # a staging copy left by an earlier attempt is looked at, not removed
  $T "test ! -e $DEST.new" || { log "$DEST.new exists (an earlier attempt): look first; stopped"; exit 1; }
  tar -C "$w/p" -cf - . | $T "umask 077; set -e; mkdir -p ~/.hermes/plugins; mkdir $DEST.new; tar -x -C $DEST.new"
  got=$($T "cd $DEST.new && $M")
  [ "$got" = "$SHA" ] || { log "the copy at tender's isn't the pin ($got): left at $DEST.new, stopped"; exit 1; }
  $T "mv $DEST.new $DEST"
  log "installed: claude-subscription-directsdk $(git -C "$w" show FETCH_HEAD:claude-subscription-directsdk/plugin.yaml | sed -n 's/^version: *//p') at ${COMMIT:0:7}, manifest $SHA" ;;
on)
  [ "$(installed)" = "$SHA" ] || { log "the plugin isn't installed at the pin: install first"; exit 1; }
  f=$(mktemp); trap 'rm -f "$f"' EXIT
  python3 - nixos/modules/site-agents/hermes-config.yaml > "$f" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
P = 'claude-subscription-directsdk-experimental'
R = [('  provider: "seed-gateway"\n  default: "local-chat"\n  context_length: 131072          # the served context (evidence/20260930-qwen38): one slot, f16 KV, no YaRN',
      f'  provider: "{P}"\n  default: "claude-sonnet-5-5"     # the plugin sends its pinned 1M route, claude-sonnet-5-5[1m]\n  context_length: 1000000         # Sonnet 5.5\'s window, as Claude Code runs it'),
     ('    request_timeout_seconds: 3600\nagent:',
      f'    request_timeout_seconds: 3600\n  {P}:\n    request_timeout_seconds: 900  # read-idle\n    stale_timeout_seconds: 900    # the whole call (the plugin\'s README: otherwise off for process://)\nagent:'),
     ('  gateway_timeout: 3600           # a turn waiting on a cold prefill is not idle', '  gateway_timeout: 900'),
     ('  context_timeout_seconds: 2700\n  context_total_ceiling_seconds: 3000\n  hygiene_total_ceiling_seconds: 3000',
      '  context_timeout_seconds: 600\n  context_total_ceiling_seconds: 900\n  hygiene_total_ceiling_seconds: 900'),
     # Qwen's template switch is unknown to the plugin, which rejects unknown fields; reasoning off reaches it as effort low
     ('  compression: { provider: "main", timeout: 2700, extra_body: { chat_template_kwargs: { enable_thinking: false } } }',
      '  compression: { provider: "main", timeout: 600 }')]
for a, b in R:
    assert s.count(a) == 1, a[:50]
    s = s.replace(a, b)
s, n = re.subn(r'(?m)^  threshold_tokens: \d+\n', '', s); assert n == 1   # the ratio alone, at the 1M window
assert s.count('  reasoning_effort: "medium"') == 1
s += (f'plugins:\n  entries:\n    {P}:\n      settings:\n'
      '        claude_config_dir: "/home/tender/.local/state/mc"   # its own: native\'s state stays out of ~/.claude\n'
      '        claude_code_telemetry: true\n')
s = ('# Sonnet 5.5 through the claude CLI (20261021): rendered from hermes-config.yaml by tools/hermes-sonnet.sh; '
     'tools/gpu-day.sh hermes-gpu 131072 renders the gpu-chat one.\n') + s
print(s, end='')
PY
  $T "umask 077; mkdir -p $MC; chmod 700 $MC; cat > ~/.hermes/config.yaml.sonnet && mv ~/.hermes/config.yaml.sonnet ~/.hermes/config.yaml" < "$f"
  $T "umask 077; cat > $CM.new && chmod 700 $CM.new && mv $CM.new $CM" <<'SH'
#!/bin/sh
# the claude CLI for Hermes's model client (tools/hermes-sonnet.sh): its own HOME and temp directory, inside the
# client's config directory, so nothing it writes or reads by its home lands in tender's own; then tender's wrapper
M=/home/tender/.local/state/mc
mkdir -p -m 700 "$M/home" "$M/home/tmp" || exit 1
HOME=$M/home TMPDIR=$M/home/tmp; export HOME TMPDIR
unset XDG_CONFIG_HOME XDG_CACHE_HOME XDG_STATE_HOME XDG_DATA_HOME
# its working directory outside /home/tender: the CLI looks for .claude/ folders in every directory above it
# (the rehearsal, 20261021: from Hermes's temp directory it reached ~/.claude)
D=/tmp/claude-model-$(id -u)
mkdir -p -m 700 "$D"
{ [ -d "$D" ] && [ ! -L "$D" ] && [ -O "$D" ] && [ "$(stat -c %a "$D")" = 700 ]; } || { echo "claude-model: $D isn't a private directory of ours" >&2; exit 1; }
cd "$D" || exit 1
exec /home/tender/.local/share/seed/tender-bin/claude "$@"
SH
  # the plugin's command, by Hermes's .env (read by the gateway and the CLI alike); a path, not a secret
  $T "hermes config set CLAUDE_SUBSCRIPTION_DIRECTSDK_COMMAND $CM >/dev/null"
  [ "${2:-}" = --no-restart ] || restart
  "$0" status ;;
status)
  log "Hermes: $($T "grep -m1 '^  provider:' ~/.hermes/config.yaml; grep -m1 '^  default:' ~/.hermes/config.yaml; grep -m1 '^  context_length:' ~/.hermes/config.yaml; grep -m1 '^  reasoning_effort:' ~/.hermes/config.yaml" | tr -s ' ' | tr '\n' ' ')"
  log "the plugin's settings: $($T "grep -E '^        (claude_config_dir|claude_code_telemetry):' ~/.hermes/config.yaml" | sed 's/#.*//' | tr -s ' ' | tr '\n' ' ')"
  have=$(installed); log "the plugin installed: $([ -z "$have" ] && echo no || { [ "$have" = "$SHA" ] && echo "yes, at the pin" || echo "A DIFFERENT COPY ($have)"; })"
  log "its config directory: $($T "stat -c '%U %a' $MC 2>/dev/null || echo absent")"
  log "its command: $($T "sed -n 's/^CLAUDE_SUBSCRIPTION_DIRECTSDK_COMMAND=//p' ~/.hermes/.env" | tr '\n' ' ')(the model client's claude: $($T "sha256sum < $CM 2>/dev/null | cut -c1-12 || echo absent"))"
  log "paused marker: $(paused); tender-hermes: $($T 'systemctl --user is-active tender-hermes' || true)" ;;
back)
  tools/gpu-day.sh hermes-gpu 131072 --no-restart
  $T "hermes config unset CLAUDE_SUBSCRIPTION_DIRECTSDK_COMMAND >/dev/null"   # the wrapper file itself is kept
  [ "${2:-}" = --no-restart ] || restart
  "$0" status ;;
*) sed -n '2,20p' "$0"; exit 64 ;;
esac
