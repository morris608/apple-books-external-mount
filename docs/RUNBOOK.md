# BooksMedia runbook

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

**Desktop:** double-click **`Eject Books Drive.command`** (opens Terminal with progress).  
Do **not** use the old AppleScript `.app` if it’s still around — it could hang silently.

Equivalent terminal:

```bash
~/GitHub/apple-books-external-mount/scripts/books-media.sh eject
```

If Time Machine shows a **spinner** next to it in Finder, eject will stop that backup first; wait for the Terminal message **SAFE TO UNPLUG**.

`Phase0bPop` should stay hidden from the sidebar (`nobrowse`). If it appears, ignore its eject button — use **Eject Books Drive.command** only.

## Expected behavior

- **Drive plugged + mounted:** Books looks normal (covers, play, Finder→iPhone).
- **Drive safely ejected:** titles/collections remain; most covers blank until remount. Phone keeps already-synced books.
- **Imports while unmounted:** land in the empty local `Audiobooks` dir; next `mount`/`ensure` sweeps them onto the image (tag new `.m4b` with `AtomicParsley --stik Audiobook` so Finder sync lists them).

## Safe eject (always)

1. Quit any Finder iPhone sync.
2. `./scripts/books-media.sh eject`
3. Wait until `25External` disappears from Finder / `/Volumes`.
4. Unplug.

Do **not** yank the cable while the sparsebundle is attached.

## After a reboot

1. Plug in `25External` (and unlock/mount if needed).
2. LaunchAgent should remount within ~30s (`./scripts/books-media.sh status` to confirm).
3. Or run `./scripts/books-media.sh mount` manually.

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

`~/Library/Logs/books-media/`
