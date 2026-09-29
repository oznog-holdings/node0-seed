# Two ZFS demonstrations: a special vdev, and growing a raidz one disk at a time

Run on infra on 20260928 (OpenZFS 2.4.3), on spare drives and on files. **The data pool wasn't
touched.** The full transcript is `evidence/20260928-zfs-demos.txt`, produced by
`tools/zfs-demos.sh`, which prints every command before its output. Everything here can be repeated
on any spare disk, or on files.

## 1. A special vdev (the "metadata vdev")

**What it is.** A pool can have a *special* vdev on faster storage. ZFS puts the pool's metadata
there, and, per dataset, every block at or under `special_small_blocks`. Large blocks stay on the
data vdevs. It suits a pool of large disks with a fast small device beside them: directory walks,
many small files, and dedup tables get faster.

**The demonstration:** a throwaway pool, with the data vdev on the spare 1 TB NVMe (serial
SERIAL-PLACEHOLDER) and the special vdev on an empty 32 GB Optane (SERIAL-PLACEHOLDER).

```
zpool create -o ashift=12 -O compression=lz4 -O atime=off demo <1 TB> special <Optane>
zfs create demo/big                                         # default: only metadata goes to the special vdev
zfs create -o special_small_blocks=32K demo/small           # also every block of 32K or less
```

| after writing | on the 1 TB (data) | on the Optane (special) |
|---|---|---|
| nothing | 0 | 420K (the pool's own metadata) |
| 2 GiB of large files to `demo/big` | 2.00G | 2.55M: their metadata only |
| 20,000 files of 4 KiB to `demo/small` | 2G (unchanged) | 89.9M: the small files themselves |

`zpool list -v` shows the split per vdev. A directory walk of the 20,000 files right after a fresh
import took 0.02 s. There was no pool without a special vdev to compare against, so read that as
"metadata reads are cheap", not as a measured speed-up.

**What a reader must know before adding one:**
- **A special vdev is not a cache.** It holds the only copy of the pool's metadata: **lose it and
  you lose the whole pool.** So it must be as redundant as the data vdevs (a mirror beside a raidz1,
  a 3-way mirror beside a raidz2). ZFS refuses a less redundant one unless forced:

  ```
  zpool add rzs special /tmp/zfiles/s3      # pool: raidz1 + a mirror special
  mismatched replication level: pool uses mirror and new vdev is file   (use '-f' to override)
  ```

  The first demo used a single Optane only because the second still held an older server's pool.
  Once the owner freed it, the demo was redone with a mirror (1b).
- **Adding one to a raidz pool is one-way.** A special vdev can be removed only from a pool without
  raidz top-level vdevs; its blocks then move back to the data vdevs:

  ```
  zpool remove demo <Optane>        # demo: one plain disk + special -> allowed, data moved, same hash
  zpool remove rzs mirror-1         # raidz1 + special mirror ->
  cannot remove mirror-1: invalid config; all top-level vdevs must have the same sector size and not be raidz.
  ```

  The site's `data` pool is raidz1, so a special vdev there would stay forever.
- **When it fills up**, new metadata and small blocks spill to the data vdevs, so size it for the
  metadata. The small blocks you ask it to hold come on top.
- **Only new writes go there.** Blocks written before the special vdev existed stay where they are
  until rewritten (`zfs rewrite`, below).

### 1b. The proper form: a mirrored special vdev (20260928, 13:43Z)

**The first demonstration used a single Optane only because the second one still held an older
server's pool.** The owner then decided that pool wasn't needed, and it was cleared
(`zpool labelclear`, `wipefs`; evidence/20260928-optane-wipe.txt). The demonstration was then run as
a reader should see it (evidence/20260928-zfs-special-mirror.txt):

```
zpool create -o ashift=12 -O compression=lz4 -O atime=off demo <1 TB> special mirror <Optane 1> <Optane 2>
zfs create demo/big
zfs create -o special_small_blocks=32K demo/small
```

| | on the 1 TB (data) | on the special mirror |
|---|---|---|
| 2 GiB of large files in `demo/big`, 20,000 files of 4 KiB in `demo/small` | 2G: the large files' data | 90.8M: all the metadata, plus the small files themselves |

**Losing one side of the mirror** (`zpool offline demo <Optane 2>`):
- The pool goes **DEGRADED** and stays up, with the special `mirror-1` DEGRADED and one Optane
  OFFLINE.
- **It even exported and imported again** with one Optane offline: the pool's metadata came from
  the other.
- The large file's hash, the hash of all 20,000 small files and their count were all unchanged, and a
  new file was written while degraded.

**`zpool online`** brought the Optane back. It resilvered what it had missed (596K, under a second),
and a scrub then found 0 errors.

That's the point of the mirror. With a single special device, the same loss would have lost the
whole pool, because the metadata has no other copy.

Afterwards the pool was destroyed and all three drives wiped: no partition table on any of them.
The `data` pool was untouched (ONLINE before and after).

## 2. Growing a raidz vdev by one disk (raidz expansion)

**What it is.** From OpenZFS 2.3 (`feature@raidz_expansion`), a raidz vdev can take one more disk
while the pool stays online. Before that, a raidz could grow only by adding a second whole vdev
beside it, or by replacing every disk with a larger one.

**The demonstration**, on four 512 MB files in RAM (the same commands take whole disks):

```
zpool create rz raidz1 f1 f2 f3                 # 3 wide: 2 data + 1 parity
# write 600 MB, sha256 07cd4ce22a53fa8a
zpool attach rz raidz1-0 f4                     # the fourth disk joins the vdev
zpool wait -t raidz_expand rz                   # "expanded raidz1-0 copied 888M"
zfs rewrite -v /path/to/file                    # optional: re-lay old blocks at the new width
```

| | raw size | the file uses | available | sha256 |
|---|---|---|---|---|
| raidz1, 3 wide | 1.38G | 601M | 209M | 07cd4ce2… |
| after `attach` + `wait` | 1.38G | 601M | 209M | the same |
| after `zfs rewrite` of the file | 1.88G | 553M | 598M | the same |

**What a reader must know:**
- **The data is safe and online throughout.** The expansion copies existing blocks across the
  wider vdev, and the file's hash never changed.
- **Old blocks keep their old layout** (2 data + 1 parity here). Only new writes use 3 + 1, so the
  capacity you gain shows up gradually. `zfs rewrite` (OpenZFS 2.4) rewrites files in place at the
  new width, and space accounting improves as it does. Here, `zpool list` showed the new raw size
  only after the rewrite.
- **One disk at a time, and never to change the parity level.** A raidz1 stays raidz1 when it
  grows.
- **A mirror never becomes a raidz.** Attaching a disk to a mirror makes a wider mirror (3-way
  here). Turning mirrors into a raidz means a new pool and a copy.
- The pages' rule stands: grow by adding a second group or mirror beside the first, or one drive at
  a time to a raidz.

## Clean-up (shown in the transcript)

- **The demo pool was destroyed**, and both drives wiped (`wipefs -a`). `lsblk` shows them with no
  partition table.
- **The file pools were destroyed** and the files removed.
- **The `data` pool is unchanged:** 1.39T, 25.6G allocated, ONLINE, before and after.
