# Showcase-wide liquid-glass law application

Ratified 2026-08-13. Mandate: apply THE liquid-glass law (`docs/liquid-glass-allowlist.md`)
to every showcase view/shell, fanning out subagents. Android/M3E is deferred to a later
session by explicit user instruction.

## Baseline

Compliant already: the gallery chrome (`showcase_gallery_chrome_widget.dart` →
`AppBoxKitChromeScaffold`) and the three tab-root lists under it
(home/search/profile `*_view.mobile.dart`, `extendBehindTopBar: true`).

Non-compliant surface: six files still assemble their own `appBar:`:

1. `showcase_notes_shell/showcase_notes/showcase_notes_view.mobile.dart`
2. `showcase_notes_shell/showcase_notes_folder/showcase_notes_folder_view.mobile.dart`
3. `showcase_notes_shell/showcase_note_editor/showcase_note_editor_view.mobile.dart`
4. `showcase_profile_shell/showcase_components/showcase_components_view.mobile.dart`
5. `showcase_profile_shell/showcase_motion/showcase_motion_view.mobile.dart`
6. `showcase_profile_widgets/showcase_maps_body_widget.dart`

## Phases

- **S1 Survey (agent `law-survey`)** — classify each file: shell/tab root vs pushed
  route; native glass in scroll content; scrollable type; law-pass greps 1/2/4 over
  showcase lib; routing map (which views sit under the gallery chrome).
- **S2 Migrate (parallel agents, clustered by shell)** — shell/tab roots →
  `AppBoxKitChromeScaffold`; their lists → `AppBoxKitEdgeAwareListView` with
  `extendBehindTopBar: true` + `MediaQuery.paddingOf(context).top` padding. Pushed
  routes: lawful boxed bar stays IF no native glass rides the scroll; otherwise demote
  the in-scroll glass per the informed allowlist or record `// glass-law-exempt:`.
  The scaffold has no leading slot (v1) — pushed routes are NOT migrated to it.
- **S3 Gate** — showcase test suite + kit law gate + lint law-pass greps green;
  single-line commit.

## Survey verdicts (S1, agent law-survey, 2026-08-13)

- Notes shell returns a bare NestedRouter (no gallery chrome) — the tab root view
  migrates to `AppBoxKitChromeScaffold` at the VIEW level ("Folders" title), which
  also avoids handing folder/editor the gallery double-bar stack. Bar-less auth
  branches are lawful and stay untouched.
