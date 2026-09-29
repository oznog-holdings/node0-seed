# The firewall (fw): OPNsense 26.7 on Larkbox one (rung 6)

- **`seed-config-export`** runs on the firewall as `/usr/local/sbin/seed-config-export`. It prints
  `/conf/config.xml` with these redacted on the box:
  - the WAN's settings and every WAN gateway (the owner's values: never read, copied or recorded);
  - the `fixture:` rules (the lab's);
  - every secret-bearing field, and `<revision>`.

  It then refuses to print if a private address outside the site's ranges is left. **Every read of
  the configuration goes through it**; nothing reads config.xml directly.
- **`config.expected.xml`** is the export of the configuration as the site wants it, updated with
  each change (one commit per step). The daily drift check compares the firewall's export with it.
- **The way back from a change:** OPNsense's own configuration history on the box (`/conf/backup`,
  System › Configuration › History). It holds the owner's values, so it stays there.
- **Changes are made:**
  - through OPNsense's API (`tools/fw-api.sh`, the key in vault item `opnsense api root`, the GUI's
    certificate pinned by its public key);
  - for the settings that have no API in 26.7 (the LAN's gateway, system DNS, NTP, the web GUI's
    interfaces), through OPNsense's own PHP functions (`config.inc`, `write_config`) and its
    `configctl` actions, as its console scripts do.

  Each change is read back through the export.
- **The WAN** (`re0`): the owner's to set (static, the upstream's values), never the builder's.
- **The LAN** (`re1`, RTL8125B): on the Realtek vendor driver (`os-realtek-re`; deviations.md).
  Every OPNsense upgrade must keep that plugin's kmod matched to the kernel.

## Reading `config.expected.xml`

`config.expected.xml` is the firewall's whole configuration as the site wants it: OPNsense's
`/conf/config.xml`, exported through `seed-config-export`. It is the reference the daily drift check
compares the live firewall against, and it changes only with a deliberate change (one commit each).

**What's in it:** the interfaces (the LAN on `re1` at 192.168.1.1, VLANs 20 and 30 as `opt1` and `opt2`), Kea's
DHCP (the three subnets, the dynamic DNS into lan.seed.example.com), Unbound for the guest and IoT networks, the
firewall rules and aliases, NTP, and the system settings.

**What's not in it:**
- The WAN's settings and gateway: the owner's, and `REDACTED`.
- Every secret: password hashes, keys and API secrets, all `REDACTED`.
- `<revision>`, the who and when of the last save.
- In the published copy, also:
  - **the lab's two `fixture:` rules**, which are removed entirely. They are the lab's harness, not part of
    the site. In this repository they appear by name only, with their contents `REDACTED`.
  - **Object ids** (the `uuid` attributes), which are replaced by `GENERATED-ID`.

**How to use it:**
- **To read the design:** the rules are under `<OPNsense><Firewall><Filter><rules>`, in `sequence` order
  (the interface names are OPNsense's: `lan`, `opt1` guest, `opt2` IoT). Kea is under
  `<OPNsense><Kea><dhcp4>`.
- **To compare a firewall with it:** run `/usr/local/sbin/seed-config-export` on the firewall and `diff`
  the output against this file, as `site/infra/backup/device-config.sh` does every day. Every line that
  differs is a change nobody recorded.
- **Not as a restore file.** With the WAN, the secrets (and, in the published copy, the fixture rules and
  ids) taken out, it can't be imported as it stands. Rebuild from OPNsense's own configuration history on
  the box (`/conf/backup`), or re-enter the redacted values by hand, then compare with this file.
