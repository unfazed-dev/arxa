# The liquid-glass law — native glass on iOS/macOS, ratified

**THE liquid-glass law** (term ratified 2026-08-13; VOCABULARY.md): single
source of truth for which kit widgets are native platform views, which carry
Liquid Glass, what happens inside scrollables, and the composition rules that
keep it artifact-free. Enforced by kit gate tests + appbox-lint rules —
gates, not prose. The reuse unit is the chrome scaffold
(`AppBoxKitChromeScaffold`) — the lawful ASSEMBLY of top chrome wherever a
design declares it, never a mandate that a surface HAS chrome (see *Chrome
existence is the design's call*). The Android sibling is the M3E law
(docs/m3e-law.md); per target, iOS/macOS answer to this law, Android to
M3E, and web / Windows / Linux to their own platform conventions — no
liquid-glass chrome is implied there.
Governing principle (decided 2026-08-12, grilled):
**Apple-fidelity — the kit does exactly what iOS 26 does, nothing more,
nothing less.** When a dispute arises, the answer is "what does Apple's own
app do here?", verified against the sources at the bottom, not taste.

## The three classes

### 1. Chrome — native glass, always
Fixed elements floating above content. Glass is *reserved* for this layer
(WWDC25 219: "Liquid Glass is best reserved for the navigation layer").
"Always" scopes to MATERIAL, not to presence: chrome that exists on this tier
is native glass — it never means a surface must have chrome. A design that
declares none ships bar-less and is fully lawful (the notes auth panels are
the reference). See *Chrome existence is the design's call*.

| Kit widget | Notes |
|---|---|
| AppBoxKitTabBar / CNTabBar | |
| AppBoxKitNativeToolbar (as chrome) | Scaffold-anchored bars only — see §3 for in-content demos |
| AppBoxKitNativeFab / FabMenu | Scaffold FAB slot |
| AppBoxKitNativeSheet / NativeDialog / NativePopupMenu | Transient overlays |
| AppBoxKitNativeSearchBar (docked/pinned) | Pinned sliver headers count as chrome |
| AppBoxKitNativeAppBar / SliverAppBar | Flutter-drawn; on the GLASS TIER the gallery replaces it with AppBoxKitNativeFloatingBar (see rule 4 ruling) |
| AppBoxKitNativeFloatingBar | Native glass floating top chrome (glass tier) — title capsule + native actions over a full-bleed body; the top-edge counterpart of the tab bar. Since the floating-back-affordance ruling (2026-08-13) it takes a `leading` slot (tucks off the leading edge with the title pill — device ruling clip 22-34 superseded the same-day non-tucking ratification: a pill leaving without the back button read as a half-minimized bar; scroll-back/top restores both), so pushed routes with in-scroll native glass use the chrome scaffold too |

### 2. Controls — ALL NATIVE IN SCROLL (ruling 4, 2026-08-13, supersedes the informed allowlist)
Every control is **native Liquid Glass everywhere, including scrollables**.
The in-scroll auto-demotion (`preferFlutterTier: Scrollable.maybeOf(context)
!= null`) is DELETED from all kit widgets. Per-instance demotion flags
(`wantNative`, `preferFlutterTier`) remain for deliberate exceptions (e.g.
the components input bar under rule 5).

Evidence trail (states 1-3 device-observed 2026-08-13; state 4 is the
chrome-era ratification):
1. Native-everywhere: artifacts on Search/Profile scroll (clips 08-24, 11-34).
2. Full demotion (`4af16e3f`): artifacts GONE — slicing mechanism confirmed
   (engine #150646, open through Flutter 3.47.0; overlay rects ignore clip
   bounds).
3. Home's 7 `AppBoxKitNativeIconButton`s — real UiKitViews inside a ListView,
   never gated — rendered clean the whole time: CNButton-backed views are
   exposure-safe in practice. Exposure is compositional, not categorical.
4. Ruling 4 (user, chrome era): with every composition that actually fired
   the artifacts now law-gated away (no saveLayer over platform views, no
   alpha-hide, no glass-on-glass overhang, cull boundary off-screen under
   floating chrome), the demotion is a workaround whose cause is gone —
   removed in one flip; the device run is the proof, the deselect ladder the
   rollback. Superseded table (states 2-3 era): sliders/range/switch/search
   bar/text field took the Flutter tier in scroll; that split is history, not
   law.

**Known deviation from HIG, accepted knowingly:** Apple's Materials page says
"Don't use Liquid Glass in the content layer" and gives in-list
sliders/toggles glass only *during activation*. Ruling 4 extends the
button-class deviation to every control — user-ratified as a deliberate
product choice.

**Deselect protocol (if artifacts reappear in a scrollable):** re-demote ONE
type per device run, WIDEST GLASS FIRST — glass card, then toolbar, then
search bar / text field, then sliders / switch, then segmented, popup menu,
split button, button last. Never blanket-demote again — attribution first.

### 3. Glass surfaces — native in scroll under ruling 4 (2026-08-13)
Ruling 4 covers surfaces too: AppBoxKitGlassCard and AppBoxKitNativeToolbar
render native glass inside scrollables (their in-scroll demotion — which had
never landed beyond an uncommitted working tree — was dropped in the same
flip). This knowingly deviates from Apple's named anti-pattern ("don't break
the glass… keep glass out of the scrolling content layer" — WWDC25 design
lab) and the vendor README's LiquidGlassContainer-in-lists warning, which is
exactly why these two sit FIRST on the deselect ladder: if any slab returns,
the glass card is the first re-demote, the toolbar second.

