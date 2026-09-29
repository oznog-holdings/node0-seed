# The router's configuration from the repository (rung 5, phase A)

The router (OpenWrt One, 192.168.1.1) is configured from `site/router/config/`: one file per UCI
package, as `uci export <package>` prints it, taken from the running router on 20260929
(`config-tool pull`) and from then on the source. Rows R5.01 and R5.03.

**What isn't in the repository:**
- **The lab's sections:** the internet side (`network` interfaces `wan` and `wan6`) and the two
  firewall rules named `fixture:*` (ANNEX › The bench). Each is a marker line,
  `# lab-owned (not in the repository): <config line>`. `apply` puts the router's own copy back
  in its place without reading it into the repository. It refuses to run if a marker has no
  section on the router, or the router has a lab section with no marker.
- **Secrets:** the three wifi passphrases are `'<vault:wifi seed>'` and so on, filled from the
  site vault at `apply`. The other secret-named options (`uhttpd.main.key`, `rpcd` login
  `password`, `luci.flash_keep.passwd`) are references (a path, `$p$root`), not secrets.

## Tools

| command | what it does |
|---|---|
| `site/router/config-tool check` | the repository against the live router, in the drift check's normal form; a redacted diff on a difference |
| `site/router/config-tool apply --dry-run` | renders every package and compares it with the router byte for byte; imports nothing |
| `site/router/config-tool apply` | imports only the packages that differ, behind a 120 s rollback on the router; confirms after the router, infra, DNS (core) and the internet answer; the fixture hash before and after must be equal; then `check` and `expected` |
| `site/router/config-tool expected` | pushes the normal form to infra for the drift check |
| `site/router/config-tool pull` | rewrites `config/` from the router (only to adopt a change made on the router on purpose; review the diff) |
| `tools/router-backup.sh` | the way back: `sysupgrade -b`, encrypted to the .sops.yaml recipients, into `backup/` |

**To change the router:** edit `config/<package>`, `apply --dry-run`, `tools/router-backup.sh`,
`apply`, commit (the config, the backup) and push. Changes made in LuCI or by `uci` on the router
are drift and are reverted by the next `apply`.

**The drift check:** infra's daily device-config job (User Scripts) normalises the router's
export with `uci-normal.awk` (the lab's sections left out, secret-named options redacted),
compares it with `/mnt/data/system/device-configs-expected/router.normal`, and writes the count to
`seed-state/router-drift.lines`, the diff to `router-drift.diff`. seed-metrics.sh exports
`seed_router_config_drift_lines`; **RouterConfigDrift** fires on anything but 0 (-1: no expected
copy). infra's copies of `uci-normal.awk` and `device-config.sh` are in
`/mnt/data/system/seed-bin/`, by hand like the other job scripts (compare by sha256).

## The way back

1. **A bad apply that cuts the agent box off** rolls itself back: the router restores the
   packages it had before and runs `reload_config` 120 s after the import unless the agent box
   has confirmed. Proven 20260929 04:09 to 04:11Z (the confirmation failed on a missing `dig`,
   and the router rolled back `system` by itself).
2. **A bad config that was confirmed:** `git revert` the change and `apply` again.
3. **Anything worse:** restore the newest `backup/*.tar.gz.age`. Decrypt it with the master key
   (vault `sops master age key`, in a pipe), copy it to the router's `/tmp`, run
   `sysupgrade -r /tmp/<file>.tar.gz`, then `reboot`. It restores /etc/config in full, the lab's
   sections included, as they were when it was taken. Compare the fixture hash after.
4. **The router unreachable on the LAN:** that needs hands (its console, or a factory reset
   and step 3).
