# The rescue entry's pin (rescue.nix, modules/rescue-entry.nix). The ESP gets exactly these files and
# nothing else; a deploy whose rescue build differs leaves the ESP's rescue as it is, and says so.
# Changing the rescue is a change to this file: build .#nixosConfigurations.agent-rescue, then record
# the new hashes and init here. Pinned 20260928 from nixpkgs 1bc55b9def81.
{
  kernel = "d2b93e3505bb2ae229da98a29ddcb19dfe6cd9b9c6be672490b776d701070207";    # bzImage, 13M
  initrd = "77ad1f52fd33679f53ac67b9a3eb1ec57f66752eb7a1b91e2be6c80b15e02036";    # the RAM system (squashfs inside), 418M
  init = "/nix/store/34vwhqyl976bpnb1yrvfb9kfgl20h4rk-nixos-system-agent-rescue-rescue-26.05.20260922.1bc55b9/init";
}
