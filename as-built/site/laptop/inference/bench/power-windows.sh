#!/bin/bash
# power-windows.sh: the windows for the power figures (R4.09 and the bench at rest; 20260928, after rung 4b),
# run as seed on compute while the orchestrator reads the plug meters. Each window prints its start and
# end (UTC); the plugs' mean over each window is the reading. The Mac also reports its own DC input
# (ioreg AppleSmartBattery SystemPowerIn, battery full and not charging), sampled every 5 s here, so
# compute is measured without a plug. Windows, back to back:
#   R  rest: the production state, all four models loaded and idle (every box at rest) ... 10 min
#   H  the Mac with the backend held (no model loaded) ..................................... 10 min
#   C  chat: both GLM slots generating without pause ....................................... 10 min
#   M  the rung-4b mix: two chats, embeddings, reranking and speech-to-text at once ......... 10 min
# Settling time of 90 s before each window (30 s left the warm-up's tail in window R: the Mac's telemetry lags, 20260928). Test data public or synthetic (bench/4b; audio from `say`).
set -uo pipefail
B=$(cd "$(dirname "$0")" && pwd); . "$B/../pins"
S=$HOME/.local/state/seed/inference; M=${WINDOW_S:-600}; T=$(mktemp -d /tmp/pw.XXXXXX)
U="http://$LISTEN:$PORT"; K=$(cat "$HOME/.config/seed/llama.key")
post() { curl -s -m 600 -o /dev/null -H "Authorization: Bearer $K" -H 'Content-Type: application/json' --data-binary @"$1" "$U$2"; }
# the Mac's own draw, every 5 s: epoch and milliwatts
( while :; do echo "$(date +%s) $(ioreg -rn AppleSmartBattery | grep -o '"SystemPowerIn"=[0-9]*' | head -1 | cut -d= -f2)"; sleep 5; done ) > "$T/mac.txt" & SAMPLER=$!
trap 'kill $SAMPLER 2>/dev/null; rm -f "$S/held"; rm -rf "$T"' EXIT
# request bodies from the public set
jq -c '{model: "qwen3-embedding-4b", input: [.[0:16][].text]}' "$B/4b/docs.json" > "$T/embed.json"
jq -c --slurpfile q "$B/4b/queries.json" '{model: "qwen3-reranker-0.6b", query: $q[0][0].q, documents: [.[0:50][].text]}' "$B/4b/docs.json" > "$T/rerank.json"
jq -nc '{model: "glm-4.7-flash", messages: [{role: "user", content: "Write a long, detailed history of the bicycle."}], max_tokens: 2048, temperature: 0.7}' > "$T/chat.json"
head -1 "$B/4b/audio-texts.txt" | cut -d' ' -f2- > "$T/a.txt"; say -v Samantha -o "$T/a.aiff" -f "$T/a.txt"; afconvert -f WAVE -d LEI16@16000 -c 1 "$T/a.aiff" "$T/a.wav"
w() { eval "START_$1=$(date +%s)"; echo "window $1 start $(date -u +%T)"; }   # bash 3.2 (macOS): no arrays of names
e() { eval "END_$1=$(date +%s)"; echo "window $1 end   $(date -u +%T)"; }
until_end() { local end=$(( $(date +%s) + M )); while [ "$(date +%s)" -lt "$end" ]; do "$@"; done; }
chat() { post "$T/chat.json" /v1/chat/completions; }
embed() { post "$T/embed.json" /v1/embeddings; }
rerank() { post "$T/rerank.json" /v1/rerank; }
stt() { curl -s -m 600 -o /dev/null -H "Authorization: Bearer $K" -F model=qwen3-asr-1.7b -F response_format=json -F file=@"$T/a.wav" "$U/v1/audio/transcriptions"; }
W=${WINDOWS:-RHCM}   # WINDOWS=M runs only the mix (20260928)
has() { case $W in *$1*) return 0;; esac; return 1; }
# R: all four loaded, then idle
if has R; then chat; embed; rerank; stt; sleep 90
w R; sleep "$M"; e R; fi
# H: the backend held
if has H; then touch "$S/held"; until ! pgrep -u "$(id -u)" -f llama-server >/dev/null; do sleep 2; done; sleep 30
w H; sleep "$M"; e H
rm -f "$S/held"; until curl -sf -m 2 "$U/health" >/dev/null && chat; do sleep 3; done; sleep 90; fi
# C: both chat slots busy
has C && { w C; until_end chat & p1=$!; until_end chat & p2=$!; wait $p1 $p2; e C; }   # the loops only: a bare wait also waits for the sampler, forever (20260928)
# M: the mix
if has M; then chat; embed; rerank; stt; sleep 90
w M; P=; for f in chat chat embed rerank stt; do until_end $f & P="$P $!"; done; wait $P; e M; fi
# the Mac's own mean per window (DC input, W)
for k in R H C M; do has $k || continue
  eval "a=\$START_$k b=\$END_$k"; awk -v a="$a" -v b="$b" -v k="$k" '$1>=a && $1<=b && $2>0 {s+=$2; n++} END {printf "window %s: the Mac (ioreg SystemPowerIn) mean %.1f W over %d samples\n", k, s/n/1000, n}' "$T/mac.txt"
done
