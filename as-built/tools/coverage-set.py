#!/usr/bin/env python3
"""Set the status and evidence columns of one coverage.md row, found by its ID.
Usage: coverage-set.py R1.08 done 'evidence text'"""
import re, sys
rid, status, evidence = sys.argv[1], sys.argv[2], sys.argv[3]
path = 'coverage.md'; lines = open(path).read().split('\n'); hits = 0
for i, l in enumerate(lines):
    if not l.startswith('|'): continue
    cells = l.split(' | ')
    if len(cells) >= 6 and re.match(rf'^{re.escape(rid)}\b', cells[1]):
        cells[-2] = status; cells[-1] = evidence.replace('|', '/') + ' |'
        lines[i] = ' | '.join(cells); hits += 1
if hits != 1: sys.exit(f'{rid}: {hits} rows matched')
open(path, 'w').write('\n'.join(lines)); print(f'{rid} -> {status}')
