#!/usr/bin/env python3
"""Write prompts.jsonl: three prompt sizes over a synthetic device inventory (seeded, so every run
and every runtime gets the same bytes; no real addresses, serials or names)."""
import json, random
r = random.Random(20260927)
st = ['ok'] * 9 + ['degraded']
def rows(n):
    return '\n'.join(f'Device D-{i:04d}: rack {r.randint(1, 9)}, port {r.randint(1, 48)}, firmware '
                     f'{r.randint(1, 4)}.{r.randint(0, 9)}.{r.randint(0, 9)}, status {r.choice(st)}' for i in range(1, n + 1))
q = '\n\nList the device ids whose status is degraded, then say how many there are.'
out = [
    {'id': 'short', 'prompt': 'Explain in three sentences what a UPS does for a small server rack.'},
    {'id': 'medium', 'prompt': 'Here is an inventory.\n' + rows(80) + q},
    {'id': 'long', 'prompt': 'Here is an inventory.\n' + rows(480) + q},
]
with open('prompts.jsonl', 'w') as f:
    for o in out: f.write(json.dumps(o) + '\n')
