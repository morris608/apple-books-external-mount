# Eject Books Drive (SwiftUI — Plate)

Implements `docs/DESIGN.md` + `docs/IMPLEMENTATION.md`.

```bash
./apps/EjectBooksDriveUI/build.sh
./apps/EjectBooksDriveUI/icon/make-icns.sh   # after icon art changes
```

Preview without ejecting (fixture data):

```bash
…/Eject\ Books\ Drive.app/Contents/MacOS/EjectBooksDrive --preview=armed
…/Eject\ Books\ Drive.app/Contents/MacOS/EjectBooksDrive --preview=idle
…/Eject\ Books\ Drive.app/Contents/MacOS/EjectBooksDrive --preview=running
…/Eject\ Books\ Drive.app/Contents/MacOS/EjectBooksDrive --preview=succeeded
…/Eject\ Books\ Drive.app/Contents/MacOS/EjectBooksDrive --preview=partial
…/Eject\ Books\ Drive.app/Contents/MacOS/EjectBooksDrive --preview=failed
```

`--no-auto` skips the 3s armed countdown and opens idle.

The app must live at `apps/Eject Books Drive.app` inside this repo so it can find `scripts/apple-books-external-mount.sh`.
