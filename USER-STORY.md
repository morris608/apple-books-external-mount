# Relocate Apple Books audiobook archive to external storage

**Chosen approach:** Mount external APFS media (sparsebundle on `25External`) at the Books `Audiobooks` container path. Keep full Books UI, collections, and Finder→iPhone when the drive is mounted.

## As a

macOS user with a critically full internal SSD, holding ~331 GB of **imported** audiobooks in Apple Books, who listens on iPhone and plugs the drive in when syncing.

## I want to

1. Keep all ~688 titles visible and organized in Books (collections/series intact).
2. Store media on external storage without unsupported symlinks.
3. Transfer titles to iPhone via Finder when the drive is connected.
4. Automate attach/mount when the drive appears; safe-eject before unplug.
5. Reclaim ~331 GB only after soak + a second physical backup.
6. Keep the process transferrable to a new Mac with the same short username.

## So that

Internal SSD space is freed without losing the library, and day-to-day Books still works when the drive is present.

## Acceptance criteria

### Must

- [x] Verified external copy of all audiobook files exists
- [x] Whole-root mount plays and shows covers when media present
- [x] Catalog persists when media absent (titles/collections; covers mostly blank)
- [x] Covers restore when media remounted (no re-import)
- [x] Finder→iPhone sync works from mounted media (Agent Zero #1 verified)
- [x] LaunchAgent can mount without interactive admin each attach
- [ ] Aside deleted only after soak + restore-tested second backup on another device
- [ ] Legacy `/Volumes/25External/ibooks` deleted only after multiple production checks

### Won’t

- Symlink-based offload (sandbox failure proven)
- Claiming Apple-supported relocation
- Treating Time Machine on the same enclosure as an independent second copy