- Folder view (#2): lawful as-is (boxed bar + Flutter-only scroll; pinned search
  bar is chrome per §1). Maps (#6): lawful (no scrollable). Editor (#3): lawful —
  SingleChildScrollView clips, never sliver-culls, so rule 4 cannot fire; recorded
  as a `glass-law-exempt` comment at the scaffold shell.
- Components (#4): rule 4 (plain ListView cull seam under boxed bar) + rule 5 HIT
  (fixed native input-bar bottomSheet over in-scroll native buttons' travel path).
- Motion (#5): rule 4 + rule 1 HIT (`.wakeAll()` FadeTransition — spec.fade
  defaults true — over the replay card's two native buttons). Fix is targeted
  fade-off for that scope, never a kit-default change.
- Greps: saveLayer over platform views — zero hits; no glass-law-exempt comments
  existed anywhere in showcase before this pass.
- Headroom under a boxed NATIVE bar is lawful (native chrome covers overdraw by
  UIView z-order); the #86787 flash applies only to Flutter-drawn bars.

## S2 assignments

- fix-notes-root → #1 chrome-scaffold migration. DONE (analyzer clean, 14/14).
- fix-components → #4 rule 5 fixed (`AppBoxKitNativeInputBar.wantNative: false`,
  icon buttons stay native per the rule 5 carve-out); rule 4 correctly REFUSED —
  see correction below. DONE otherwise (6/6).
- fix-motion → #5 rule 1 fixed (three wakeAll segments; `spec.copyWith(fade:
  false)` on slots 4-8, covering BOTH the replay card's native buttons and the
  spec-controls segmented control); rule 4 refused likewise. DONE (2/2).
- Inline → #3 exemption comment (done).

## Correction (S2): AppBoxKitNativeAppBar is Flutter-drawn

Both fix agents independently established the brief's premise wrong: the boxed
bar renders CupertinoNavigationBar (pure Flutter; law §1 row agrees), so
`extendBehindTopBar` under it would land overdraw ON screen — the clip 13-32
flash class. Rule 4 therefore stayed open on components + motion.

## S3 ruling (user, 2026-08-13): ratify the floating back affordance

Chosen over exemption and over demoting §2-allowlisted buttons. Work:

1. Agent kit-leading-slot: `leading` slot on AppBoxKitNativeFloatingBar (does
   NOT tuck under minimize — back stays reachable, Apple parity; hides under
   hide) + `leading`/`bottomSheet` on AppBoxKitChromeScaffold (boxed tier:
   `automaticallyImplyLeading: false`); doc comments updated (pushed-route
   scoping superseded); tests; full ui_library suite.
2. Re-task fix-components / fix-motion: migrate their views to
   AppBoxKitChromeScaffold(leading: back) with full-bleed bodies →
   `extendBehindTopBar: true` now lawful + glass-tier top padding.
3. Follow-through: law §1 table row for the scaffold's leading, registry note
   ("bare widget for pushed routes" is superseded), gate/docs/tests, commit.

## S4 ruling (user, 2026-08-13): remove in-scroll demotion — ruling 4

"Ensure search, profile and notes shell have the liquid glass ui as before the
Flutter ui mixed in… remove the non working solution." All SEVEN auto-demoting
widgets flip in one pass (slider, range slider, switch, search bar, text
field, toolbar, glass card). Glass card + toolbar demotion was uncommitted
working-tree work — removal restores HEAD. Law §2/§3 amended (ruling 4);
deselect ladder now runs widest-glass-first (card → toolbar → search bar/text
field → sliders/switch → segmented → popup → split → button). Device run is
the proof.

## S5: device pass 20-20 (clip, 2026-08-13) — two defects, no slabs

Ruling 4's core bet HELD: no slicing slabs, no white rectangles, native
search bar / sliders / switches / toolbar render clean in scroll. Defects:

- **A (all shells): no top-edge dissolve.** Full-bleed content rides through
  the status-bar zone fully visible and garbles with the clock/island. iOS
  handles this with the system scroll-edge effect, unavailable to
  Flutter-composited content. Fix: lawful Flutter-drawn gradient scrim overlay
  in the chrome Stack (title-pill precedent) + reusable widget for bar-less
  auth. Agent: edge-scrim.
- **B (Search): title pill absent at rest — OPEN, attribution pending.**
  Diagnosis (agent pill-hunt, empirical): NOT the tuck machine — the pill is
  laid out at its correct rect, tuck == none, on every frame of a zero-extent
  rubber-band drag. This is a COMPOSITING erasure. Lead suspect: visited tabs
  stay painted at alpha 0.004 in INDEX order, so hidden Profile paints ABOVE
  active Search (probe-confirmed paint order), matching "Search broken /
  Profile fine"; the same file's doc block records device ghosts from exactly
  this leak. Fallback suspect: Search is the only tab whose topmost content
  child is a native platform view (AppBoxKitNativeSearchBar), fitting "pill
  wins the z-fight exactly while a native view passes beneath it".
  DEVICE EXPERIMENTS to attribute (next run): (a) visit Notes, return to
  Profile — ordering predicts Profile's pill now vanishes at rest; (b) Home
  after visiting Profile — ordering predicts Home's pill absent. The natural
  fix (paint active tab last) reorders GlobalKey'd subtrees and platform-view
  composition — the exact change the tab stack's iOS branch exists to prevent
  — so it is NOT applied before attribution.
  Non-bug ruled on: zero-extent lists never tuck because the bottom-overscroll
  guard shadows the accumulator — left AS-IS deliberately: a page with nothing
  to scroll should not minimize on rubber-band (Apple parity).
- Housekeeping: HEAD was uncompilable standalone — the floating bar consumed
  `platformViewSafe`, defined only in an uncommitted working-tree diff; landed
  that set (frosted vibrant fill, tab-stack sub-pixel ClipRect ghost bound,
  fab non-const config) before fix work.

## S6 rulings (user, 2026-08-13 evening)

- **No ancestor chrome over pushed routes** ("there must not be the chrome in
  views like motion showcase"): the gallery chrome moves from shell level
  (wrapping the nested router — floating bar stacked over every pushed
  route's own bar) to PER-SURFACE. Tab roots own their chrome; pushed routes
  render only their own. Agent: chrome-per-surface.
- **The law does not apply chrome to all apps**: chrome existence is
  design-driven — the designer's frozen structure declares per-surface
  chrome; the registry's appbar kind resolves it (shell/tab-root → shell
  variant; pushed+glass-in-scroll → shell variant with leading; pushed
  Flutter-only → bare bar; no-chrome design → bar-less, lawful). The law
  constrains COMPOSITIONS when native glass is present, per target (iOS →
  liquid-glass, Android → M3E, web/desktop → their own standards). Agent:
  law-scope.
- **Search shell view fix: BLOCKED** — the referenced clip
  (20-57-25) is not on disk (Downloads has nothing newer than Aug 1; mdfind
  finds no match). Re-share requested.

## S7: device pass 21-32 (clip, 2026-08-13) — defect B refined

Clip `ScreenRecording_08-13-2026 21-32-28_1.MP4` (5.6s, Search tab; source
file auto-offloaded from Downloads after frame extraction — frames preserved
in session scratchpad `clip2132/`). 22 frames @4fps:

- **The pill vanish is STATE-CORRELATED, not at-rest:** present at rest
  (f001/f008/f013/f022), present while scrolled up under the bar (f010/f011),
  absent on EVERY frame of top rubber-band overscroll (f002-f006, f015-f018),
  restored ≤250ms after settle. NOT the tuck machine: behavior=minimize tucks
  BOTH ends, and the trailing actions never move in any frame, so `_away`
  never fired; `_onScroll` also force-restores at `pixels <= 0`.
- **Theme anomaly (attribution lead):** the resting pill renders a WHITE
  capsule with DARK text — exactly the LIGHT-branch frosted values (paper
  fill, ink text) — while every sibling (scrim, cards, labels) renders the
  dark palette. Current source cannot paint that from one context: the same
  `scheme` feeds both the pill fill and its label. Suggests the on-screen
  capsule is not (or not only) the committed Flutter pill.
- **Tab-stack correction:** iOS is an instant cross-cut, ONE tab on stage per
  frame (tab host doc, `showcase_application_tab_host_widget.dart`) — the
  alpha-0.004 ghost-above-active suspect from S5 was the Android slide path
  and is DEAD on iOS.
- **Secondary:** bright native slider thumb bleeds through the top-edge scrim
  ramp next to the pill (f011) — the scrim dims Flutter-drawn dark content
  fine but a white 30px thumb survives the semi-transparent ramp zone. Watch
  item, not yet a ruling.
- Repro rig: temp probes (AppDelegate composited-window snapshot timer +
  auto-switch-to-Search + driven `animateTo(-140)` held rubber-band) on the
  attached device, current source — to attribute before fixing.

### S7 resolution — RESOLVED, law rule 7 (2026-08-13)

- Reproduced on current source (theme anomaly was recording tone-mapping —
  the probe's composited capture shows the correct dark pill at rest).
- View-tree diff attributed it: the pill's `FlutterOverlayView` shrank from
  `(16,59,361x78)` at rest to the actions' bbox `(281,59,96x44)` during held
  overscroll — engine `flow/view_slicer.cc` keeps Flutter ops above platform
  views only while they intersect a platform-view rect; otherwise they drop
  to a difference-clipped background canvas. Scroll-state-dependent by
  construction; no Flutter-side reorder can stabilize it.
- Fix: vendor PATCH #10 `CNGlassEffect.plain` (no glass material — clear
  fill + `Glass.identity`, iOS + macOS parity) + the bar wraps its frosted
  pill in a stationary plain `LiquidGlassContainer` anchor, so the
  intersection holds every frame. 13-53 stays closed (no glass to wash);
  transition-gate exemption recorded (anchor renders nothing).
- Device-verified with the same driven rubber-band: pill present at rest,
  through the full held overscroll, and over passing content. ui_library
  suite 356 green incl. new anchor pin in the bar test.
- Every consumer of AppBoxKitChromeScaffold inherits the fix (all four
  shells + pushed routes); law rule 7 records the anchor requirement for
  any future floating Flutter chrome.

## Device-pass watch items (from S3 agents)

- Long titles overflow the floating bar's non-flex title pill row (pre-existing;
  the leading slot makes it 52px worse). Fixing means deciding what "2.0x own
  width" tuck offset means under Flexible — geometry call against a device clip.
- `extendBehindTopBar` is unconditional on the migrated views (matches the
  ratified gallery pattern), so BOXED tiers paint 64px overdraw under an opaque
  Flutter bar — check Android/pre-26 iOS for 13-32-class artifacts.
- Components input bar demoted via `wantNative: false` renders the Material
  capsule (solid), not a frosted pill — restyle only if the device pass objects.
- MediaQuery padding under the chrome must be read BELOW the scaffold (Builder
  wrap) — the floating chrome raises padding.top for its body subtree only.
