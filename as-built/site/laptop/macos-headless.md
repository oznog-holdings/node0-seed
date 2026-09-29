# compute: the macOS headless traps (R4.08)

design › Traps › macOS headless names five traps: upgrades drop permission grants, a pending prompt
hangs a job, Spotlight and the media daemons eat a server, CLI auth is per machine, and APFS is
case-insensitive. Checked as `seed` on 20260928; the two settings that need an administrator are at
the end.

| trap | state on compute | how it was checked |
|---|---|---|
| **an upgrade restarts the Mac or changes it under the site** | **macOS updates aren't installed automatically** (`AutomaticallyInstallMacOSUpdates` 0). Downloads (`AutomaticDownload` 1) and Security Responses and system data files (`CriticalUpdateInstall` 1, `ConfigDataInstall` 1) stay on: they keep it patched without a major upgrade. Checking is on (`softwareupdate --schedule`) | `defaults read /Library/Preferences/com.apple.SoftwareUpdate` |
| **upgrades drop permission (TCC) grants** | **no job of the site depends on a grant.** The backup excludes Desktop, Documents and Downloads, which TCC denies to a launchd job, and `check-laptop` fails if they hold a file (F-LAPTOP-TCC). There is nothing to re-grant after an upgrade. **If a job ever needs Full Disk Access:** System Settings › Privacy & Security › Full Disk Access, re-checked after every major upgrade (a major upgrade can reset it) | backup.sh, check-laptop |
| **a pending prompt hangs a job** | the jobs (the backup, the model supervisor) run as LaunchDaemons as `seed`, without a login session. sudo is NOPASSWD and limited to four named commands, so nothing waits for a password | the plists, `sudo -n -l` |
| **Spotlight and the media daemons eat a server** | **Spotlight indexing is off** for / and the Data volume (the owner, 20260928). It had been indexing the model directory (about 45 GB) inside macOS's 16 GiB | `mdutil -s /` |
| **CLI auth is per machine** | the tool logins on compute are `seed`'s own, separate from the agent box's. A reinstall of compute needs them made again | none |
| **APFS is case-insensitive: verify copies by count** | model and runtime files are checked by sha256 (install.sh), which is stronger than a count. The repo clone has 318 files on disk, equal to the 318 tracked (2f04b02), and the repo has no paths that differ only by case (403 files) | `git ls-files`, `sort -f \| uniq -di` |

## For an administrator (the owner's account on compute): done 20260928

The owner set both as `admin` on 20260928. Checked as `seed` at 14:44:14Z: Spotlight indexing disabled on
/ and /System/Volumes/Data; `com.apple.commerce AutoUpdate` 0; macOS auto-install 0
(evidence/20260928-compute-admin-settings.txt). The steps, for a reinstall:

1. **Spotlight off** for the whole Mac. Either run `sudo mdutil -a -i off` in Terminal, or use
   System Settings › Spotlight › Search Privacy… › add Macintosh HD. To verify, `mdutil -s /` says
   "Indexing disabled."
2. **App Store app updates off.** System Settings › General › Software Update › Automatic updates
   (ⓘ) › "Install application updates from the App Store" off. That's
   `com.apple.commerce AutoUpdate` 0. It would otherwise update Xcode and the like in the
   background, and some updates quit running apps.

Leave "Install macOS updates" off (it is) and "Install Security Responses and system files" on.
