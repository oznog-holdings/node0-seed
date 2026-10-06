# Rung 0: the laptop

**In plain terms.** Your documents, photos and records are copied every day to storage in the
cloud. A lost laptop, a mistake or ransomware on your laptop can hide those copies but not
delete them, and anything hidden can be brought back for 30 days. It costs little, and it
starts the habit of backups that every later rung keeps.

## What you get

Your core data (documents, finance, photos, and the site's config repository once it
exists) backed up offsite from the laptop you already have. The key the laptop holds can
hide files in the bucket but not delete them, and hidden versions are kept for 30 days, so a
wipe with that key can be undone within 30 days.

**Buy.** No hardware. Rent a cloud bucket and a domain.

**What still fails.** Everything lives on the laptop, so everything stops when it closes,
and the backup runs only while it is open. [Rung 1](../1-infra/) fixes that.

**Built by an agent.** Keel, an agent working from a brief, built every rung of the Seed,
starting from this laptop. [The agents](../../agents/) page says how it worked and what kept it
in bounds.

Stop here if what you need is "my important files survive my laptop". Rung 0 does that.

## Decisions and options

**A bucket with two keys and a 30-day rule.** The **writer** key can list, read and write
but not delete. The **admin** key can delete, lives only in the password manager, and only a
person uses it. The bucket keeps hidden (overwritten or "deleted") versions for 30 days, so
anything the writer key removes can still be recovered for a month. To recover a file, remove
its hide marker with the admin key: `b2 file unhide b2://<bucket>/<file>` needs `deleteFiles`,
which the writer key lacks. `b2 ls --versions --recursive b2://<bucket>/<path>` lists what was
hidden.
*Would change it:* nothing we found. B2's "Keep only the last version" setting does not
protect you, because a deleted file is gone a day later.

- **Making the writer key needs the command-line tool.** On Backblaze B2 the website's
  "Read and Write" key includes delete (checked 20260923). Create the writer key with the CLI
  (`b2 key create --bucket <bucket> <name> listBuckets,listFiles,readFiles,writeFiles`),
  logged in with a key that may create keys (the account's master key). A key restricted
  to one bucket cannot create other keys.
- **Point restic at the S3 endpoint.** B2's native API refused a key made this way on
  versions 2 and 3 (HTTP 400) and accepted it on version 4. restic and rclone accepted it
  through B2's S3-compatible endpoint (`s3:https://s3.<region>.backblazeb2.com/<bucket>/<path>`),
  with the key ID in `AWS_ACCESS_KEY_ID` and the key in `AWS_SECRET_ACCESS_KEY`.
- **restic works with a key that cannot delete.** When restic removes its own lock files,
  B2 keeps each one as a hidden version instead of deleting it, and the 30-day rule clears
  them. A permanent delete is refused. Pruning on the bucket needs the admin key, so a
  person does it.

**The repository password goes in the password manager before `restic init`.** Generate it
there, never type or display it, and have the backup job fetch it into `RESTIC_PASSWORD`
at run time, with the bucket key's ID and secret, and unset all three variables when it ends.

**Private dictation from day one: FluidVoice.** [FluidVoice](https://altic.dev/fluid) turns
speech into text in any app on a Mac, with speech models that run on the Mac itself, so your
voice never leaves it. It is free and open source (GPLv3). Its optional clean-up step can call a
hosted model; leave that off to keep everything local. Christoph uses it a lot.
*Would change it:* you are not on a Mac yet (iPhone and Windows versions are announced, not
out, as of 20260928).

**Restore before you trust it.** Restore a few files from each kind of data to a scratch
directory and compare them with the originals by sha256. A backup nobody has restored is a
belief.

## Costs and measurements

- Hardware: none.
- Recurring: the bucket (billed per TB stored, including hidden versions for 30 days), and
  a domain, which rung 1's certificates need. At list prices, a `.com` domain and one DNS zone come to about
  $22 a year (the bench's `.co` domain was $48.90 a year), on a DNS plan without domain-scoped tokens (a plan
  with them costs more; see [costs](../../costs.md)), and 1.6 GB stored, inside B2's free first
  10 GB, so nothing for storage. The design had estimated $10 to $25 a month.
- On our bench, on 20260923: a synthetic set of documents, finance files and photos backed up and
  restored with identical hashes and file counts; a permanent delete with the writer key
  refused; hiding allowed. The probes are
  [b2-keycheck.py](../../as-built/tools/b2-keycheck.py) (what a key may do) and
  [b2-delete-probe.py](../../as-built/tools/b2-delete-probe.py) (delete refused, hide
  allowed).

## Runbooks

1. Create a password manager account, and turn on two-factor with a separate
   authenticator app.
2. On the B2 website, create the bucket: private, encryption on, lifecycle "keep prior
   versions for 30 days".
3. On the website, make the admin key, restricted to the bucket. Save it in the password
   manager where only you use it.
4. Log the CLI in with the account's master key (`b2 account authorize`), then make the
   writer key (the `b2 key create` command above). Save it in the password manager.
5. Run `b2 bucket get <bucket>`. The lifecycle rule should read
   `daysFromHidingToDeleting: 30`. If it does not, fix the lifecycle on the website before
   going on.
6. Run `b2 key list`. The writer key's capabilities should not include `deleteFiles`. If
   they do, delete that key (`b2 key delete <key ID>`) while logged in with the master key,
   and make it again with the CLI. The bucket-restricted admin key cannot delete keys; that
   needs `deleteKeys`.
7. Generate the repository password in the password manager. Put the writer key
   (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`), the password (`RESTIC_PASSWORD`) and the
   repository
   (`RESTIC_REPOSITORY=s3:https://s3.<region>.backblazeb2.com/<bucket>/<path>`) in the
   environment, so every later command uses the same repository. Run `restic init`.
8. Run `restic backup` of your sources, with `--host` set to the laptop's name.
9. Run `restic restore latest --target <scratch directory>`.
10. Compare sha256 hashes and file counts between the originals and the restored copy. They
    should be identical. If any differ, stop and find out why before scheduling anything.
11. Schedule the backup on the laptop. It is the only job the laptop carries, and only
    until rung 1 moves backups onto infra.

The bench's own job is [rung0-restic.sh](../../as-built/tools/rung0-restic.sh). It fetches
the keys and password from the password manager, refuses to run if a source is missing or
empty, and backs up.

## Configuration

_Not yet templated. Use the bench's job above,
[as-built/tools/rung0-restic.sh](../../as-built/tools/rung0-restic.sh), as a worked example._
