# The agent box's rescue system (R2.08): the fallback of last resort, independent of every deploy.
# It boots entirely from RAM (a netboot kernel and initrd holding the whole system), so a broken root
# filesystem, /work or deploy can't stop it. It's installed on the ESP from a pinned build
# (rescue-pin.nix, modules/rescue-entry.nix) and never replaced by a deploy, and never produced by kexec.
# It carries only a known-good network (192.168.1.11 by the cabled port's MAC, DHCP on any other port)
# and sshd for the builder's key and the orchestrator's. Its own ssh host key is made once on the ESP
# (/boot/rescue/ssh_host_ed25519_key) and read from there at boot.
{ config, lib, pkgs, modulesPath, ... }:
let keys = import ./keys.nix; in
{
  imports = [ (modulesPath + "/installer/netboot/netboot.nix") (modulesPath + "/profiles/minimal.nix") ];
  networking.hostName = "agent-rescue";
  networking.domain = "seed.example.com";
  networking.useDHCP = false;
  networking.useNetworkd = true;
  networking.wireless.enable = false;
  systemd.network.networks."10-lan" = {
    matchConfig.MACAddress = "02:00:00:00:00:01";          # the agent box's cabled port (hosts.md)
    address = [ "192.168.1.11/24" ];
    gateway = [ "192.168.1.1" ];
    dns = [ "192.168.1.12" "192.168.1.10" ];
  };
  systemd.network.networks."20-other" = { matchConfig.Type = "ether"; networkConfig.DHCP = "ipv4"; };   # the cable on the other port

  services.openssh = {
    enable = true;
    settings = { PermitRootLogin = "prohibit-password"; PasswordAuthentication = false; KbdInteractiveAuthentication = false; };
    hostKeys = [ { path = "/etc/ssh/ssh_host_ed25519_key"; type = "ed25519"; } ];
  };
  users.users.root.openssh.authorizedKeys.keys = [ keys.builderAgent keys.orchestrator ];
  # the fixed host key from the ESP (read-only), before sshd; if it's missing, sshd makes a new one
  systemd.services.seed-rescue-hostkey = {
    description = "The rescue system's own ssh host key, from the ESP";
    wantedBy = [ "multi-user.target" ]; before = [ "sshd.service" "sshd-keygen.service" ];
    serviceConfig.Type = "oneshot";
    path = [ pkgs.util-linux pkgs.coreutils ];
    script = ''
      mkdir -p /run/esp
      for i in $(seq 1 20); do [ -e /dev/disk/by-partlabel/disk-main-ESP ] && break; sleep 1; done
      mount -o ro /dev/disk/by-partlabel/disk-main-ESP /run/esp || exit 0
      if [ -s /run/esp/rescue/ssh_host_ed25519_key ]; then
        install -D -m 0600 /run/esp/rescue/ssh_host_ed25519_key /etc/ssh/ssh_host_ed25519_key
        install -D -m 0644 /run/esp/rescue/ssh_host_ed25519_key.pub /etc/ssh/ssh_host_ed25519_key.pub
      fi
      umount /run/esp
    '';
  };

  # a hang ends in a warm reset, as on the box itself
  systemd.settings.Manager = { RuntimeWatchdogSec = "30s"; RebootWatchdogSec = "5min"; };
  systemd.enableEmergencyMode = false;
  boot.kernelParams = [ "panic=30" "boot.panic_on_fail" ];
  boot.supportedFilesystems.zfs = lib.mkForce false;

  # enough to look at and mend the box: disks, filesystems, the ESP (sfdisk is in util-linux)
  environment.systemPackages = with pkgs; [ xfsprogs e2fsprogs dosfstools efibootmgr ];
  # netboot.nix tags its system "kexec" (netboot.nix 152); this one is booted by systemd-boot from the ESP
  system.nixos.tags = lib.mkForce [ "rescue" ];
  # small: no nix, no nixpkgs source, no installer tools in the image (they were 400 MiB of its closure)
  nix.enable = false;
  nixpkgs.flake = { setNixPath = false; setFlakeRegistry = false; };
  system.disableInstallerTools = true;
  system.switch.enable = false;   # a RAM system never switches (it pulled perl in); xfsprogs keeps python (xfs_scrub), for xfs_repair
  system.stateVersion = "26.05";
}
