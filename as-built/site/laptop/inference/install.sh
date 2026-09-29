#!/bin/bash
# Install the pinned runtime and model into seed's home (no admin), verified by sha256. Idempotent.
# The directory carries CACHEDIR.TAG, so seed's backup (--exclude-caches) skips it: it is rebuilt
# from the pins, not restored.
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd); . "$D/pins"
I=$HOME/.local/share/seed/inference; mkdir -p "$I/models" "$I/llama.cpp"
[ -f "$I/CACHEDIR.TAG" ] || printf 'Signature: 8a477f597d28d172789f06886806bc55\n# rebuilt from the pins in seed-lab (site/laptop/inference), not backed up\n' > "$I/CACHEDIR.TAG"
if [ ! -x "$I/llama.cpp/$RUNTIME_TAG/llama-$RUNTIME_TAG/llama-server" ]; then
  cd "$I/llama.cpp"; curl -sfL -o "$RUNTIME_ASSET" "https://github.com/ggml-org/llama.cpp/releases/download/$RUNTIME_TAG/$RUNTIME_ASSET"
  echo "$RUNTIME_SHA256  $RUNTIME_ASSET" | shasum -a 256 -c; mkdir -p "$RUNTIME_TAG"; tar -xzf "$RUNTIME_ASSET" -C "$RUNTIME_TAG"; rm "$RUNTIME_ASSET"
fi
M="$I/models/$MODEL_FILE"
if [ ! -f "$M" ]; then
  curl -sfL -C - -o "$M.part" "https://huggingface.co/$MODEL_REPO/resolve/$MODEL_REV/$MODEL_FILE"
  echo "$MODEL_SHA256  $M.part" | shasum -a 256 -c; mv "$M.part" "$M"
fi
while read -r repo rev file sha; do
  [ -n "$repo" ] || continue; M="$I/models/$file"
  if [ ! -f "$M" ]; then
    curl -sfL -C - -o "$M.part" "https://huggingface.co/$repo/resolve/$rev/$file"
    echo "$sha  $M.part" | shasum -a 256 -c; mv "$M.part" "$M"
  fi
done <<<"$MODELS_4B"
echo "installed: llama.cpp $RUNTIME_TAG, $MODEL_FILE, $(grep -c . <<<"$MODELS_4B") rung-4b files"
