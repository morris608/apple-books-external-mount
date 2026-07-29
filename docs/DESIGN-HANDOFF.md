# Handoff — Eject Books Drive redesign

Everything Cursor needs, and nothing it has to ask about. Drop these into the repo at the paths
shown (they already match the repo's layout).

## Start here

| File | Purpose |
|---|---|
| `CURSOR-BRIEF.md` | the prompt to give Cursor — reading order, the five passes, the rules |
| `docs/DESIGN.md` | the visual system: color, type, the figure rule, the track, motion, geometry, voice |
| `docs/IMPLEMENTATION.md` | build spec: state machine, every string, log rules, actions, `--preview`, accessibility, acceptance checklist |
| `docs/tokens.json` | the same numbers, machine-readable |

## Code

| File | Purpose |
|---|---|
| `apps/EjectBooksDriveUI/DesignSystem.swift` | `Palette` (light/dark), fonts, tracking, metrics. Generated from tokens.json |
| `apps/EjectBooksDriveUI/EjectWindowView.swift` | the entire window, all six states, plus `StepTrack`, `ActionButton`, fixtures and SwiftUI previews |

The only code Cursor writes is the adapter from the existing `EjectController` (and its log stream)
to `EjectPresentation`, plus the `--preview=<state>` flag. Everything visual is already built.

## Icon

| File | Purpose |
|---|---|
| `apps/EjectBooksDriveUI/icon/icon-1024.svg` | vector source, the only file to edit |
| `apps/EjectBooksDriveUI/icon/icon-1024.png` | 1024 sRGB master |
| `apps/EjectBooksDriveUI/icon/png/*.png` | the ten iconset masters, 16 → 1024 (`-2x` = `@2x`) |
| `apps/EjectBooksDriveUI/icon/make-icns.sh` | builds `EjectBooksDrive.icns` with `iconutil` |
| `apps/EjectBooksDriveUI/icon/README.md` | install steps and what to check before committing |

```bash
chmod +x apps/EjectBooksDriveUI/icon/make-icns.sh
apps/EjectBooksDriveUI/icon/make-icns.sh
cp apps/EjectBooksDriveUI/icon/EjectBooksDrive.icns apps/EjectBooksDrive.icns
./apps/EjectBooksDriveUI/build.sh
```

## Decisions already made (don't relitigate)

- **Plate** composition: no panels, wells, cards, filled buttons or progress bar.
- **Light is default**, dark is the same view with a second palette; follow system appearance. Dark
  carries a 6px state cap rule, light carries none.
- **Amber = working, blue = held, green = safe, red = fault.** One state color on screen at a time.
  A hold is never red.
- **The figure**: bare integer = countdown to auto-start; colon form = elapsed. Same slot always.
- **The track**: four segments (locate, flush, stop TM, detach), mark drifts only inside the live
  one, parks when held, four solid bars on success. Never a percentage.
- **Three motions** only, all gated on Reduce Motion; nothing moves after a result lands.
- **Icon**: open book in headphones, amber earcups, amber eject mark top-right, group at 112%.
- Behavior unchanged: auto-start on launch (with a 3-second cancel window), `--preview` skips the
  eject, Open Log / Done.

## Definition of done

`docs/IMPLEMENTATION.md` §9 — twelve checkboxes. The important two: the window must not reflow
between any two states, and no animation may run after a result lands.
