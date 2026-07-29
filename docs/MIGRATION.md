# New Mac / migration

## Same short username (preferred)

Books stores absolute paths under `/Users/<shortname>/...`. Keep the same account short name.

1. Migration Assistant (or restore user home).
2. Clone this repo to `~/GitHub/apple-books-external-mount` (or update paths in the LaunchAgent plist).
3. Plug in `25External` with `BooksSafety/phase0b-populated.sparsebundle` (or successor image).
4. Confirm `config/apple-books-external-mount.env` UUIDs/paths still match (`diskutil info /Volumes/25External`).
5. Ensure `Audiobooks.internal-aside` exists **or** you have already deleted it after soak — if aside is gone, create an empty aside marker only if you still want the agent’s cutover guard; otherwise temporarily adjust the script.
6. Install LaunchAgent:

```bash
cp launchd/com.davidmorris.apple-books-external-mount.plist ~/Library/LaunchAgents/
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.davidmorris.apple-books-external-mount.plist
```

7. `./scripts/apple-books-external-mount.sh mount` and verify Books + one Finder→iPhone sync.

## Different short username

Stop. Paths in `BKLibrary` / `Books.plist` will not match. Options: create a user with the old short name, or plan a catalog rebuild from the safety copy (manual re-import; collections from exported metadata only).

## Drive failure

1. Restore `phase0b-populated.sparsebundle` (or Audiobooks tree) from the **second** backup device.
2. Place it at the configured `ABE_IMAGE` path (or update config).
3. `./scripts/apple-books-external-mount.sh mount`.

Legacy `/Volumes/25External/ibooks` is a last-resort incomplete tree — prefer BooksSafety dated copy + sparsebundle.
