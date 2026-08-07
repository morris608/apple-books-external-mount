# apple-books-external-mount runbook

Serve Apple Books audiobooks from an external sparsebundle mounted at the Books container path.

## Current setup (this Mac)

| Item | Value |
|---|---|
| External volume | `/Volumes/25External` UUID `EB22CF2C-723B-4305-942D-8476A3EB5035` |
| Media image | `/Volumes/25External/BooksSafety/phase0b-populated.sparsebundle` |
| Volume name inside image | `Phase0bPop` |
| Mount point | `~/Library/Containers/com.apple.BKAgentService/Data/Documents/ibooks/Books/Audiobooks` |
| Internal rollback copy | `.../Audiobooks.internal-aside` (keep until soak + second backup) |
| Verified safety copy | `/Volumes/25External/BooksSafety/2026-07-26T235612/` |
| Legacy tree (do not delete yet) | `/Volumes/25External/ibooks` |

## Daily eject (do this — not Finder’s ⏏)

Finder’s eject button next to **25External** does **not** run Books cleanup first. Use:

**Desktop:** double-click **`Eject Books Drive`** (Plate UI: 3s cancel → eject, activity log, safe-to-unplug).  
Rebuild: `./apps/EjectBooksDriveUI/build.sh`. Visual check: `--preview=succeeded` / `--preview=partial`.

Equivalent terminal:

```bash
~/GitHub/apple-books-external-mount/scripts/apple-books-external-mount.sh eject
```

If Time Machine shows a **spinner** next to it in Finder, eject will stop that backup first; wait for the Terminal message **SAFE TO UNPLUG**.

`Phase0bPop` should stay hidden from the sidebar (`nobrowse`). If it appears, ignore its eject button — use **Eject Books Drive.command** only.

## Expected behavior

- **Drive plugged + mounted:** Books looks normal (covers, play, Finder→iPhone).
- **Drive safely ejected:** titles/collections remain; most covers blank until remount. Phone keeps already-synced books.
- **Imports while unmounted:** land in the empty local `Audiobooks` dir; next `mount`/`ensure` sweeps them onto the image (tag new `.m4b` with `AtomicParsley --stik Audiobook` so Finder sync lists them).

## Safe eject (always)

1. Quit any Finder iPhone sync.
2. `./scripts/apple-books-external-mount.sh eject`
3. Wait until `25External` disappears from Finder / `/Volumes`.
4. Unplug.

Do **not** yank the cable while the sparsebundle is attached.

## After a reboot

1. Plug in `25External` (and unlock/mount if needed).
2. LaunchAgent should remount within ~30s (`./scripts/apple-books-external-mount.sh status` to confirm).
3. Or run `./scripts/apple-books-external-mount.sh mount` manually.

## LaunchAgent needs Full Disk Access (2026-08-07 incident)

launchd jobs get no TCC access: run as bare `zsh`, the agent could not `rm`
inside the Books container **or read the sparsebundle on the external drive**
(`mount_apfs: cannot open backing store … Operation not permitted`), so
automatic remount silently failed and the ~30s retry loop force-quit Books on
every attempt, making the app look empty.

Fixes in place:

- The agent now runs via `bin/abe-launcher` (build: `cc -o bin/abe-launcher scripts/abe-launcher.c`).
  **Grant it Full Disk Access**: System Settings → Privacy & Security →
  Full Disk Access → add `bin/abe-launcher`. Re-grant after any rebuild
  (ad-hoc signature). Until granted, automatic remount fails and mounting
  must be done manually from a terminal.
- On any mount failure the script now logs the reason, backs off 900s
  (no more Books kill-loop), and says to run `mount` manually.

## Reading `status` when the agent did the mounting

When the LaunchAgent (not your terminal) performed the mount, terminals may get
"Operation not permitted" reading the mounted Audiobooks path — so
`status` can report `sha1 folders visible: 0` **while everything is healthy**.
Trust these instead: the agent log's last `mounted OK; sha1 folders=688` line,
the Books app showing covers, or a working Finder sync.

## If Finder loses the Podcasts/Audiobooks/Books tabs

Seen 2026-08-07 after the kill-loop incident: the device page showed only
General/Music/Movies/TV/Photos/Files/Info. Those three tabs are served by
per-app daemons, and restarting them (`bookassetd`, `AMPDevicesAgent`,
Finder) was NOT enough — neither was rebooting the iPhone. **Reboot the Mac.**
(Also ruled out: the iPhone's Settings → Apps → Books → iCloud Drive toggle,
which when ON legitimately hides those tabs.)

## Finder sync can wipe the phone while the drive is absent

If the iPhone connects while the Audiobooks mount is down, an automatic
Finder sync sees an **empty** library and removes synced audiobooks from the
phone (happened 2026-08-07 — plugged in to charge with drive unplugged).
In Finder → iPhone → General, **uncheck "Automatically sync when this iPhone
is connected"**. Only sync manually, after `status` shows the mount healthy.

## Cutover notes from Phase 0b

- Symlinks fail (sandbox). Whole-root mount works.
- First cutover may confuse in-progress sync/progress; finished flags survive.
- Prefer cutover when you are between series.

## Before deleting internal aside (~331 GB reclaim)

Only after:
1. Several successful eject/remount/reboot cycles
2. Finder→iPhone syncs from mounted media
3. A **second physical** backup of the media image (Time Machine on the same enclosure does **not** count)
4. `tmutil isexcluded` check if using TM elsewhere

Then: quit Books, confirm mount healthy, delete `Audiobooks.internal-aside`.

## Before deleting legacy `/Volumes/25External/ibooks`

Only after production soak above — multiple independent checks that BooksSafety + mounted image are complete.

## Logs

`~/Library/Logs/apple-books-external-mount/`
