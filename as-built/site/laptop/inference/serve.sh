#!/bin/bash
# The inference backend: llama-server in router mode (rung4b.md). The router loads the models in
# presets.ini on demand (glm-4.7-flash at start), each as a child llama-server that exits with the
# router, and unloads the least recently used one when --models-max are loaded. It listens on the LAN
# address only and answers only callers with the key the gateway holds (vault "compute llama api key",
# in ~/.config/seed/llama.key, 0600). Run by supervise.sh, which adds up the whole tree against the
# ceiling; not by hand.
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd); . "$D/pins"
I=$HOME/.local/share/seed/inference
exec "$I/llama.cpp/$RUNTIME_TAG/llama-$RUNTIME_TAG/llama-server" \
  --models-preset "$D/presets.ini" --models-max "$MODELS_MAX" \
  --host "$LISTEN" --port "$PORT" --api-key-file "$HOME/.config/seed/llama.key" \
  --no-webui --metrics
