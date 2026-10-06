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
# glm-4.7-flash (MODEL_*) is retired (20260929): not fetched any more; its pins stay as the rung 4b record.
# Qwen3.8-27B: no official GGUF exists, so it isn't downloaded but built (build-qwen38.sh); here it is only checked.
Q="$I/models/$QWEN38_FILE"; qwen=missing
if [ -f "$Q" ]; then echo "$QWEN38_SHA256  $Q" | shasum -a 256 -c >/dev/null && qwen=ok || { echo "$Q: sha256 differs from the pin"; exit 1; }
else echo "$QWEN38_FILE is missing: build it with build-qwen38.sh (fetch and convert on a Linux box with nix, quantize here)"; fi
while read -r repo rev file sha; do
  [ -n "$repo" ] || continue; M="$I/models/$file"
  if [ ! -f "$M" ]; then
    curl -sfL -C - -o "$M.part" "https://huggingface.co/$repo/resolve/$rev/$file"
    echo "$sha  $M.part" | shasum -a 256 -c; mv "$M.part" "$M"
  fi
done <<<"$MODELS_4B"
echo "installed: llama.cpp $RUNTIME_TAG, $QWEN38_FILE ($qwen), $(grep -c . <<<"$MODELS_4B") rung-4b files"
[ $qwen = ok ]
