# The sandbox (design › Operating: "a sandbox VM on the infra box, from the same repo, with its own
# name and nothing of production in it, where a change to a role is deployed first. It is marked a
# sandbox in the inventory, not monitored by design, and not brought back after a reboot";
# R1.92, R1.94, R1.95).
#  - from the same repo: this flake; the image is built from it (system.build.images.qemu-efi)
#  - nothing of production: no sops, no secrets, no production data or mounts; its own keys
#  - deployed first: it pulls `main` (every change as soon as it is pushed), production pulls
#    `deploy` (only after the pull request, the build check and the merge)
#  - isolation is enforced on infra, not here (site/infra/sandbox/isolation.sh): NAT out, nothing
#    in, no route to the LAN or to infra's services, the forge's git port the one exception
#  - not monitored, not autostarted (Unraid VM autostart off); hosts.md and NetBox mark it sandbox
{ config, lib, pkgs, modulesPath, ... }:
let keys = import ../../keys.nix; in {
  # qemu-guest: virtio drivers in the initrd (without it the first boot couldn't find its disk)
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ../../modules/agent-tools.nix ../../modules/pull-deploy.nix ];

  seed.pullDeploy = { enable = true; host = "sandbox"; ref = "main"; };

  networking.hostName = "sandbox";
  networking.useDHCP = true;                              # libvirt's NAT network on infra (virbr0)
  networking.firewall = { enable = true; allowedTCPPorts = [ 22 ]; };
  services.openssh = { enable = true; settings = { PasswordAuthentication = false; KbdInteractiveAuthentication = false; PermitRootLogin = "prohibit-password"; }; };

  users.mutableUsers = false;
  users.users.admin = {
    isNormalUser = true; uid = 1000; group = "users"; extraGroups = [ "wheel" "libvirtd" ];
    openssh.authorizedKeys.keys = [ keys.builderAgent keys.compute keys.orchestrator ];
  };
  users.groups.agent.gid = 1001;
  users.users.agent = { isNormalUser = true; uid = 1001; group = "agent"; openssh.authorizedKeys.keys = [ keys.builderAgent ]; };
  users.users.root.openssh.authorizedKeys.keys = [ keys.builderAgent ];   # nixos-rebuild --target-host
  # the site agents' rehearsal ground (briefs/agents.md › J): their account, root through sudo, VMs of its own
  users.groups.tender.gid = 1002;
  users.users.tender = { isNormalUser = true; uid = 1002; group = "tender"; extraGroups = [ "wheel" "libvirtd" ];
    openssh.authorizedKeys.keys = [ keys.tender ]; };

  # nested VMs (the host CPU is passed through; infra has kvm_intel nested=1). Bounded by the sandbox itself:
  # 4 vCPUs, 16 GB, a 128 GB disk (site/runbooks/sandbox.md). Their networking is user-mode (passt), so no
  # address range of their own appears anywhere: reach them through a forwarded port on the sandbox.
  virtualisation.libvirtd = { enable = true; qemu = { runAsRoot = false; swtpm.enable = false; }; };
  environment.systemPackages = with pkgs; [ virt-manager qemu_kvm passt cloud-utils ];
  security.sudo.wheelNeedsPassword = false;

  # the image: UEFI (OVMF on Unraid), one qcow2 disk; the image module lays out ESP + root
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;
  boot.growPartition = true;
  # the image's own layout (labels set by the qemu-efi image), declared so the plain system build
  # (pull-deploy, the PR build check) knows its root
  fileSystems."/" = { device = "/dev/disk/by-label/nixos"; fsType = "ext4"; autoResize = true; };
  fileSystems."/boot" = { device = "/dev/disk/by-label/ESP"; fsType = "vfat"; options = [ "umask=0077" ]; };
  services.qemuGuest.enable = true;
  nix.settings = { experimental-features = [ "nix-command" "flakes" ]; trusted-users = [ "root" "admin" ]; };
  time.timeZone = "America/Denver";
  system.stateVersion = "26.05";
}
