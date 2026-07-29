# Design brief for Claude Code (Designer) — apple-books-external-mount

Paste the **Prompt to run** section into Claude Code after enabling `frontend-design` (and ideally a macOS app-design skill if available). Attach a screenshot of the current window + `apps/EjectBooksDrive.icns` (or the PNG preview).

---

## Prompt to run

```text
You are designing the visual system for a native macOS utility in this repo:

  ~/GitHub/apple-books-external-mount

Product purpose
- One-job Mac utility: safely eject an external drive that holds Apple Books audiobook media (sparsebundle mounted at the Books Audiobooks container path).
- User listens on iPhone; drive is occasional. Wrong eject = risk. The UI must feel calm, precise, and trustworthy — not playful, not “AI SaaS dashboard.”
- Audience: one power user (me) + possible future public GitHub users who clone the tooling.

What already exists (improve; don’t throw away architecture)
- SwiftUI app: apps/EjectBooksDriveUI/ → builds into apps/Eject Books Drive.app via ./apps/EjectBooksDriveUI/build.sh
- States: idle → running → succeeded | partial | failed
- Live activity log streamed from scripts/apple-books-external-mount.sh eject
- Current look: cool mist / viridian palette, Avenir Next + New York serif title, indeterminate progress, dark log well
- Current Dock icon: ornate navy book + flat red eject badge on blue rounded square (apps/EjectBooksDrive.icns) — functional but mismatched (skeuomorphic book vs flat badge; gold/ornate vs the cooler UI)

Your job (in this order — do NOT do everything in one undifferentiated dump)
1) Design system first (write a short DESIGN.md in the repo): aesthetic direction, type roles, color roles (CSS-variable-style tokens even though this is SwiftUI), motion philosophy, iconography rules, do/don’t.
2) Redesign the macOS app icon to HIG-quality (single coherent metaphor, reads at 16–128px, no tiny detail, no emoji, no text in icon). Deliver master 1024 PNG + iconset/icns wired into the app.
3) Redesign the eject progress window to match that system. Keep behavior: auto-start eject on launch, --preview skips eject, Open Log / Done.
4) Rebuild with build.sh. Run --preview for visual check. Iterate ONE dimension per pass (type → color → layout → motion → icon), screenshot/verify each time.

Aesthetic direction (commit to ONE; refine, don’t hedge)
- Recommended: “instrument panel for a library” — daylight cool mist, ink typography, one viridian signal color, restrained motion. Feels like a precise Mac utility adjacent to Books, not a consumer ebook storefront.
- Alternate if you reject that: “quiet archival” — warmer paper fiber (NOT generic cream+#terracotta AI cliché), graphite ink, single copper accent. Only pick this if you can make it non-generic.
- Forbidden aesthetics: purple-on-white / purple-indigo gradients; generic Inter/Roboto/system-UI stacks as the hero voice; dark-mode-by-default chrome; glow/neon; pill soup; multi-layer fancy shadows; emoji; dashboard cards cluttering a one-job window; Liquid Glass stacked on glass for no reason.

macOS icon constraints (hard)
- Follow Apple HIG app icon ideas: one clear object/metaphor; simplified shapes; strong silhouette; limited palette; consistent lighting; works on light and dark desktops.
- Prefer a unified metaphor for “external library media leaving safely” — e.g. drive + book glyph fused, or an eject chevron integrated into a book/drive form — NOT a realistic ornate book stickered with a unrelated red SF Symbol circle.
- No readable text in the icon. No photo-real leather/gold filigree at small sizes.
- Produce: 1024×1024 master (sRGB, transparency as needed), then iconutil iconset with standard macOS sizes, install as apps/EjectBooksDrive.icns and AppIcon.icns inside the .app; rebuild.

Window / UI constraints (hard)
- Single composition, one job. First view: product name as a clear brand signal, one status headline, short supporting line, progress, activity, primary action.
- Native SwiftUI on macOS 14+; no webview. Prefer system materials only if they serve hierarchy — don’t pastiche iOS.
- Must remain usable while eject runs 10s–2min (Time Machine stop). Progress + log must stay readable; success state must scream “safe to unplug.”
- Partial state (disk busy / TM) must feel different from success and failure without alarmist red-only UI.
- Accessibility: Dynamic Type where practical, contrast ≥ WCAG-ish for body text, Reduce Motion respected (disable ambient pulse / indeterminate flourish).
- Keep wiring: EjectController + apple-books-external-mount.sh; don’t rename the product away from “Eject Books Drive” without asking.

Motion philosophy
- 2–3 intentional motions max: enter, progress, result settle.
- Fast, confident, quiet. No bounce-spam. No continuous decorative animation after success.

Deliverables
- docs/DESIGN.md (system)
- Updated SwiftUI sources + rebuild
- New icns + source master PNG under apps/EjectBooksDriveUI/icon/
- Brief before/after notes in the PR/commit message style

Success criteria
- Icon recognizable at Dock size without reading “book + eject badge”
- Window feels like the same product as the icon
- Someone anxious about unplugging feels guided, not entertained
- No generic AI-dashboard look

Start by proposing the design system in DESIGN.md and 2 icon metaphor options (with a recommendation). Wait for a quick OK only if metaphors diverge wildly; otherwise proceed through icon → window → rebuild → preview.
```

---

## Context for you (David) — how to get better results

Prompting pattern that works well with Claude’s frontend-design skill ([Anthropic frontend design plugin](https://claude.com/plugins/frontend-design), [prompting guidance](https://www.aidesigner.ai/blog/claude-code-frontend-design)):

1. **Direction over pixels** — purpose, tone, color *family*, type *roles*, motion *philosophy*. Avoid dumping hex grids up front.
2. **Layered iteration** — system → icon → window → one polish pass at a time.
3. **Attach references** — current window screenshot + current icns. Vision beats paragraph descriptions.
4. **Enable skills** — `frontend-design`; if available also macOS app-design / icon skills so it respects HIG and Dock legibility.
5. **Verify visually** — force `--preview` + screenshot after each pass.

### Optional one-liners if the first pass is off

- “Icon: simplify to one silhouette; remove the red badge sticker.”
- “Type: stronger display/body contrast; eyebrow can stay small.”
- “Success state: more weight on ‘Safe to unplug,’ less on the log.”
- “Kill ambient animation after completion.”
- “Align icon palette to the window’s viridian/ink system.”

### Repo paths the designer must touch

| Piece | Path |
|---|---|
| UI sources | `apps/EjectBooksDriveUI/*.swift` |
| Build | `apps/EjectBooksDriveUI/build.sh` |
| Icon | `apps/EjectBooksDrive.icns` → also `…/Eject Books Drive.app/Contents/Resources/AppIcon.icns` |
| Eject engine (don’t redesign) | `scripts/apple-books-external-mount.sh` |
