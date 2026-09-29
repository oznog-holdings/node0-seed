# The site's configuration (private, real values)

This is the seed site's config repo of record until the site's Forgejo exists (Q2 answer:
real values go in a private repo on the site's Forgejo; until then they live only here).
Templates with synthetic values go to `node0-seed`. No secret values here: secrets are
fetched from the vault at deploy time and land on infra as 0600 files in
`/mnt/data/system/secrets` (a 0700 ZFS dataset; design › Secrets: "Unraid ... keeps its
few in a mode 0600 directory on the pool").

- `hosts.md`: the inventory (design › Inventory)
- `dns/rewrites.yaml`: the site's names, one list (design › DNS); rendered by `bin/render-adguard`
- `infra/`: per-container config, image recipes and Unraid templates
- `bin/`: render and deploy scripts, run from agentvm
