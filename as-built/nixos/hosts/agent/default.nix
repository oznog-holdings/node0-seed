# agent: the agent box (index › Rung 2), on Larkbox two (Chuwi LarkBox X, Intel N100, 12 GB
# soldered, one NVMe RS512GSSD510 serial SERIAL-PLACEHOLDER, wired enp2s0 02:00:00:00:00:01 at
# 2.5 Gb/s). Its firmware can't keep settings and it doesn't return after a power cut:
# restart warm only, never power-cycle; it rides the UPS and is not told to shut down.
{ config, lib, pkgs, modulesPath, ... }:
let keys = import ../../keys.nix; in
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ./disko.nix ../../modules/agent-tools.nix ../../modules/pull-deploy.nix ../../modules/boot-assessment.nix ../../modules/rescue-entry.nix ../../modules/agent-services.nix ../../modules/watcher.nix ../../modules/pr-check.nix ../../modules/work-state.nix ../../modules/wifi-test.nix ];

  # deployed from the forge's `deploy` ref (modules/pull-deploy.nix); promotion = push main to deploy
  seed.pullDeploy = { enable = true; host = "agent"; };

  # --- hardware (nixos-generate-config --no-filesystems on the box, 20260924)
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" "sdhci_pci" ];
  boot.kernelModules = [ "kvm-intel" ];
  hardware.cpu.intel.updateMicrocode = true;
  hardware.enableRedistributableFirmware = true;
  nixpkgs.hostPlatform = "x86_64-linux";

  # --- boot that doesn't depend on the firmware remembering anything: systemd-boot at the
  # removable path \EFI\BOOT\BOOTX64.EFI (bootctl install --no-variables); 20 generations in
  # the menu are the rescue (design › Deploying). No boot counting in this NixOS (finding).
  boot.loader.systemd-boot = { enable = true; configurationLimit = 20; };
  boot.loader.efi.canTouchEfiVariables = false;
  # a hang ends in a warm reset by the chipset watchdog (iTCO_wdt / intel_oc_wdt), never a power-cycle
  systemd.settings.Manager = { RuntimeWatchdogSec = "30s"; RebootWatchdogSec = "5min"; };
  boot.kernelParams = [ "panic=30" ];
  services.logind.settings.Login.HandlePowerKey = "ignore";
  zramSwap.enable = true;

  # --- names and network (D.04: static outside the DHCP pool)
  networking.hostName = "agent";
  networking.domain = "seed.example.com";
  networking.useDHCP = false;
  networking.useNetworkd = true;
  networking.wireless.enable = false;
  systemd.network.networks."10-lan" = {
    matchConfig.MACAddress = "02:00:00:00:00:01";
    address = [ "192.168.1.11/24" ];
    gateway = [ "192.168.1.1" ];
    dns = [ "192.168.1.15" "192.168.1.16" ];   # Technitium: ns1 (on core), then ns2 (on infra), from rung 5 › F
    ipv6AcceptRAConfig.UseDNS = false;          # the router must not become a second resolver (F-RA-DNS)
  };
  # the site's few addresses from the repo: names resolve without infra (index › Rung 2, R2.09)
  networking.hosts = {
    "192.168.1.1"  = [ "fw.seed.example.com" "fw" ];            # the firewall, the gateway from the rung 6 cut-over (20260929)
    "192.168.1.4"  = [ "router.seed.example.com" "router" ];    # the OpenWrt One, the access point from rung 6
    "192.168.1.10" = [ "infra.seed.example.com" "infra" "git.seed.example.com" ];   # the forge: deploys resolve without infra's DNS
    "192.168.1.11" = [ "agent.seed.example.com" "agent" ];
    "192.168.1.12" = [ "core.seed.example.com" "core" "ntfy.seed.example.com" ];   # ntfy: the watcher's alerts resolve without DNS
    "192.168.1.13" = [ "agentvm.seed.example.com" "agentvm" ];
    "192.168.1.20" = [ "compute.seed.example.com" "compute" ];
  };
  networking.firewall = { enable = true; allowedTCPPorts = [ 22 ]; };   # deny inbound by default (R2.22)

  # --- time (design › Time: the internal server with prefer, the public pool without; from
  # rung 3 core is the primary and infra the second)
  time.timeZone = "America/Denver";
  services.timesyncd.enable = false;
  services.chrony = {
    enable = true;
    servers = [ ];
    extraConfig = ''
      server 192.168.1.12 iburst prefer
      server 192.168.1.10 iburst
      pool pool.ntp.org iburst
      makestep 1 3
    '';
  };

  # --- people and agents: fixed uids (R2.17, the same as agentvm), no mutable users
  users.mutableUsers = false;
  users.users.admin = {
    isNormalUser = true; uid = 1000; group = "users"; extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ keys.compute keys.orchestrator ];
  };
  users.groups.agent.gid = 1001;
  users.users.agent = {
    isNormalUser = true; uid = 1001; group = "agent";
    # the builder (an agent) keeps unprivileged access here once its key leaves root (F-AGENT-ADMIN)
    openssh.authorizedKeys.keys = [ keys.compute keys.agentvmBuilder keys.orchestrator keys.cutoverLogReader ];
  };
  # root: the orchestrator's fixture only. The builder's key was here for the install and first
  # checks (owner, 20260924) and was removed by this commit once the box deployed itself from
  # the forge; the builder keeps the unprivileged `agent` account (F-AGENT-ADMIN).
  users.users.root.openssh.authorizedKeys.keys = [ keys.orchestrator ];
  security.sudo.wheelNeedsPassword = false;     # admin has no password (key only), as on agentvm

  services.openssh = {
    enable = true;
    settings = { PasswordAuthentication = false; KbdInteractiveAuthentication = false; PermitRootLogin = "prohibit-password"; };
    # the host key is made before the install and kept in the identity store (R1.73, R2.24)
    hostKeys = [ { path = "/etc/ssh/ssh_host_ed25519_key"; type = "ed25519"; } ];
  };

  # --- /work (design › Development): one directory per user, before the first clone
  systemd.tmpfiles.rules = [
    "d /work/admin 0750 admin users -"
    "d /work/agent 0750 agent agent -"
  ];

  nix.settings = { experimental-features = [ "nix-command" "flakes" ]; trusted-users = [ "root" "admin" ]; };
  services.journald.extraConfig = "SystemMaxUse=500M";    # R2.27
  environment.systemPackages = with pkgs; [ vim htop restic efibootmgr nvme-cli xfsprogs ];   # git, jq and the agent tools come from modules/agent-tools.nix

  system.stateVersion = "26.05";
}
