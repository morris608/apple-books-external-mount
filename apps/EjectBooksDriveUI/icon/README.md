# Icon — Eject Books Drive

**Art:** a bone open book inside bone headphones with amber earcups, plus a small amber eject mark
in the top-right corner, on a near-black plate. Group scaled to 112% about (512, 544) in the 1024
canvas. Palette is exactly the window's: plate `#121314`, forms `#F1F0EC`, accent `#E8A33D`.

## Files

| File | What |
|---|---|
| `icon-1024.svg` | vector source — the only file to edit |
| `icon-1024.png` | 1024 sRGB master, transparent outside the plate |
| `png/icon_*.png` | the ten iconset masters (16 → 1024). `-2x` in a name means `@2x` |
| `make-icns.sh` | renames `-2x` → `@2x`, runs `iconutil`, writes `EjectBooksDrive.icns` |

## Install

```bash
cd apps/EjectBooksDriveUI/icon
./make-icns.sh
cp EjectBooksDrive.icns ../../EjectBooksDrive.icns
../build.sh
```

`build.sh` copies it into the bundle as `Contents/Resources/AppIcon.icns`. Confirm with:

```bash
ls -l "apps/Eject Books Drive.app/Contents/Resources/AppIcon.icns"
```

Then clear the icon cache if Finder still shows the old art:

```bash
touch "apps/Eject Books Drive.app" && killall Dock
```

## Check before committing

- Dock size and Finder list view (16pt) on both a light and a dark desktop.
- The book's gutter line vanishing at 16pt is expected and fine.
- The amber corner mark must stay separate from the earcups at every size. If it merges, the group
  scale drifted — reset it to 1.12.
- No text, no badge circle, no gradient, no shadow inside the art.

## Editing

Edit `icon-1024.svg`, then re-export the ten sizes in `png/` at exactly the names listed above and
re-run `make-icns.sh`. Any vector tool works; there is no build step tied to the SVG.
