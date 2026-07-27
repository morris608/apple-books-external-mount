# Books library relocation

Mount Apple Books audiobook media from external storage at the container path so Books keeps full organization, covers (when mounted), playback, and Finder→iPhone sync.

**Architecture:** APFS sparsebundle on `25External` mounted at  
`~/Library/Containers/com.apple.BKAgentService/Data/Documents/ibooks/Books/Audiobooks`  
(not symlinks — sandbox blocks those).

## Status

| Step | State |
|---|---|
| Phase 0 proofs | Done — see [docs/RUNBOOK.md](docs/RUNBOOK.md) |
| Verified safety copy | `/Volumes/25External/BooksSafety/2026-07-26T235612/` |
| Populated media image | `.../BooksSafety/phase0b-populated.sparsebundle` |
| Internal aside (rollback) | `Audiobooks.internal-aside` — **keep until soak + 2nd backup** |
| Legacy `25External/ibooks` | Keep until production multiply verified |
| LaunchAgent | Installed (`com.davidmorris.books-media`) |
| Reclaim ~331 GB | Pending aside delete after soak |

## Commands

**Eject (recommended):** double-click **`Eject Books Drive.command`** on the Desktop (opens Terminal with progress). Do not use Finder’s ⏏ on `25External`.

```bash
cd ~/GitHub/apple-books-external-mount
./scripts/books-media.sh status
./scripts/books-media.sh mount
./scripts/books-media.sh unmount   # keep drive plugged
./scripts/books-media.sh eject     # then unplug when Finder clears
```

## Docs

- [docs/RUNBOOK.md](docs/RUNBOOK.md) — daily ops, eject, soak criteria
- [docs/MIGRATION.md](docs/MIGRATION.md) — new Mac
- [USER-STORY.md](USER-STORY.md) — goals / acceptance

## Do not delete yet

- `Audiobooks.internal-aside`
- `/Volumes/25External/ibooks`
- `/Volumes/25External/BooksSafety/`
