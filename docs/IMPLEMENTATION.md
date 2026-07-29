# Implementation spec — Eject Books Drive (SwiftUI, macOS 14+)

Written to be built without further design input. Read `docs/DESIGN.md` first for the why; this
file is the what. Files marked *provided* already exist in the repo.

- *provided* `apps/EjectBooksDriveUI/DesignSystem.swift` — palette, type, and the shared parts.
- *provided* `apps/EjectBooksDriveUI/EjectWindowView.swift` — the whole window, all six states,
  driven by one value type (`EjectPresentation`). Includes SwiftUI previews for every state.
- *provided* `apps/EjectBooksDriveUI/icon/` — 1024 master PNG, the full iconset PNG set, the SVG
  source, and `make-icns.sh`.
- **you write** the adapter from the existing `EjectController` to `EjectPresentation`, and the
  wiring in the app entry point.

Do not restyle anything in the provided files. If something doesn't compile against your Swift
version, fix the syntax, not the numbers.

---

## 1. State machine

Six presentation states. The engine (`scripts/apple-books-external-mount.sh eject`) is unchanged.

| # | State | Entered when | Cap rule (dark) | Figure |
|---|---|---|---|---|
| 1 | `armed` | launch, auto-start enabled, countdown running | neutral `#3A3D40` | bare integer 3→1 |
| 2 | `idle` | launch with auto-start disabled (`--no-auto`), or after Cancel | neutral | dim `0:00` |
| 3 | `running` | eject script started | working | elapsed, working color |
| 4 | `succeeded` | script exit 0 and volume gone | done | frozen total |
| 5 | `partial` | script reports a holder / busy but nothing was unmounted | held | frozen total |
| 6 | `failed` | script exit non-zero, no changes made | fault | frozen total |

Transitions: `armed` --(3s elapse or Start now)--> `running`; `armed` --(Cancel/Esc)--> `idle`;
`idle` --(Eject now)--> `running`; `running` --> one of 4/5/6; `partial`/`failed` --(primary)-->
`running`. There is no other path. `--preview` short-circuits: it renders a state without running
the script (see §6).

**Step index** comes from the script's log lines, mapped to the four track segments:

| Segment | Log signal | Caption while live |
|---|---|---|
| 1 locate | mount point resolved / sparsebundle found | `STEP 1 / 4` |
| 2 flush | flushing writes / handles counted | `STEP 2 / 4` |
| 3 stop TM | `tmutil stopbackup` issued, waiting | `STEP 3 / 4` |
| 4 detach | `hdiutil detach` / `diskutil eject` | `STEP 4 / 4` |

If a line can't be classified, keep the current segment. Never skip backwards.

## 2. Copy — every string in the app

Display strings are hard-broken with `\n`. `{holder}` is the blocking process name from the log
(fall back to "Another app" if unknown); `{time}` is `HH:mm`.

| State | Eyebrow | Display | Support | Caption | Secondary | Primary |
|---|---|---|---|---|---|---|
| armed | `AUDIOBOOKS / MOUNTED` | Ejecting\nin a moment. | Starting on its own. Press Cancel if you opened this by mistake — nothing has changed yet. | `SECONDS TO CANCEL` | Cancel ⎋ | Start now ⏎ |
| idle | `AUDIOBOOKS / MOUNTED` | Ready to\neject. | *(replaced by the facts list, see §3)* | `4 STEPS · ABOUT 40S` | Cancel | Eject now ⏎ |
| running | `AUDIOBOOKS / DISK6S2` | Unmounting\nthe library. | Time Machine is stopping first. Hold the cable — up to two minutes. | `STEP n / 4` | Open log | Done *(disabled)* |
| succeeded | `AUDIOBOOKS / DETACHED` | Safe to\nunplug. | Unmounted cleanly. Zero open handles, Time Machine restored. | `4 / 4 COMPLETE` | Open log | Done ⏎ |
| partial | `AUDIOBOOKS / STILL MOUNTED` | One hold.\nYour move. | {holder} still has the drive open. Quit it and retry — the drive is safe where it is. | `HELD AT n / 4` | Open log | Quit {holder} & retry ⏎ |
| failed | `AUDIOBOOKS / UNCHANGED` | Still\nmounted. | Three detach attempts returned EBUSY. Nothing was changed — leave the cable in. | `STOPPED AT n / 4` | Open log | Retry ⏎ |

Notes:
- The volume name in the eyebrow is the real volume name, uppercased; the second half is the state
  word, not a device path, except in `running` where the BSD name is genuinely useful.
