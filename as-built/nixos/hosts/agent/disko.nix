# Larkbox two's only disk (rung 2; design › Development: "/work is a separate XFS volume on a
# second NVMe or partition"). One NVMe slot, so /work is a partition. Named by serial, so the
# layout can never land on another disk (the USB stick included).
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/disk/by-id/nvme-RS512GSSD510_SERIAL-PLACEHOLDER";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = { type = "filesystem"; format = "vfat"; mountpoint = "/boot"; mountOptions = [ "umask=0077" ]; extraArgs = [ "-n" "BOOT" ]; };
        };
        root = {
          size = "100G";
          content = { type = "filesystem"; format = "ext4"; mountpoint = "/"; extraArgs = [ "-L" "nixos" ]; };
        };
        # /work: the partition only. disko never makes a filesystem on it, so no install or
        # reinstall run of disko can format /work (F-REBUILD-STATE). The filesystem is made ONCE by
        # hand (`mkfs.xfs -L work -m reflink=1`, runbooks/rebuild-agent-box.md) and mounted by
        # modules/work-state.nix, which also refuses a /work that isn't the pinned one.
        work = { size = "100%"; };
      };
    };
  };
}
