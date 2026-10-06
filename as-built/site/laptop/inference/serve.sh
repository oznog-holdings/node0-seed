#!/bin/bash
# The inference backend: llama-server in router mode (rung4b.md). The router loads the models in
# presets.ini on demand (local-chat and the embedder at start), each as a child llama-server that exits with the
# router, and unloads the least recently used one when --models-max are loaded. It listens on the LAN
# address only and answers only callers with the key the gateway holds (vault "compute llama api key",
# in ~/.config/seed/llama.key, 0600). Run by supervise.sh, which adds up the whole tree against the
# ceiling; not by hand.
set -uo pipefail
D=$(cd "$(dirname "$0")" && pwd); . "$D/pins"
I=$HOME/.local/share/seed/inference
# the runtime: the pinned llama.cpp release, unless the preset file names another build under $I (a line
# "; runtime = <path>": Bonsai needs PrismML's fork, 20261001), so a model switch stays the one link
R=$(sed -n 's/^; runtime = //p' "$D/presets.ini" | head -1)
# two servers, both children of this script, so the supervisor counts them as one tree and stops them together
# (the utility tier, 20261002): the router, and the encoder service (encoders.py: the models llama.cpp can't serve)
"$I/${R:-llama.cpp/$RUNTIME_TAG/llama-$RUNTIME_TAG/llama-server}" \
  --models-preset "$D/presets.ini" --models-max "$MODELS_MAX" \
  --host "$LISTEN" --port "$PORT" --api-key-file "$HOME/.config/seed/llama.key" \
  --no-webui --metrics &
router=$!; enc=
U=$HOME/.local/share/seed/utility
if [ -n "${ENCODERS_PORT:-}" ] && [ -x "$U/venv/bin/python" ]; then
  "$U/venv/bin/python" "$D/encoders.py" "$LISTEN" "$ENCODERS_PORT" >> "$HOME/.local/state/seed/inference/encoders.log" 2>&1 &
  enc=$!
fi
trap 'kill -TERM $router $enc 2>/dev/null; wait' TERM INT
# either one ending ends both: the supervisor sees the server gone and starts it again (bash 3.2: no wait -n)
while kill -0 $router 2>/dev/null && { [ -z "$enc" ] || kill -0 $enc 2>/dev/null; }; do sleep 5 & wait $!; done
kill -TERM $router $enc 2>/dev/null; wait; exit 1