**Composition rules (learned on device, 2026-08-12 evening):**
1. **No saveLayer effect may wrap a subtree that may host platform views** —
   BackdropFilter, partial-alpha Opacity, ShaderMask, ImageFiltered alike.
   The saveLayer cannot span the frame slices UiKitViews create; Flutter
   content inside it drops or ghosts per frame (flutter#175048;
   kit/core/NATIVE_COMPONENTS.md). In-scroll surfaces use the vibrant-fill
   variant — which is also Apple's own degrade for nested glass.
2. **Demoting a composite widget must propagate the tier to its children.**
   CNGlassButtonGroup's fallback rebuilt child configs without
   `preferFlutterTier`, silently re-promoting them to native UiKitViews
   inside the scrollable (vendor LOCAL PATCH #7 fixes this). Any future
   composite fallback must inherit the parent's tier.
3. **Alpha-hiding a platform-view-rich subtree is not containment — clip it
   too.** A tab kept alive at 0.004 alpha still paints every frame; its
   platform views slice the ACTIVE tab's frame into overlay textures, and
   pieces of the hidden subtree composited over the active tab at visible
   alpha (stale rail-pane rectangle over Profile, "Maps showcase" ghost over
   Search — device recording 2026-08-12 22:46). AppBoxKitAnimatedTabStack now
   pairs the alpha-hide with a sub-pixel ClipRect: paint still happens (the
   views never detach — 00bc2f0c's guarantee holds), but a hidden tab can
   contribute at most half a pixel to the frame.
4. **Native views must not cull at a mid-screen viewport edge (clips 12-48,
   13-17).** The engine drops a platform view the moment it stops being
   painted and re-materializes it on re-entry with a visible glass shimmer.
   Sliver child culling is **layout-based**, not clip-based:
   `RenderSliverMultiBoxAdaptor.paint` skips a child once
   `mainAxisDelta + paintExtent <= 0` at the viewport's leading edge —
   `clipBehavior` never participates, so the first fix (`Clip.none`,
   35ed8ec0) was inert and clip 13-17 showed the seam shimmer unchanged.
   Second fix (`extendBehindTopBar`, fd5f4422): oversize the viewport
   upward (OverflowBox, bottom-aligned; overdraw returned as top padding)
   so culling happens off-screen like the bottom edge — REGRESSED, see
   counter-evidence below; reverted at the gallery call sites.
   `Scaffold.extendBodyBehindAppBar` was rejected twice: the gallery body
   hosts nested-route Scaffolds whose own bars would inherit the inset
   shift.
   Corroboration (engine source, 2026-08-13): an unpainted platform view is
   `removeFromSuperview`'d entirely (FlutterPlatformViewsController.mm
   ~:1011) and re-added via `addSubview:` on re-entry — so a cull kills the
   WHOLE view, label included. Discriminator vs the fade signature: label
   survives + direction asymmetry = scroll demotion (no geometry fix helps);
   whole view pops = cull (this rule applies). That iOS 26 glass replays its
   materialization on re-add is device-observed inference — no Apple source
   states it.
   **Counter-evidence (clip 13-32): the overdraw fix REGRESSED.** With
   platform views painting behind the Flutter bar, overlay-layer churn
   flashed body content OVER the bar during fast scrolls — the flutter#86787
   class the research pass flagged as watch-item. Overdraw reverted at the
   gallery call sites the same day. Standing conclusion after three
   mechanisms (edge-effect alpha, Clip.none, viewport overdraw): a
   Flutter-drawn opaque bar cannot reliably cover platform views passing
   behind it (paint order does not survive hybrid-composition slicing), and
   culling them at the seam shimmers. The robust arrangements are (a)
   native top chrome — UIView-over-UIView z-order, the reason the bottom
   tab bar is clean — or (b) no platform views in the scrolling content
   under the bar. Direction is a product ruling, not a patch.
   **Ruling (2026-08-13, user-ratified): native top bar.** The gallery
   chrome now branches: glass tier = `AppBoxKitNativeFloatingBar` (frosted
   Flutter title pill per rule 5 + the existing native action buttons)
   floating over a FULL-BLEED body, so content culls at the physical
   screen edge; other tiers keep the boxed Flutter bar.
   ⚠️ SUPERSEDED (2026-08-13, chrome-per-surface ruling): the clause
   "nested-route Scaffolds inset via the chrome's raised MediaQuery top
   padding, unmodified" described SHELL-level chrome wrapping the nested
   router — the arrangement now outlawed as the double-bar stack. Chrome is
   per-surface; a pushed route resolves its own chrome or none. See *Chrome
   existence is the design's call*.
   Plan: docs/plans/native-top-bar.md.
   **Residual + fix (clip 13-53-b):** re-add at the boundary is
   TIME-based — the culled smoke block's bottom row re-entered the screen
   mid-materialization (identical widgets to the clean top row; the only
   difference was leading re-entry). Fix: `extendBehindTopBar` overdraw is
   BACK ON for the gallery lists — now safe because the overdraw region is
   off-screen above a native/full-bleed chrome (the 13-32 flash needed the
   opaque Flutter bar, which no longer exists). The boundary sits ~120px
   above the physical top, buying the animation time to finish unseen.
   **Top-edge scrim (added 2026-08-13, UNPROVEN on device).** Full-bleed
   content — native platform views included, per ruling 4 — rides through the
   STATUS BAR fully visible and garbles with the clock/battery/Dynamic
   Island. iOS solves this with the system scroll-edge effect, which is
   unavailable to Flutter-composited content, and every effect-based
   equivalent is barred by composition rule 1 (a BackdropFilter band cannot
   sample platform-view pixels; an alpha fade saveLayers the content).
   `AppBoxKitTopEdgeScrim` is the lawful substitute: a Flutter-DRAWN vertical
   gradient from `scaffoldBackgroundColor` (opaque across the status-bar
   inset) to transparent at the bar block's bottom edge, a sibling in the
   chrome Stack between body and bar, `IgnorePointer`, surviving tuck/hide.
   It adds no layer, so both gates pass. **But note it is full-width and
   opaque over passing platform views — the clip 13-32 shape.** The title-pill
   precedent it was argued from is PARTIAL-width, which is the discriminating
   difference. Watch the next device run for body content flashing over the
   status band during a fast fling; if it appears, the answer is native chrome
   for the band, not another gradient. Pinned by
   appbox_kit_native_floating_bar_test (5 pins: height, pointer, paint order,
   tuck/hide survival, no-saveLayer/no-alpha).
5. **No native glass may overhang a path scrolled native glass travels
   (clip 13-53).** With the floating native bar, the home smoke row's
   compose button washed to a square ghost for EXACTLY the title capsule's
   span while crossing it — glass-on-glass stacking — and buttons crossing
   the pill gaps stayed crisp (the discriminating observation). Apple's
   "don't stack glass" applies across our chrome/content split: fixed
   chrome elements that scrolled glass passes under must be Flutter-drawn
   (AppBoxKitFrostedSurface platformViewSafe) — so the floating bar's
   TITLE pill is deliberately not native. Interactive bar controls stay
   native glass; if partial overlaps (warning icon under the search
   button) ever artifact, widen the pill gaps before demoting anything.
   The Flutter pill additionally rides a plain (non-glass) native anchor —
   see rule 7; that anchor renders no material, so this rule's ban and the
   anchor coexist. Pinned by appbox_kit_native_floating_bar_test.
6. **Fill color and foreground travel together in fallbacks.** Any fallback
   that sets a CupertinoButton `color` must set the foreground too: solid
   fill → contrasting color, translucent tint wash (glass) → the tint itself
   (vendor PATCH #5). The default foreground flips with `color` and lands
   tone-on-tone both ways (auth's blank Sign In; the profile toolbar's blank
   Share/Edit/Delete).
7. **Floating Flutter chrome over a platform-view scrollable rides a PLAIN
   native anchor (clip 21-32, device-attributed 2026-08-13).** The engine's
   view slicer (`flow/view_slicer.cc`) keeps Flutter ops painted after a
   platform view in an overlay ONLY while their rects intersect a
   platform-view rect below them; non-intersecting ops drop to a background
   canvas that is difference-clipped by every overlay rect. Chrome floating
   over scrolled platform views therefore has NO stable home: the frosted
   title pill rendered at rest and while content passed beneath it, but
   vanished wholesale during top rubber-band overscroll — composited-window
   probe showed its overlay shrinking from `(16,59,361x78)` to the action
   buttons' bbox `(281,59,96x44)`, clipping the pill out. Fix ratified: the
   pill keeps its Flutter frosted visuals and gains a stationary
   `LiquidGlassContainer(effect: CNGlassEffect.plain)` beneath it (vendor
   PATCH #10) — `plain` renders NO glass material (clear fill,
   `Glass.identity`), so rule 5's glass-on-glass ban is not reopened; the
   anchor exists purely so the pill's ops intersect a platform-view rect
   every frame. Device-verified: pill present through a driven held
   rubber-band that reproduced the erasure pre-fix. Any future Flutter-drawn
   chrome floating over glass-bearing scrollables needs the same anchor —
   partial-width Flutter overlays are NOT exempt from slicing, only
   full-width opaque bars were previously called out (rule 4 / 13-32).
   Pinned by appbox_kit_native_floating_bar_test (anchor pin).

8. **Hidden-but-painted platform views must be transformed off-screen — alpha
   and clip do NOT contain their slicing geometry (clip 22-43, labelprobe,
   device-attributed 2026-08-13).** The view slicer intersects Flutter ops
   with hidden platform views' UNCLIPPED, full-alpha rects: the animated tab
   stack's 0.004-alpha ghost tabs (kept painted so tab switches never change
   the platform-view set) sliced the ACTIVE tab's section labels against a
   hidden tab's rects — Motion's "FLUTTER_ANIMATE ADAPTER" clipped to exactly
   a hidden 147pt title-pill-anchor rect, "Motion enabled" cut to "abled" by
   hidden 44pt icon-button rects — even though the hidden tabs painted
   through a half-pixel clipper. Only a TRANSFORM changes the rects the
   slicer sees. Fix ratified: hidden tabs additionally ride a
   `Transform.translate` 100000px off-screen (driven to identity on the
   active tab) — the platform-view set stays constant (no detach, no glass
   re-materialize; the tucked-chrome idiom), while hidden rects can never
   intersect on-screen ops. Every tab and every pushed route inherits this
   from the shared stack; routes beneath opaque pushed routes are not
   painted at all (verified: no second anchor in the probe dumps), so ghost
   tabs were the only invisible slicing geometry in the app. Pinned by
   appbox_kit_animated_tab_stack_test (off-screen translate pin).

9. **Warm every glass KIND at boot that only pushed routes mount —
   `AppBoxKitGlassWarmup` (device-measured 2026-08-14).** First
   materialization of a glass kind is a once-per-PROCESS cost paid on
   whichever frame first composites it: pushing the first glass-card route
   cost a 39.6ms raster frame (4.8% of push frames over the 60Hz budget)
   while pushes 2/3 of the same route peaked at 10–12ms with zero frames
   over budget. The cost is per KIND, not per view — glass buttons/segmented
   already on the boot screen were warm; the surface container
   (`LiquidGlassContainer`, glass card) and the switch each paid their own
   first-of-kind spike. The kit primitive `AppBoxKitGlassWarmup` wraps the
   shell root once: it mounts one card-kind container (plus host-listed
   `alsoWarm` kinds) translated 100000px off-screen per rule 8, IgnorePointer
   + ExcludeSemantics, kept mounted (set constancy; NOT chromeGated — the
   gate would churn the exact materialization being prefetched). Measured
   after: first push worst frame 11–12ms, 0% over the 60Hz budget —
   indistinguishable from steady-state pushes. Rule: kinds visible at boot
   warm themselves; any kind a pushed route mounts first goes in `alsoWarm`.
   Pinned by appbox_kit_glass_warmup_test (rule-8 translate + kind pin).

10. **An interactive back-swipe is a POP and must read as one — gesture state,
    not animation state, is the signal (device clip 00-26, 2026-08-14).**
    `AppBoxKitNativeChromeGate` decides "am I travelling with this transition?"
    from `route.animation/secondaryAnimation.isAnimating`. Both are false for
    the whole edge-drag, and the SDK says why: `dragUpdate` sets
    `controller.value` DIRECTLY (`cupertino/route.dart:846`), which never
    starts a ticker, and `didStartUserGesture` ticks the observer before the
    drag has moved anything at all. The gate re-evaluates only on observer
    ticks and latches, so one wrong read at gesture start hid EVERY gated
    view in the gesturing navigator for the entire drag — then restored them
    at the `didPop` tick mid-settle, materializing all the glass in the
    user's face. Device signature: during the swipe both routes go bare
    (cards, switch, segmented, native buttons, back chevron all gone) while
    Flutter-drawn frosted pills and the root-scoped tab bar stay — that
    survivor set IS the diagnostic, since it is exactly the gate's hide set
    and nothing else. Fix: OR in
    `route.navigator.userGestureInProgress`, which `NavigatorState` raises
    BEFORE notifying observers (`navigator.dart:5827` vs `:5837`) and holds
    through the settle (`cupertino/route.dart:905` defers
    `didStopUserGesture` to the settle's status callback). Scoped for free —
    it is the gate's own navigator, so a nested swipe cannot repaint root
    chrome, and no push is gesture-driven, so the sibling-bar hide under a
    root push is untouched. Deliberate and NOT an oversight: a ROOT-level
    gesture pop over the tab scaffold now keeps the sibling tab bar painted,
    because there the bar sits on the route being revealed and travels with
    it — the same answer the button pop already gives. The result is that a gesture pop behaves
    identically to a button pop, which was already ratified and device-clean.
    Pinned by appbox_kit_chrome_gate_transition_scope_test (back-swipe test,
    mutation-checked: without the clause it reports a hidden gate on every
    drag frame; the drag must cross the halfway line or Cupertino cancels the
    pop and the frame samples go vacuous).

    **Ask EVERY enclosing navigator, not just your own (amended same day
    after an SDK sweep of all interactive dismissals).** `userGestureInProgress`
    lives on the single `NavigatorState` that owns the DRAGGED route, which is
    not necessarily the asking widget's. `CupertinoSheetRoute` is the shape
    that proves it: it pushes onto the ROOT navigator and hands its drag
    controller `route.navigator!` (`sheet.dart:210/855`), so a gate inside the
    sheet's own nested `Navigator` sees no gesture on its own navigator and no
    animation on its own route — and blanks while visibly travelling with the
    sheet. Reproduced headlessly with plain Cupertino routes (the mechanism is
    the navigator mismatch, not the sheet) and fixed by walking outwards with
    `findAncestorStateOfType`, the same walk `hasActiveTransitionAbove` does.
    A navigator that encloses you can move you.

    **Coverage of the other interactive dismissals (SDK-swept, 2026-08-14):**
    iOS edge back-swipe (`cupertino/route.dart:835`), Cupertino sheet
    drag-to-dismiss (`cupertino/sheet.dart:1053`) and Android predictive back
    (`widgets/routes.dart:569`, reached from the platform-channel handlers)
    ALL raise the gesture flag — covered. `showCupertinoModalPopup` has no
    drag dismissal at all and pops with a genuinely ticking animation —
    covered by `isAnimating`. The one true blind spot is Material's
    `ModalBottomSheetRoute`: it never calls `didStartUserGesture` (zero
    matches in `material/bottom_sheet.dart`) and its drag sets the route
    controller's value directly (`:285`), so BOTH signals read false.
    Measured as NOT reachable for this gate — the gate re-evaluates only on
    observer ticks and latches, and a Material sheet drag fires no tick — but
    it is latent, so it is pinned by a test rather than left to reasoning. A
    gate mounting mid-drag, or any new tick source, would expose it.

11. **A sheet hides only the chrome it actually COVERS (2026-08-14, closes the
    all-or-nothing ceiling the gate doc named).** The gate's modal branch hid
    on `anyModalDepth > _mountDepth` alone, so opening any sheet
    dematerialized EVERY native glass surface behind it — including the ones
    still plainly visible in the clear space above a short bottom sheet — and
    materialized them all back on dismiss. Same "glass vanishes, then pops
    back" defect as the back-swipe, reached through the modal branch instead
    of the transition branch. The rect was already there and being ignored:
    `CNBottomSheet` publishes the sheet's LIVE box each frame through
    `CNSheetGeometryProbe` for exactly this purpose (its comment: *"measuring
    the route would tear down native chrome sitting in the clear space above a
    short sheet"*), and the kit wraps the probe around the sized body, not the
    route (`appbox_kit_native_sheet.dart:274`). Fix: the gate now consults
    `CNTabBarRouteObserver.topModalRect` and hides only on overlap — the same
    predicate the vendor's `ModalHideMixin._computeShouldHide` already
    applies, deliberately identical so the two authorities cannot disagree
    about the same sheet. Fails toward HIDING on every uncertainty (no rect
    published — a plain `showModalBottomSheet`, a dialog — or no measurable
    box), so the original bleed fix is preserved verbatim for anything that
    cannot describe its own geometry.

    **The scrim, stated correctly (an earlier draft of this rule got it
    backwards).** `CupertinoSheetRoute` does hardcode a transparent barrier —
    but the kit OVERRIDES that, and dimming is the DEFAULT, not opt-in:
    `showOverlay` defaults `true` (`appbox_kit_native_sheet.dart:131`), so the
    normal path passes `kCupertinoModalBarrierColor` and lands on
    `_CNDimmedSheetRoute` (vendor `bottom_sheet.dart:228`), a full-screen dim
    over the page. So glass left painted above a short sheet sits under a
    scrim. That is still the right call, because a SOLID-COLOUR barrier is an
    ordinary paint op: it intersects the platform view's rect, so the slicer
    hoists it into an overlay ABOVE the native view (rule 7's mechanism) and
    the dim lands. This is the one case a `BackdropFilter` cannot do — a blur
    must sample the native layer it can't see, which is the whole reason the
    modal hide exists at all. Solid dims and blurs are NOT interchangeable
    here; do not generalise from one to the other. **Reasoned from rule 7, not
    device-verified.** Falsifiable signature if it is wrong: glass above an
    open sheet reads BRIGHTER than the dimmed content around it. That would be
    a tint bug, not a reason to go back to blanking the whole page.

    Pinned by appbox_kit_chrome_gate_sheet_coverage_test
    (4 cases incl. the sheet growing into a gate and the mount-depth baseline
    that stops a sheet's OWN chrome self-hiding), mutation-checked.

12. **Toasts are Flutter-tier, and the gate test reads CODE, not prose
    (2026-08-14).** `CNToast` wraps its body in a real `LiquidGlassContainer`
    (vendor `toast.dart:503`), then runs it through `ScaleTransition` +
    `FadeTransition` on both edges (`:571-577`) — alpha animation over a
    platform view, the ghosting idiom this law already forbids — and mounts it
    via a bare `OverlayEntry` (`:302`) that no gate can reach. It was the one
    native glass surface in the kit that could not leave the frame for a route
    slide, and a toast most often fires right after a nav action. Fixed at the
    call site: every `CNToast` kind now passes `useGlassEffect: false`
    (`appbox_kit_notification_service.dart`), matching `_centerPill`, the
    service's other, already-Flutter-drawn toast. Two enforcement holes let it
    live: the gate test scanned only `lib/widgets` non-recursively (the call
    site is in `lib/services/`), and `CNToast`/`CNIcon` were absent from its
    pattern. Both closed — the scan is now all of `lib/` recursively. It also
    matched RAW source, so a file could satisfy the rule by MENTIONING
    `.chromeGated()` in a comment: caught in the act, when a comment written
    to explain this very leak silenced the test about it. The scan now strips
    whole-line comments before matching, and the opt-out alone is read from
    raw source. **A rule that can be silenced by writing about it is not
    enforcement.**

**Known signature, not a defect — glass edge refraction (labelprobe
2026-08-13):** each in-scroll glass card shows dim copies of its NEIGHBORING
section labels just inside its top/bottom edges, riding the card at constant
offset. This is the liquid-glass material's edge lensing sampling adjacent
screen content — it survives full repaints (`FLTDisablePartialRepaint`
verified no-op against it) and matches no slicer geometry. Dark-on-dark makes
it read as a ghost because the rest of the glass effect is invisible. If it
ever bothers on device, the levers are design ones: more spacing between
labels and glass edges, or a more opaque card tint — not engine flags.

**Resolved residual (2026-08-13, clip 12-48):** `AppBoxKitScrollEdgeEffect`'s
partial-alpha fade over edge-band children hosting native controls produced
exactly the predicted artifact (home's smoke row + Glass CTA: glyphs washed
out ahead of the shell, pale ghosts, pop-in on re-entry). Fix landed: the
effect is now **fully inert on the Liquid Glass tier** (alpha gated alongside
the blur) — children exit by plain viewport clipping, which is what iOS does
under opaque chrome anyway and costs zero layers. The frosted tiers keep the
blur + fade (pure Flutter under the saveLayer). Pinned by
`appbox_kit_scroll_edge_effect_tier_test.dart`.

**Deviation note — split button:** obsolete — under the informed allowlist
(§2) CNSplitButton is native in content by rule, not by deviation.

## Chrome existence is the design's call (ruling 2026-08-13, user)

This law governs COMPOSITION, never inventory. **appbox-designer decides
whether a surface has top chrome; the law decides how chrome is assembled
where it exists.** The designer's frozen structure/anatomy is the authority
per surface; the scaffolder resolves that declaration through the appbar kind
(`skills/appbox-scaffolder/kind-resolution.registry.json`) and builds it to
the target's own standard with native UI wherever applicable. Nothing here
synthesizes chrome an anatomy did not declare.

| What the design declares for a surface | What resolves |
|---|---|
| Shell / tab-root top chrome | `shell` variant → `AppBoxKitChromeScaffold` |
| Pushed surface, native glass in its scroll | `AppBoxKitChromeScaffold` with `leading` (back) |
| Pushed surface, Flutter-only scroll | bare boxed bar (`AppBoxKitNativeAppBar`) |
| No top chrome | nothing — bar-less is fully lawful (notes auth panels) |

**Per target.** This law is the iOS/macOS standard. Android answers to the
M3E law (docs/m3e-law.md); web and Windows/Linux answer to their own platform
conventions — no liquid-glass chrome is implied on those targets, and the
composition rules above are scoped to targets where native glass exists.

**Double-bar ban (structural, 2026-08-13).** A surface must never wrap a
nested ROUTER in floating chrome. Shell-level chrome over a nested router
stacks the floating bar above every route pushed inside it, so a pushed
surface carrying its own bar renders two — the double-bar stack. **A pushed
route never inherits an ancestor surface's floating chrome**; each surface
owns its chrome or has none. The gallery's chrome moved from shell level to
per-surface for exactly this reason. Flagged by the lint law pass.

Where native glass IS present the composition rules bind in full — saveLayer,
alpha, cull boundary, glass-on-glass overhang. They constrain what the design
asked for; they never add to it.

## Performance policy (decided with the allowlist)
Platform-view cost scales per live view per frame (no cliff; ~45 MB and a
render-target switch per view — flutter#46666, #40108). The tab stack's
alpha-keep-alive means visited shells keep compositing. Policy: **land, then
measure on device**. The keep-alive (anti-flicker, commit 00bc2f0c) is not to
be touched without device evidence that it is the bottleneck — this codebase
has twice killed a correct mechanism to protect a defective one.

## History
- Round 1–2 (2026-08-12): blanket in-scroll demotion of all natives shipped
  and was reverted for controls the same day — it enforced a rule Apple only
  holds for glass *surfaces*. See docs/plans/scrollable-glass-demotion.md.
- Round 3 (2026-08-13): full control demotion (`4af16e3f`) on the clip-0813
  probe trail; device run confirmed artifacts gone (mechanism proven), then
  superseded same day by the informed allowlist (§2) once home's ungated
  in-scroll icon buttons proved button-class views exposure-safe.
- Round 4 (2026-08-13, evening): chrome scoped to the design. The law had
  read as a blanket "every view gets the chrome scaffold"; the ruling splits
  existence (designer) from assembly (law) and moves the gallery's chrome
  from shell level to per-surface, superseding the nested-route inset clause
  in rule 4 and outlawing the double-bar stack.
- Vendor LOCAL PATCH #5 (fallback label contrast) and #6 (preferFlutterTier
  plumbing) remain: #5 fixes the pre-26 tier; #6 serves surfaces (§3) and any
  future opt-in.

## Sources
WWDC25 219 (Meet Liquid Glass), 284, 356; WWDC25 design-lab and UI-Frameworks
lab transcripts (samhenrigold gists); Apple HIG Materials; expo#44739
(segmented indicator glass at rest in lists); cupertino_native_better README;
flutter#46666 #40108 #103014 #107486; docs.flutter.dev iOS platform views.
