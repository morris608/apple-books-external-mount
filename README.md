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
| LaunchAgent | Installed (`com.davidmorris.apple-books-external-mount`) — runs `bin/abe-launcher`; needs Full Disk Access ([RUNBOOK](docs/RUNBOOK.md#launchagent-needs-full-disk-access-2026-08-07-incident)) |
| Reclaim ~331 GB | Pending aside delete after soak |

## Commands

**Eject (recommended):** double-click **`Eject Books Drive`** on the Desktop (Plate SwiftUI window — 3s cancel, then eject). Do not use Finder’s ⏏ on `25External`.

Rebuild after UI changes: `./apps/EjectBooksDriveUI/build.sh`  
Design system: [docs/DESIGN.md](docs/DESIGN.md) · [docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md)

```bash
cd ~/GitHub/apple-books-external-mount
./scripts/apple-books-external-mount.sh status
./scripts/apple-books-external-mount.sh mount
./scripts/apple-books-external-mount.sh unmount   # keep drive plugged
./scripts/apple-books-external-mount.sh eject     # then unplug when Finder clears
./scripts/apple-books-external-mount.sh restore-catalog   # Books shows only cloud books / "No Books"
./scripts/apple-books-external-mount.sh backup-catalog
```

**Never open Books while the drive is unplugged** — Books prunes its catalog
without the media. The agent quits it if you do, and heals the catalog from
`BooksSafety/catalog/latest` on the next mount ([RUNBOOK](docs/RUNBOOK.md#catalog-protection-added-2026-09-09)).

## Docs

- [docs/RUNBOOK.md](docs/RUNBOOK.md) — daily ops, eject, soak criteria
- [docs/MIGRATION.md](docs/MIGRATION.md) — new Mac
- [USER-STORY.md](USER-STORY.md) — goals / acceptance

## Do not delete yet

- `Audiobooks.internal-aside`
- `/Volumes/25External/ibooks`
- `/Volumes/25External/BooksSafety/`
