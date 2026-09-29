#!/usr/bin/env python3
"""Drive Unraid's Boot Parameters page (Main > Flash > Boot Parameters) through the
same handler its web UI posts to, so Unraid's own validation, backups and model apply.
Password comes from $UNRAID_PASS (fetched by reference from Bitwarden); never printed.
Usage: unraid_bootparams.py HOST read | set-custom "<params>"
"""
import json, os, re, sys, requests, urllib3
urllib3.disable_warnings()
host, op = sys.argv[1], sys.argv[2]
base = f"http://{host}"
s = requests.Session()
r = s.post(f"{base}/login", data={"username": "root", "password": os.environ["UNRAID_PASS"]},
           allow_redirects=True, timeout=20)
page = s.get(f"{base}/Main/Boot", timeout=20).text
m = re.search(r"var csrf_token = '([0-9A-F]+)'", page)
if not m:
    sys.exit("login or csrf failed (no csrf_token on the Boot page)")
csrf = m.group(1)
H = f"{base}/plugins/dynamix/include/boot_params_handler.php"
cfg = s.post(H, data={"operation": "read_config", "csrf_token": csrf}, timeout=20).json()
if op == "read":
    print(json.dumps({k: v for k, v in cfg.items() if k != "full_config"}, indent=1))
    print("---full_config---"); print(cfg.get("full_config", ""))
    sys.exit(0)
if op == "set-custom":
    b = lambda k: "1" if str(cfg.get(k, "0")) in ("1", "true", "True") else "0"
    post = {
        "operation": "write_config", "csrf_token": csrf,
        "nvme_disable": b("nvme_disable"), "acs_override": cfg.get("acs_override", ""),
        "vfio_unsafe": b("vfio_unsafe"), "efifb_off": b("efifb_off"),
        "vesafb_off": b("vesafb_off"), "simplefb_off": b("simplefb_off"),
        "sysfb_blacklist": b("sysfb_blacklist"), "acpi_lax": b("acpi_lax"),
        "ghes_disable": b("ghes_disable"), "usb_autosuspend": b("usb_autosuspend"),
        "pcie_aspm_off": b("pcie_aspm_off"), "pcie_port_pm_off": b("pcie_port_pm_off"),
        "pci_noaer": b("pci_noaer"), "pci_realloc": b("pci_realloc"),
        "custom_params": sys.argv[3],
        "custom_params_comments": json.dumps(cfg.get("custom_params_comments") or {}),
        "default_boot_entry": cfg.get("default_boot_entry", "Unraid OS"),
        "timeout": str(cfg.get("timeout", "50")),
        "apply_to_unraid_os": "1", "apply_to_gui_mode": "1",
        "apply_to_safe_mode": "0", "apply_to_gui_safe_mode": "0",
        "exclude_framebuffer_from_gui": "0",
    }
    print(json.dumps(s.post(H, data=post, timeout=30).json(), indent=1))
