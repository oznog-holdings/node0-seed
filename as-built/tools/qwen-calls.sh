#!/usr/bin/env bash
# Append the inference server's per-call timings to /work/agent/qwen-calls.tsv (site/laptop/inference/qwen-calls.py
# does the reading, on compute). Run by the keel-qwen-calls timer; safe to run by hand. The offset is kept beside it.
set -euo pipefail
out=/work/agent/qwen-calls.tsv; offf=/work/agent/.qwen-calls.offset
[ -s "$out" ] || printf 'utc\tmodel\tport\ttask\tslot\tprompt_new\tprompt_s\tcached\tgen\tgen_s\tctx_end\n' > "$out"
off=$(cat "$offf" 2>/dev/null || echo 0)
res=$(ssh -o BatchMode=yes -o LogLevel=ERROR -o ConnectTimeout=20 seed@192.168.1.20 "python3 - $off" < "$(dirname "$0")/../site/laptop/inference/qwen-calls.py")
# a failed append stops here, before the offset moves (Codex's review)
printf '%s\n' "$res" | awk '!/^#offset / && NF' >> "$out"
new=$(sed -n 's/^#offset //p' <<<"$res"); [ -n "$new" ] && echo "$new" > "$offf"
