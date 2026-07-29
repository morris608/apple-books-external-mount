# Cursor brief — implement the Eject Books Drive redesign

Everything needed is in this repo. Do not redesign; implement.

**Read in this order**
1. `docs/DESIGN.md` — the visual system (color, type, figure rule, track, motion, geometry, voice).
2. `docs/IMPLEMENTATION.md` — the build spec: state machine, every string, log rules, actions,
   `--preview`, accessibility, icon install, acceptance checklist.
3. `docs/tokens.json` — the same values, machine-readable.
4. `apps/EjectBooksDriveUI/DesignSystem.swift` and `EjectWindowView.swift` — provided
   implementation of the whole window with previews for all six states.

**Your work, in passes. Rebuild and visually verify after each one.**

1. **Wire it up.** Add the provided Swift files to the target. Write the adapter that maps the
   existing `EjectController` state and log stream onto `EjectPresentation` (§1 and §4 of the
   implementation spec). Keep `EjectController` and `scripts/apple-books-external-mount.sh`
   behaviour exactly as they are: auto-start on launch, `--preview` skips the eject, Open Log and
   Done both work.
2. **States.** Drive all six states from real script output. Add `--preview=<state>` per §6 and
   screenshot each one.
3. **Motion and accessibility.** Three motions only, all gated on Reduce Motion; VoiceOver labels
   and the result announcement per §7.
4. **Icon.** Run `apps/EjectBooksDriveUI/icon/make-icns.sh`, install to
   `apps/EjectBooksDrive.icns` and into the app bundle, rebuild, verify at 16pt on a light and a
   dark desktop.
5. **Acceptance.** Walk §9 line by line and fix anything that fails.

**Rules**
- Take every color, size, spacing and string from the docs. Invent nothing.
- No new dependencies, no webview, no third-party fonts — the ship fonts are SF Pro and SF Mono.
- Don't rename the product, the scripts, or the log format.
- If a doc contradicts itself, `docs/DESIGN.md` wins for looks and
  `docs/IMPLEMENTATION.md` wins for behaviour. If both are silent, pick the option that keeps the
  window from reflowing and note it in the commit message.

**Commit messages** — one per pass, in the form: what changed, why, and what a reviewer should look
at (e.g. "run `--preview=partial`; the mark should be parked, not drifting").
