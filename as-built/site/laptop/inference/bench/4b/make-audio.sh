#!/bin/bash
# Synthetic speech for the rung-4b speech-to-text runs: macOS `say` reads public paragraphs of the node0
# pages (audio-texts.txt: "<doc id> <text>" per line) in six voices; afconvert makes 16 kHz mono WAV.
# Run on compute as seed: bash make-audio.sh <out dir> < audio-texts.txt. Prints name, voice, seconds.
set -euo pipefail
out=$1; mkdir -p "$out"; voices=(Samantha Daniel Karen Moira Rishi Fred); n=0
while read -r id text; do
  v=${voices[$((n % ${#voices[@]}))]}; f=$out/doc$id
  printf '%s\n' "$text" > "$f.txt"; say -v "$v" -o "$f.aiff" -f "$f.txt"
  afconvert -f WAVE -d LEI16@16000 -c 1 "$f.aiff" "$f.wav"; rm "$f.aiff"
  echo "doc$id $v $(afinfo "$f.wav" | awk '/estimated duration/ {print $3}')"; n=$((n+1))
done
