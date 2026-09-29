# The agent box's fixed rescue boot entry (R2.08; rescue.nix is the system, rescue-pin.nix its pin).
# Installed on the ESP only from a build equal to the pin, and never replaced by a deploy: a deploy whose
# rescue build differs leaves the ESP's rescue as it is, and says so. NixOS's builder doesn't touch it:
# it manages only loader/entries/nixos* and EFI/nixos (systemd-boot-builder.py 257-279).
#  - /boot/rescue/{bzImage,initrd}: the RAM system; /boot/loader/entries/seed-rescue.conf, sort-key
#    zz-seed-rescue (after every NixOS entry, and outside boot-assessment.nix's patterns);
#  - /boot/rescue/ssh_host_ed25519_key: the rescue system's own host key, made once here (0600, on the
#    root-only ESP), read by the rescue at boot; not the agent box's key.
# Chosen once with `systemctl reboot --boot-loader-entry=seed-rescue.conf`, or by the loader itself when no
# NixOS entry can boot: with none left, the first bootable entry in its sorted list is this one.
{ config, lib, pkgs, rescue, ... }:
let
  b = rescue.config.system.build;
  pin = import ../rescue-pin.nix;
  entry = pkgs.writeText "seed-rescue.conf" ''
    title Seed rescue (RAM, fixed; R2.08)
    sort-key zz-seed-rescue
    version rescue-20260928
    linux /rescue/bzImage
    initrd /rescue/initrd
    options init=${pin.init} ${toString rescue.config.boot.kernelParams}
  '';
in {
  systemd.services.seed-rescue-entry = {
    description = "The fixed rescue boot entry on the ESP, as pinned";
    wantedBy = [ "multi-user.target" ];
    unitConfig.RequiresMountsFor = [ "/boot" ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    path = [ pkgs.coreutils pkgs.diffutils pkgs.openssh ];
    script = ''
      D=/boot/rescue; E=/boot/loader/entries/seed-rescue.conf
      k=${b.kernel}/${config.system.boot.loader.kernelFile}; i=${b.netbootRamdisk}/initrd
      is() { [ -f "$1" ] && [ "$(sha256sum < "$1" | cut -d' ' -f1)" = "$2" ]; }
      if is $D/bzImage ${pin.kernel} && is $D/initrd ${pin.initrd} && cmp -s ${entry} $E; then
        echo "rescue entry: on the ESP, as pinned"
      elif is $k ${pin.kernel} && is $i ${pin.initrd} && [ "${b.toplevel}/init" = "${pin.init}" ]; then
        install -d -m 0700 $D
        install -m 0644 $k $D/bzImage.new && install -m 0644 $i $D/initrd.new && sync
        mv $D/bzImage.new $D/bzImage && mv $D/initrd.new $D/initrd
        install -m 0644 ${entry} $E.new && mv $E.new $E && sync
        echo "rescue entry: installed as pinned (kernel ${pin.kernel}, initrd ${pin.initrd})"
      else
        echo "rescue entry: this deploy's rescue build differs from rescue-pin.nix; the ESP's rescue left as it is"
      fi
      if [ ! -s $D/ssh_host_ed25519_key ]; then
        install -d -m 0700 $D
        ssh-keygen -q -t ed25519 -N "" -C "root@agent-rescue" -f $D/ssh_host_ed25519_key
        echo "rescue host key made: $(ssh-keygen -lf $D/ssh_host_ed25519_key.pub)"
      fi
      echo "rescue host key: $(ssh-keygen -lf $D/ssh_host_ed25519_key.pub)"
    '';
  };
}
