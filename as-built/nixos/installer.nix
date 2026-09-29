# A keyed NixOS installer (rung 2 install without hands; site/runbooks/rung2-agent-install.md).
# It boots, takes a DHCP lease, and accepts ssh as root with the builder's key and the
# orchestrator's fixture key only. No passwords. A hung kernel ends in a warm reset by the
# hardware watchdog (the box may never be power-cycled).
{ config, lib, pkgs, disko, ... }:
let keys = import ./keys.nix; in
{
  networking.hostName = "seed-installer";
  services.openssh = {
    enable = true;
    settings = { PermitRootLogin = "prohibit-password"; PasswordAuthentication = false; };
  };
  users.users.root.openssh.authorizedKeys.keys = [ keys.agentvmBuilder keys.orchestrator ];
  users.users.nixos.openssh.authorizedKeys.keys = [ keys.agentvmBuilder keys.orchestrator ];

  # the guard against a hung boot: warm resets only
  systemd.settings.Manager = { RuntimeWatchdogSec = "30s"; RebootWatchdogSec = "5min"; };
  boot.kernelParams = [ "panic=30" ];
  boot.supportedFilesystems.zfs = lib.mkForce false;   # not used on the agent box; keeps the image small

  environment.systemPackages = [ disko.packages.x86_64-linux.disko pkgs.git pkgs.efibootmgr pkgs.nvme-cli pkgs.rsync pkgs.xfsprogs ];
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  image.fileName = lib.mkForce "seed-installer-${config.system.nixos.label}.iso";
  isoImage.squashfsCompression = "zstd -Xcompression-level 6";
}
