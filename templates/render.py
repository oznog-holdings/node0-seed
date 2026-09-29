#!/usr/bin/env python3
"""Render every *.tmpl under templates/ into out/, reading values.yaml (or values.example.yaml).

Placeholders are ${dotted.path} into the values file, e.g. ${site.domain} or ${hosts.infra}.
A placeholder with no value stops the render, so nothing half-filled is written.
Needs Python 3 and PyYAML (pip install pyyaml).
"""
import pathlib, re, sys
import yaml

root = pathlib.Path(__file__).resolve().parent.parent
values_file = root / "values.yaml"
if not values_file.exists():
    values_file = root / "values.example.yaml"
values = yaml.safe_load(values_file.read_text())

def lookup(path):
    node = values
    for part in path.split("."):
        if not isinstance(node, dict) or part not in node:
            sys.exit(f"no value for ${{{path}}} in {values_file.name}")
        node = node[part]
    return str(node)

out = root / "out"
for tmpl in sorted((root / "templates").rglob("*.tmpl")):
    text = re.sub(r"\$\{([a-z0-9_.]+)\}", lambda m: lookup(m.group(1)), tmpl.read_text())
    dest = out / tmpl.relative_to(root / "templates").with_suffix("")
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(text)
    print(f"rendered {dest.relative_to(root)} from {values_file.name}")
