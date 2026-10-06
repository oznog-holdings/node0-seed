#!/bin/bash
# Qwen3.8-27B for compute (the owner's decision, 20260929): Qwen publishes no official GGUF for it, so the GGUF is
# built from the official release (Hugging Face Qwen/Qwen3.8-27B at the pinned revision, every shard checked
# against the release's sha256) with the pinned llama.cpp's own converter and quantizer. The result's sha256 is
# pinned in `pins` (QWEN38_*), so install.sh can check it; this script is how to make it again.
#   build-qwen38.sh fetch    <dir>   (a Linux box with nix; the agent box) the release at QWEN38_REV into <dir>, checked
#   build-qwen38.sh convert  <dir>   (the same box) the text model to a BF16 GGUF with llama.cpp QWEN38_CONVERTER's
#                                    convert_hf_to_gguf.py (source tarball checked; torch as its requirements pin)
#   build-qwen38.sh quantize <bf16.gguf>  (compute, as seed) BF16 -> QWEN38_QUANT with the installed llama-quantize
#                                    (the same llama.cpp tag), into the models directory; checked against the pin
# Put <dir> under a directory named .cache on the agent box: flow 2's backup skips it (55.6 GB + 53.8 GB).
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd); . "$D/pins"
case ${1:-} in
fetch)
  B=${2:?dir}; mkdir -p "$B/src"; cd "$B/src"
  curl -sf "https://huggingface.co/api/models/$QWEN38_REPO/tree/$QWEN38_REV" | jq -r '.[] | "\(.path)\t\(.size)\t\(.lfs.oid // "-")"' > ../files.tsv
  cut -f1 ../files.tsv | xargs -P 3 -I{} curl -sfL -C - --retry 5 -o {} "https://huggingface.co/$QWEN38_REPO/resolve/$QWEN38_REV/{}"
  awk -F'\t' '$3 != "-" {print $3 "  " $1}' ../files.tsv | sha256sum -c --quiet
  echo "the release's LFS files match its sha256 ($(awk -F'\t' '$3 != "-"' ../files.tsv | wc -l) files)" ;;
convert)
  B=${2:?dir}; cd "$B"
  curl -sfL --retry 5 -o llama.cpp-src.tar.gz "https://codeload.github.com/ggml-org/llama.cpp/tar.gz/refs/tags/$QWEN38_CONVERTER"
  gzip -t llama.cpp-src.tar.gz; rm -rf "llama.cpp-$QWEN38_CONVERTER"; tar xzf llama.cpp-src.tar.gz
  nix-shell -p 'python3.withPackages(p: with p; [ numpy torch safetensors sentencepiece transformers protobuf ])' --run \
    "PYTHONPATH=llama.cpp-$QWEN38_CONVERTER/gguf-py python3 llama.cpp-$QWEN38_CONVERTER/convert_hf_to_gguf.py src --outtype bf16 --outfile $QWEN38_BF16_FILE"
  echo "$(sha256sum "$QWEN38_BF16_FILE")  (pin: $QWEN38_BF16_SHA256)" ;;
quantize)
  F=${2:?bf16.gguf}; I=$HOME/.local/share/seed/inference; out="$I/models/$QWEN38_FILE"
  "$I/llama.cpp/$RUNTIME_TAG/llama-$RUNTIME_TAG/llama-quantize" "$F" "$out.part" "$QWEN38_QUANT"
  h=$(shasum -a 256 "$out.part" | cut -d' ' -f1)
  [ "$h" = "$QWEN38_SHA256" ] && mv "$out.part" "$out" && echo "installed $out ($h)" || { echo "sha256 $h, pin $QWEN38_SHA256: kept as $out.part"; exit 1; } ;;
*) echo "usage: build-qwen38.sh fetch|convert <dir> | quantize <bf16.gguf>"; exit 2 ;;
esac
