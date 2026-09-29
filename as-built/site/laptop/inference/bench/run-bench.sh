#!/bin/bash
# run-bench.sh <outdir> [labels...]: phases A-D of runbooks/rung4-benchmark.md on compute, as seed.
# Holds the production server (supervisor `held`) so only one model is in memory, runs each
# configuration on 127.0.0.1 with the same settings (16k context, one slot, prompt cache off),
# samples memory throughout, and lets the production server resume at the end.
#   L3 llama.cpp UD-Q3_K_XL   L8 llama.cpp Q8_0   M8 MLX 8-bit (mlx-community)
# SPEED_ONLY=1 runs phase B's speed part only (and the memory sampler). Prompt caches are off in both
# runtimes (llama-server: cache_prompt false per request; mlx_lm.server: --prompt-cache-size 0).
set -uo pipefail
B=$(cd "$(dirname "$0")" && pwd); . "$B/../pins"
I=$HOME/.local/share/seed/inference; S=$HOME/.local/state/seed/inference
LB=$I/llama.cpp/$RUNTIME_TAG/llama-$RUNTIME_TAG; PY=$I/mlx-venv/bin/python
out=$1; shift; labels=${*:-L3 L8 M8}; mkdir -p "$out"
log() { echo "$(date -u +%FT%TZ) $*" | tee -a "$out/run.log"; }
gg() { case $1 in L3) echo GLM-4.7-Flash-UD-Q3_K_XL.gguf;; L8) echo GLM-4.7-Flash-Q8_0.gguf;; esac; }   # /bin/bash 3.2: no arrays by name
touch "$S/held"; until ! pgrep -u "$(id -u)" -x llama-server >/dev/null; do sleep 2; done
log "production server held; environment: $(sw_vers -productVersion), $(pmset -g ps | head -1 | tr -d "'"), therm: $(pmset -g therm | grep -c 'No thermal'), uptime: $(uptime | cut -d, -f1)"
for p in short medium long; do
  n=$(jq -r --arg p $p 'select(.id==$p).prompt' "$B/prompts.jsonl" | "$LB/llama-tokenize" -m "$I/models/$(gg L3)" --stdin --ids --log-disable 2>/dev/null | tr -cd ',' | wc -c)
  log "prompt $p: $((n + 1)) tokens (llama-tokenize, before the chat template)"
done
for L in $labels; do
  "$B/sample.sh" "$out/$L-memory.csv" "llama-server|llama-bench|mlx_lm" & smp=$!
  if [ "$L" != M8 ]; then
    M=$I/models/$(gg $L)
    [ -n "${SPEED_ONLY:-}" ] || { log "$L phase A: llama-bench"; "$LB/llama-bench" -m "$M" -p 512,4096 -n 128 -r 5 -o json > "$out/$L-llama-bench.json" 2>> "$out/run.log"; }
    t0=$(date +%s); "$LB/llama-server" --model "$M" --alias bench --ctx-size 16384 --parallel 1 --cache-ram 0 --fit off \
      --host 127.0.0.1 --port 8091 --no-webui --jinja >> "$out/$L-server.log" 2>&1 & srv=$!
    until curl -sf -m 2 http://127.0.0.1:8091/health >/dev/null; do sleep 1; done; base=http://127.0.0.1:8091; mname=bench
  else
    t0=$(date +%s); "$PY" -m mlx_lm.server --model "$I/models/mlx-GLM-4.7-Flash-8bit" --host 127.0.0.1 --port 8092 --prompt-cache-size 0 >> "$out/$L-server.log" 2>&1 & srv=$!
    until curl -sf -m 2 http://127.0.0.1:8092/v1/models >/dev/null; do sleep 1; done; base=http://127.0.0.1:8092; mname=default_model   # mlx_lm.server: its --model
    "$PY" "$B/bench.py" speed "$L-warmup" $base $mname /dev/null --runs 1 >/dev/null   # mlx loads lazily on the first request
  fi
  log "$L ready in $(( $(date +%s) - t0 )) s"
  log "$L phase B: speed"; "$PY" "$B/bench.py" speed "$L" $base $mname "$out/speed.jsonl" --runs 5 > /dev/null
  [ -n "${SPEED_ONLY:-}" ] || { log "$L phase B: tasks"; "$PY" "$B/bench.py" tasks "$L" $base $mname "$out/tasks.jsonl" | tail -1 | tee -a "$out/run.log"; }
  kill $srv; wait $srv 2>/dev/null; sleep 10; kill $smp
  log "$L done; peak resident $(awk -F, 'NR>1 && $2>m {m=$2} END {print m}' "$out/$L-memory.csv") MiB, min free $(awk -F, 'NR>1 && (m=="" || $3<m) {m=$3} END {print m}' "$out/$L-memory.csv")%, max level $(awk -F, 'NR>1 && $4>m {m=$4} END {print m}' "$out/$L-memory.csv"), swapouts $(awk -F, 'NR==2 {a=$5} END {print $5-a}' "$out/$L-memory.csv")"
done
rm -f "$S/held"; log "production server released"
