# Clip 08-13 defects A/B/C — synthesis and fix order

Merges `docs/research/clip-0813-fix-research.md` (web) and
`docs/plans/clip-0813-code-scan.md` (source scan). Where they conflict, the
code scan wins on local facts; the research wins on engine/upstream facts.

## Conflicts resolved

1. **Defect C premise.** Research §4 assumed the lens duplicates *Flutter*
   content and proposed an opaque-block probe. Code scan verified from the
   Swift (`UITabBarItem(title:image:selectedImage:)`,
   `CupertinoTabBarPlatformView.swift:186,551,667`) that all tab-bar content is
   native UIKit — nothing Flutter-drawn exists for the lens to duplicate. The
   opaque-block probe is **moot for the tab bar**. Live discriminators: stock
   `UITabBar` reference comparison (research's C-look may be iOS 26 by-design
   refraction) and the `shrinkCentered: false` geometry probe. The research's
   glass-in-glass / `GlassEffectContainer` aggravator note survives as a
   native-side check.
2. **Research fix 1 (demote controls in scroll) is NOT adoptable as written.**
   It contradicts the grilled living rule (`docs/liquid-glass-allowlist.md`:
   controls stay native everywhere; the blanket control demotion shipped and
   was reverted same-day) and this repo has twice killed the correct mechanism
   to protect the defective one. The vendor "DO NOT scroll platform views"
   README rule is real evidence, but the decision needs the A2 probe result
   first — the ghosts/slabs may be keep-alive occlusion, not scrolling-control
   slicing (memory: the 22:26/22:46 "label drops" were mostly hidden-tab
   overlay occlusions).
3. **flutter#175048 memory citation corrected** (closed `r: fixed`, blur-past-
   clip, no text-drop content). Memory file updated 2026-08-13; mechanism
   re-grounded on iOS docs + open #150646.

## Constraints from build provenance (code-scan final report)

- The recorded binary (`build/ios/Debug-iphoneos/Runner.app`, stamped 08-13
  08:22:14, two minutes before the 08:24 recording) already contained every
  08-12 fix: 0.5px `_HiddenTabClipper`, `platformViewSafe: inScrollable`,
  toolbar `preferFlutterTier`, vendor PATCH #5/#7. **All three defects
  survived them — do not re-land any 08-12 fix as a fix for A/B.**
- B is **not a tier flip**: `preferFlutterTier` is an InheritedWidget lookup
  and cannot vary with scroll offset.
- Retracted B claim: the "Show sheet" truncation is the FAB occluding the
  card (right edge measured correct at x=1132), not a rendering defect.
- Note for A2: the `_HiddenTabClipper` deliberately keeps hidden tabs'
  platform views in the native hierarchy, so the "ghosts solved" memory entry
  does not preclude A2 — hidden views still slice the active tab's frame.

## Agreed foundations (both reports)

- Mechanism: one overlay per slice (PR #54010); overlay rects ignore clip
  bounds (#150646, open, present in our 3.44.9/`5a2a6a42cc`); 1px `roundOut`
  overlap (#143420) explains scroll-offset dependence.
- No Impeller escape hatch on iOS; no upstream Cupertino glass work (#170310);
  Flutter upgrade buys nothing; `RepaintBoundary` can't snapshot platform
  views (#163639).

## B full-res frames (extracted 2026-08-13 08:50, step 2 DONE)

Source: `ScreenRecording_08-13-2026 08-24-56_1.MP4` →
`/private/tmp/clip-0813/b_full_14_5.png`, `b_full_15_9.png` (1180x2556).
tmp is session-volatile — re-extract with the same ffmpeg -ss args if needed.

**t≈14.5s (Profile, TOOLBAR mid-viewport):** three toolbar items; the share
button keeps its tinted pill (orig x≈51-297, y≈1773) while edit and delete are
bare glyphs — pill material gone, glyphs intact. This is the second of B's
three states, now confirmed above thumbnail scale. Note the asymmetry within
one toolbar at one scroll offset: same widget, same row, differing outcomes —
consistent with per-slice overlay outcomes, NOT with any whole-toolbar state
flip (confirms scan's "B is not a tier flip").

**t≈15.9s (Profile, showcase cards):** the strongest new evidence.
- A white rectangle at a wrong rect (orig ≈x367-1083, y1239-1587) sits over
  the Maps card region; the "Maps showcase" pill runs full-width beneath it
  and renders in two pieces — dimmer where outside the white rect, normal
  where under it. Same signature as Search's slab: near-opaque fill at a
  stale/mis-bounded rect with content split across the boundary.
- The COMPONENTS card's fill is clipped square at its left edge (orig x≈100)
  instead of rounded — a second mis-bounded fill in the same frame.
- So the slab defect is NOT Search-specific: it reproduces on Profile with
  different content. Whatever mechanism explains A's slab must also explain
  these (strengthens A1/A2 as a shared cause for A and B; both tabs had been
  visited by this point in the clip, so A2 keep-alive remains compatible).

**Retraction check upheld:** at 14.5s the FAB overlaps the next card's row
exactly where the earlier "Show sheet truncation" was read — occlusion, as
the scan measured, not a defect.

## Execution order (probes before edits)

1. ~~A2 fresh-launch probe~~ **DONE 08-13, NEGATIVE** (user-observed on
   device, fresh launch): the FIRST Search scroll was already broken before
   any other tab was visited ⇒ keep-alive platform-view count is NOT the
   driver. Keep-alive stays untouched (`liquid-glass-allowlist.md:101-107`).
   Corroborating census from the same run's log: at first theme flip (~46s),
   ~50 platform views across tabs were resident (CNButton_0..41, search bar,
   sliders, switches, segmented, text fields) — keep-alive is real, just not
   causal for A.
2. ~~Re-extract full-res B frames at t≈14.5s and t≈15.9s~~ **DONE 08-13
   08:50** — see "B full-res frames" above. B is no longer single-frame; the
   slab reproduces on Profile.
3. **C stock-UITabBar reference comparison** (parallel with 1-2); then the
   `shrinkCentered` scratch probe if still ambiguous.
4. Code edits only after probe results: ~~A1 label reorder~~ **LANDED 08-13**
   (`showcase_search_filter_card_widget.dart` — price label moved below the
   range slider so the two platform views are adjacent; spacer paints nothing
   so no slice between them; showcase suite 128/128). ONE variable at a time:
   B2 `cacheExtent` and A3 shadow drop are NOT landed — device-verify A1 on
   Search's first scroll before touching them, so attribution stays clean.
5. If A2 is negative AND A1 reorder fails: only then reopen the
   allowlist-vs-vendor-README control question, with the probe trail as the
   external evidence the grill requires.

## Consult trail

No API key on this machine; decision-skip recorded via
`consult.sh gate decision --skip` (session `cwd-32d9928e376a`).
