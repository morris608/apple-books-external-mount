# Eject Books Drive — design system

Single source of truth for the visual system. Anything not written here is not part of the design;
if a decision is missing, follow the nearest rule below rather than inventing a new one.

Direction: **the Plate** — no panels, no wells, no cards, no progress bar. Type, one figure, one
four-segment track and one column of log. State is carried by color and by a 6px cap rule (dark
only), so the window changes register before a word is read. The window never reflows between
states: every element sits in the same slot in all six states.

---

## 1. Color

Light ground is the default; dark is the same view with the second column of values. Follow the
system appearance — never a manual toggle.

| Role | Light | Dark |
|---|---|---|
| ground | `#F1F0EC` | `#121314` |
| display ink | `#16181A` | `#F0EFEC` |
| body ink | `#5C605F` | `#90959A` |
| mono (log, eyebrow, caption) | `#666A61` | `#8A9095` |
| mono label (ACTIVITY) | `#676B62` | `#7A7F84` |
| rule / hairline | `#D6D4CC` | `#2A2D2F` |
| track empty | `#E4DFD2` | `#2A2D2F` |
| dim figure (idle 0:00) | `#85837B` | `#6E7276` |
| disabled action | `#B4B1A9` | `#4C5054` |
| strong action rule | `#16181A` | `#6E7276` |
| dotted leader | `#D2CFC5` | `#2E3134` |
| window border | `#D6D4CC` | `#000000` |
| traffic lights | `#C9C6BD` / `#DEDBD3` | `#3A3D40` / `#26292B` |

### State colors

| State | Light | Dark | Means |
|---|---|---|---|
| working | `#96631A` | `#E8A33D` | the machine is doing something |
| held | `#256B86` | `#6FC0E0` | it needs you |
| done | `#1E7A50` | `#7EE0AE` | safe to unplug |
| fault | `#8E3B32` | `#C4695E` | nothing changed, something broke |
| neutral (idle cap rule) | — | `#3A3D40` | armed / waiting |

Rules:
- One state color on screen at a time. Never amber and blue together.
- Amber is also the **primary action** color in idle/armed/failed (the action starts work).
- Red is reserved for fault. A hold is never red.
- Light ground has **no cap rule**; the eyebrow, figure and colored action carry the state.
- Dark ground carries a **6px cap rule** in the state color across the top of the window.
- Light state colors are the deep cuts so 10px mono clears 4.5:1 on bone; dark uses the light cuts.

## 2. Type

| Role | Design font | Ship font | Spec |
|---|---|---|---|
| Display | Archivo 700 | SF Pro Display, bold | 44pt; **52pt in the succeeded state only**; leading 0.95 (0.92 at 52); tracking −3.5% (−4% at 52) |
| Body | IBM Plex Sans 400 | SF Pro Text, regular | 14pt / 1.45; measure capped at 32 characters |
| Instrument (eyebrow, caption, ACTIVITY) | IBM Plex Mono 400/500 | SF Mono, regular | 9.5–10pt, uppercase, tracking .18–.24em |
| Figure | Archivo 700 | SF Pro Display, bold | 30pt, tabular |
| Log | IBM Plex Mono 400 | SF Mono, regular | 10pt / 2.0, tabular |
| Action | Archivo 600 | SF Pro Text, semibold | 10.5pt, uppercase, tracking .16em, flush left |

- Display never exceeds two lines and is hard-broken by the designer, not wrapped.
- Every number is tabular. Timestamps sit one tone dimmer than their message.
- Actions are text labels over a 1px top rule — no filled buttons anywhere in the app.

## 3. The figure (the one ambiguity, resolved)

The 30pt figure slot has two meanings and they are distinguished by **format**:

- **Bare integer** — a countdown to something about to happen (`3 → 2 → 1` before auto-start).
  Rendered in display ink, caption reads `SECONDS TO CANCEL`.
- **Colon form** (`0:08`) — elapsed time, counting up in the state color; frozen at the total once
  the result lands. Caption reads the step position.

Idle sits at a dim `0:00`. Same slot, same baseline in all states — the window must not reflow.

## 4. The track

Four equal segments, one per step of the eject: locate → flush → stop Time Machine → detach & eject.

- 294pt total, 3pt tall, 6pt gaps → segment width 69pt. Same measure as the body copy.
- Completed segments: state color. Unreached: track-empty.
- The live segment holds a 24pt mark that drifts 45pt inside it, 2.4s ease-in-out, autoreversing.
- **Held**: the mark parks at 22pt from the segment's left edge and stops moving. The stillness is
  the signal.
- **Failed**: reached segments in fault color, unreached left empty. No color past where it got.
- **Succeeded**: four solid bars, nothing moving.
- Never interpolate a percentage. The app does not know how long Time Machine will take.

## 5. Motion — three moves, no more

1. **Settle** — content rises 6pt, 300ms, `cubic-bezier(.2,.7,.3,1)`, once, when a result lands.
2. **Wait** — the track mark drifts; the log caret blinks at 1.1s. Nothing else moves, ever.
3. **Stop** — every animation ends the instant the result lands.

Reduce Motion: mark parks at the live segment's midpoint, no caret blink, settle becomes a cut.
Behavior and information are identical.

## 6. Geometry

- Window 560pt wide, height follows content. Corner radius 8 on the window; **0 on everything
  inside it** except the 9pt radius on the icon's eject bar.
- Body padding: 6pt top / 30pt sides / 28pt bottom. Titlebar 30pt (dark, under the cap rule) or
  34pt (light).
- Two columns: 294pt content + 30pt gap + 176pt log/actions. The log column is always visible.
- Vertical rhythm inside the content column: 14pt between blocks, 9pt between figure and track.
- One elevation: a single soft shadow on the window. No shadows inside it.

## 7. Voice

1. Say what happened to the drive, not what the program did.
2. In every non-success state, say whether the drive is safe to leave connected. It always is.
3. The fix is the primary action's label, not a sentence in the body ("Quit Music & retry").
4. Two-line display, plain words, full stops. No exclamation marks, no emoji, no jargon in the
   display or body — jargon belongs in the log.

## 8. Icon

One plate, three forms: a bone open book inside bone headphones with amber earcups, plus a small
amber eject mark in the top-right corner. Group is scaled to 112% about (512, 544) in the 1024
canvas. No text, no badge circle, no gradients, no photographic detail. Palette is exactly the
window's: `#121314` plate, `#F1F0EC` forms, `#E8A33D` accents.

Master art and the generated iconset live in `apps/EjectBooksDriveUI/icon/`.

## 9. Don't

- No cards, wells, panels, filled buttons, or a fifth color.
- No progress percentage, spinner, or indeterminate bar.
- No motion after the result lands.
- No red for a hold; no dark-only design; no manual appearance switch.
- Nothing new in the top-right corner of the window — that space belongs to the icon's language.
