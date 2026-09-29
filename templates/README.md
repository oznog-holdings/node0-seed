# Templates

Configuration files as templates, filled from one values file.

1. Copy `values.example.yaml` to `values.yaml` and change it.
2. Run `python3 templates/render.py` (needs PyYAML). Every `*.tmpl` becomes a file under
   `out/` with your values in place. A placeholder with no value stops the render.
3. Review what was rendered, then deploy it the way the rung's runbook says.

Placeholders look like `${site.domain}`: a dotted path into the values file. Caddy's own
environment references, `{$NAME}`, are left alone: those are secrets it reads at run time
from an env file, never from the repository.

| Template | Rung | What it is |
|---|---|---|
| `dns/rewrites.yaml.tmpl` | 1, 3 | the site's names, rendered into AdGuard Home on infra and core |
| `caddy/Caddyfile.tmpl` | 1 | the HTTPS front door with one wildcard certificate |
| `chrony/infra.conf.tmpl` | 1, 3 | infra's time server: the pool, its own clock as fallback |
| `monitoring/rules/floor.yml` with `floor.test.yaml` | 1 | the monitoring floor's 20 alert rules and their unit tests (`promtool test rules floor.test.yaml`) |
| `monitoring/seed-metrics.sh` | 1 | the one producer of the site's own metrics (backups, restores, scrubs, SMART by serial, UPS, jobs), run every 5 minutes into node_exporter's textfile directory. The UPS state needs a faster reader than this: read it every 10 to 15 seconds (rung 1, and the bench's `seed-ups-metrics` in `as-built/`) |
| `chrony/core.conf.tmpl` | 3 | core's time server: the pool preferred, infra second, the local clock only after a first sync |

_More to come from the build: the backup scripts, the gateway, the post-reboot check, the agent box's flake._
