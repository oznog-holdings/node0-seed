# The sandbox: the site agents' rehearsal ground

A NixOS VM on infra (`nixos/hosts/sandbox`, R1.92).
- Built from this repo; it pulls `main`, so a change reaches it before production.
- Nothing of production in it: no secrets, no data, no mounts.
- Isolated on infra (`site/infra/sandbox/isolation.sh`).
- **Not monitored and not autostarted:** it is down after infra reboots until someone starts it.

Break things here, not on the site.

## Its limits (set 20260930, briefs/agents.md › J)
| | limit | how it is held |
|---|---|---|
| CPU | 4 vCPUs, pinned to infra's threads 2 to 5, host CPU passed through (`vmx`: it runs VMs itself) | the VM definition (Unraid UI › VMs › sandbox › Edit) |
| memory | 16 GB, fixed (current = max) | the VM definition. Proven: 110 % of its memory allocated inside gave 30 OOM kills inside; qemu's RSS on infra peaked at 16.6 GB; infra kept 15.9 GB available, no OOM, all 17 containers up |
| disk | a 128 GB raw image, `/mnt/user/domains/sandbox/vdisk1.img`, on its own dataset `data/domains/sandbox` | `refquota` 130G (the image can't take more), `refreservation` 130G (its space is guaranteed, so a full pool elsewhere can't fail it and it can't eat the pool), `quota` 264G (room for the clean snapshot to diverge fully). Proven: DISK-PROOF |
| VMs inside | within the above: they share its 4 vCPUs, 16 GB and 128 GB | the sandbox's own limits; nothing inside can take more from infra |

**Infra's headroom** (20260930): 46.8 GB RAM.
- The sandbox takes 16 GB when running, and `agentvm` (retired, still running) 16 GB.
- ZFS's ARC may take up to 9.8 GB, but gives memory back under pressure.
- With both VMs full, about 15 GB stayed available.
- Start the sandbox only when `free -g` on infra shows at least 20 GB available.
- Pool `data`: 770G available before the sandbox's reservation, 640G after.

## What it may reach
- **Allowed:** the internet (packages, images), through libvirt's NAT on infra. DNS comes from libvirt's dnsmasq
  (192.168.122.1). The forge's git port (192.168.1.10:2222) is the one exception, used by its read-only deploy key.
- **Blocked** (proven 20260930 from inside, and from a VM inside it):
  - the LAN: the firewall's UI, DNS and ssh; infra's ssh and HTTPS on both its addresses; core; the access point;
    ns2; compute;
  - the guest and IoT VLANs;
  - the tailnet: infra's tailnet address and 100.100.100.100;
  - every private, CGNAT and link-local range.
- **IPv6:** none; it has no global address and no route.
- **Nothing reaches in:** the LAN has no route to 192.168.122.0/24. You reach it through infra.

## Start
1. On infra, check the headroom: `free -g` (see above).
2. Run the isolation rules (idempotent; they also run at array start):
   `bash /boot/config/plugins/user.scripts/scripts/sandbox-isolation/script`. It prints
   `sandbox isolation: 12 rules, hooked: 1`.
3. Start it: Unraid UI › VMs › sandbox › Start, or `virsh start sandbox` on infra.
4. It takes its address by DHCP from libvirt: 192.168.122.155 (a fixed MAC, and the lease has held).
5. Within 15 minutes of starting, it deploys `main`.
6. **Stop:** UI › Stop, or `virsh shutdown sandbox`.

## Reach
- **From the agent box, as tender:** `ssh sandbox`. It jumps through `root@192.168.1.10`, and the host key is pinned
  in `/etc/ssh/ssh_known_hosts` (`nixos/modules/site-agents.nix`).
  - tender has root there through `sudo` and belongs to the `libvirtd` group.
- **The builder:** `ssh -J root@192.168.1.10 admin@192.168.122.155`.
- **Host key:** ED25519 `SHA256:HOST-KEY-FINGERPRINT-PLACEHOLDER`. The clean snapshot keeps it.

## A VM inside
- Its libvirt is `qemu:///system`.
- **Networking is user-mode only (passt):** a VM shares the sandbox's address and gets no network of its own.
  - Reach it through a forwarded port on the sandbox.
  - **Don't start libvirt's `default` network:** it is 192.168.122.0/24, the same range the sandbox itself is on.
- Traffic from a VM inside leaves as the sandbox's, so the isolation above applies to it too. This was proven:
  the internet answered 200 and the firewall was blocked.

**Create** (Debian 12 cloud image, ssh on sandbox port 2201):
```sh
sudo install -d -m 0711 /var/lib/libvirt/images /var/lib/libvirt/boot
cd /var/lib/libvirt/images
sudo curl -fsSLo debian12-base.qcow2 https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2
# check it against the SHA512SUMS beside it; then an overlay per VM:
sudo qemu-img create -f qcow2 -F qcow2 -b /var/lib/libvirt/images/debian12-base.qcow2 inner1.qcow2 8G
virt-install --connect qemu:///system --name inner1 --memory 1024 --vcpus 2 --import \
  --disk /var/lib/libvirt/images/inner1.qcow2,bus=virtio --osinfo debian12 \
  --network passt,model=virtio,portForward0.proto=tcp,portForward0.range0.start=2201,portForward0.range0.to=22 \
  --graphics none --serial pty,log.file=/var/log/libvirt/qemu/inner1-serial.log --noautoconsole \
  --cloud-init user-data=user-data,meta-data=meta-data
ssh -p 2201 <user>@127.0.0.1
```
- It boots to a login prompt in about 90 s; the serial log shows it.
- A backing file must be under `/var/lib/libvirt/images`, because qemu runs unprivileged and can't read your home.
- **Not yet working (20260930): getting an ssh key into the guest.**
  - With `--cloud-init user-data=…`, cloud-init ran but took its NoCloud data from DMI, and the user-data's user
    and key never arrived.
  - With a `cloud-localds` seed ISO as a CD-ROM, cloud-init didn't run at all.
  - The `nocloud` image has no openssh-server.
  - What did work: a login on the console, and typing through the monitor
    (`virsh qemu-monitor-command <vm> --hmp "sendkey <key>"`, since tty1 has a getty).
  - Solving this is a good first task for an agent.

**Destroy:** `virsh -c qemu:///system destroy inner1; virsh -c qemu:///system undefine inner1`. Then remove its
overlay from `/var/lib/libvirt/images`.

## Reset to clean
The clean snapshot is `data/domains/sandbox@clean-20260930`. It was taken fresh after it grew: `main` at 59d0241,
no VMs inside, no test files.
1. On infra: `virsh shutdown sandbox` and wait for `shut off` (`virsh domstate sandbox`).
2. `zfs rollback data/domains/sandbox@clean-20260930`
3. Start it (above). It pulls `main` again within 15 minutes.

A new clean snapshot replaces the old only with the owner's approval: snapshots are not deleted without it.