- If the failure isn't EBUSY, the support line becomes: "The eject failed: {reason}. Nothing was
  changed — leave the cable in." Keep it one sentence plus the reassurance.
- Never put a process name in the display line; it belongs in the support line and the button.

## 3. Idle facts list

Three rows, mono 10.5pt, dotted leaders, label left / value right, in the support line's slot:

| Label | Value source |
|---|---|
| `volume` | total size + percent used, e.g. `1.82 TB · 61% full` |
| `last write` | mtime of the sparsebundle, humanised: `6 min ago` |
| `time machine` | `idle` / `backing up` from `tmutil status` |

If a value is unavailable, print `unknown` in the mono color — do not hide the row (the layout is
fixed).

## 4. The log column

- Always visible. 176pt wide, top-aligned, mono 10pt / 2.0.
- Shows the **last four** lines; older lines drop off the top. `Open log` reveals the full file.
- Format: `HH:mm:ss message`, timestamp in mono color, message in mono color, and the newest line
  in the state color while running (with the blinking caret appended).
- Truncate a message with a middle ellipsis rather than wrapping — the column never grows.
- The log is streamed from the script's stdout; it is not synthesised from state.

## 5. Actions

- Two actions, stacked bottom-right, each a text label above a 1pt top rule, flush left.
- Primary is the lower one, carries the state/action color and `⏎` (`.keyboardShortcut(.defaultAction)`).
- Secondary is above it, mono-neutral, `⎋` where it maps to Escape (`.cancelAction`).
- Disabled primary (`running`) uses the disabled color, is not focusable, and shows no shortcut hint.
- Full keyboard path: Return fires primary, Escape fires secondary, Tab moves between them.

## 6. `--preview`

Keep the existing flag and extend it: `--preview[=state]` where state ∈
`armed|idle|running|succeeded|partial|failed` (default `running`). It renders that state with the
fixture data used in the SwiftUI previews and never touches the script. This is the visual-check
path — use it after every pass.

## 7. Accessibility

- Dynamic Type on display and body via `.font(.system(size:…, weight:…))` scaled by
  `@ScaledMetric`; the mono instrument line and log clamp at +2 steps so the column can't reflow.
- `@Environment(\.accessibilityReduceMotion)` gates all three motions per `docs/DESIGN.md` §5.
- Body copy contrast is ≥4.5:1 on both grounds; the 9.5–10pt mono tier was specifically tuned for
  this — do not lighten it.
- VoiceOver: the window has one `accessibilityLabel` combining display + support (e.g. "Safe to
  unplug. Unmounted cleanly, zero open handles"), the track is one element labelled
  "Step 3 of 4, stopping Time Machine", and the log is an `accessibilityElement(children: .combine)`
  updated on new lines with `.accessibilityAddTraits(.updatesFrequently)`.
- Announce result transitions with `AXAnnouncement` at `.high` priority — a blind user must not
  have to poll for "safe to unplug".

## 8. Icon install

```bash
cd apps/EjectBooksDriveUI/icon
./make-icns.sh                     # builds EjectBooksDrive.icns from the PNG set
cp EjectBooksDrive.icns ../../EjectBooksDrive.icns
./../build.sh                      # rebuild; build.sh copies it in as AppIcon.icns
```

Verify at Dock size and in Finder's list view (16pt) on both a light and a dark desktop before
committing. If the book's gutter disappears at 16pt that is expected and acceptable; if the amber
corner mark merges with the earcups, something scaled wrong.

## 9. Acceptance checklist

Ship only when every line is true.

- [ ] Window is 560pt wide in all six states and **nothing moves position** between them — check by
      screenshotting two states and diffing element positions.
- [ ] The figure is a bare integer only in `armed`, colon form everywhere else.
- [ ] Track: 4 segments, 69pt each, 6pt gaps, mark drifts only in the live segment.
- [ ] Held parks the mark; failed leaves unreached segments empty; success is four solid bars.
- [ ] Exactly one state color on screen at a time; the primary action is colored in
      armed/idle/failed.
- [ ] Dark shows the 6px cap rule; light shows none.
- [ ] Succeeded display is 52pt, every other display is 44pt.
- [ ] No animation runs after a result lands (verify with Reduce Motion off *and* on).
- [ ] Log column visible in every state, four lines max, newest line tinted while running.
- [ ] Return and Escape both work in every state; no mouse required.
- [ ] `--preview=partial` and `--preview=failed` render without running the eject script.
- [ ] Icon replaced in `apps/EjectBooksDrive.icns` and inside the built `.app`, verified at 16pt.
- [ ] No filled buttons, no cards, no spinner, no percentage, no fifth color anywhere.
