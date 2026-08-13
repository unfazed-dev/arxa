# Clip sweep — ScreenRecording_08-13-2026 08-24-56_1.MP4

Source: `/Users/unfazed-mac/Downloads/ScreenRecording_08-13-2026 08-24-56_1.MP4`
(1180×2556 @ 60fps, 38.69s, DEBUG build). Swept at 2fps contact sheets + full-res
frames at defect timestamps. User verdict driving this sweep: "just tested and
still the same."

## What is cured (do not reopen)

- Theme-flip lag (B1/B2 saga, `native-glass-theme-lag-measured.md` §1–24):
  flips at ~4s (light→dark) and ~7s (dark→auto/light) land within 1–2 contact
  frames across cards, background, chrome. No multi-second laggards observed.
- Dark-mode Home tab pill: looked smeared at thumbnail scale; full-res frame at
  t=4.6s shows a correct glass pill with legible purple icon+label. Not a defect
  (minor contrast question at most).

## Surviving defects (confirmed at full res)

### A — Label drops + stale white slab around native controls (Search tab)
Evidence t≈19–29s, full-res frame t=22.6s:
- Inside the RADIUS card, the PRICE RANGE section label region between the two
  sliders is **blank** (only a stray sub-glyph artifact renders); at other
  offsets it renders as "GE" (right edge of the label only).
- Below the card, a **white rounded slab** floats where section content should
  be, and both switch rows render with **no labels** ("Open now" text absent;
  it renders correctly at a different scroll offset, t≈24.4s — so the row is
  built, its text is being occluded/dropped, not missing).
- Signature matches the recorded class: Flutter-drawn text adjacent to platform
  views (CNSlider/CNSwitch) sliced into overlay textures / occluded by a stale
  texture during scroll (see memory: BackdropFilter+platform views, flutter#175048;
  "white rail-pane slab" overlay-texture leak).

### B — Profile toolbar pills degrade with scroll offset
Evidence t≈14–21s:
- Same toolbar renders three ways depending on scroll position: full labeled
  pills (Share/Edit/Delete, t≈15.9s), icon-only share pill + bare unlabeled
  edit/delete glyphs (t≈19.5–21s), and mid-scroll states with clipped labels
  ("…e", ":dit") and overlapping pill backgrounds (t≈14.5s).
- Reads as tier/overlay instability across the scroll-demotion boundary, not a
  static styling bug: all three states come from the same widgets.

### C — Sliding tab-bar lens carries duplicated content (t=8.6s full res)
- During Home→Search pill slide, the glass lens shows a duplicated/warped Home
  icon and fragments of both labels ("me", warped magnifier over "S…rch").
- Needs judgment vs native reference: iOS 26 lens refraction is real, but a
  duplicated icon trailing outside the pill suggests our replay/settle or
  overlay texture contributes. Compare against a native UITabBar slide.

## Not defects / by design
- Glass CTA keeps its lavender tint in dark mode (tinted-in-scroll style per
  `docs/liquid-glass-allowlist.md`).

## Repro pointers
Contact sheets and full-res crops (volatile): `/private/tmp/clip-0813/`
(`sheet_01..13.png`, `ev_*.png`, `c_*.png`). Regenerate from the MP4 with
`ffmpeg -ss <t> -frames:v 1` at the timestamps above.
