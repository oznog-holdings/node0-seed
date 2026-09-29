# D.05, the VM memory steps: agentvm at 8 GiB, then 16 GiB (for the orchestrator)

Each step restarts agentvm, which is the builder's machine, so the orchestrator runs them.
Infra is at 48 GB (mem= removed, rebooted 20260924 01:07). agentvm today: 4 GiB
(`<memory>` = `<currentMemory>` = 4194304 KiB, virtio balloon present), 2 vCPUs pinned to host
threads 6 and 7, autostart on.

**Before each step:** the builder has committed and pushed (seed-lab on the forge equals
agentvm's copy); `site/bin/check-after-reboot` passes (agentvm running, only the Watchdog
firing).

## Step A: 8 GiB

1. VMs › agentvm › **Stop** (a clean ACPI shutdown; NixOS honours it). Wait until the VMs
   page shows it stopped (`virsh domstate agentvm` = shut off). **Don't Force Stop** unless it
   hasn't stopped after 3 minutes.
2. VMs › agentvm › **Edit**: Initial Memory **8192 MB**, Max Memory **8192 MB** (equal, as
   today: no balloon games). Nothing else. **Update.**
3. Read back: `virsh dumpxml agentvm | grep -E "<memory|<currentMemory"` shows 8388608 KiB for
   both; the template on the flash changed only in memory (Unraid keeps it in
   `/etc/libvirt/qemu/agentvm.xml`).
4. **Start.** agentvm comes back at 192.168.1.13 (static). Check: `ssh agent@192.168.1.13
   free -m` shows about 7.8 GB total; `systemctl --failed` empty; `/work` mounted.
5. Wait **at least 30 minutes**, then on infra: `/mnt/data/system/seed-bin/d05-measure.sh
   48g-vm8 > /mnt/data/system/d05-48g-vm8-$(date +%Y%m%d-%H%M).txt`, and in the guest:
   `ssh agent@192.168.1.13 'free -m; grep -E "MemTotal|MemAvailable" /proc/meminfo; uptime'`
   (append it to the same file).

## Step B: 16 GiB

The same as step A with **16384 MB**, label `48g-vm16`. Check: guest total about 15.6 GB, host
available memory lower by about 8 GiB than in step A (the guest touches pages lazily, so its
RSS grows with use, not at boot).

## After

- Tell the builder the file names. The builder adds them to the evidence with the 16 GB and
  48 GB readings and writes the comparison. Two limits carried over from
  `evidence/20260924-d05-compare.md`: the readings are cold unless taken after a nightly
  cycle, and the guest's RSS reflects what it has touched, not its size.
- **What size stays:** the deviation says 4 GB. The builder's suggestion is to return to
  4 GiB after step B (the agent moves to Larkbox two at rung 2, and agentvm stays as the
  builder's box). The owner decides.
