# Clip 08-13 defects — web research on causes and fixes

Researched 2026-08-13 against defects A/B/C in `docs/plans/clip-0813-0824-sweep.md`.
Local build under test: **Flutter 3.44.9 stable**, engine rev `5a2a6a42cc` (2026-07-31).
Vendored `cupertino_native_better` **1.5.2** (`kit/ui_library/vendor/`).

Confidence tags: **[V]** verified by fetching the primary page; **[S]** search-summary
only, not fetched — treat as a lead; **[H]** my synthesis, not stated by any source.

> Provenance warning: a search summarizer in this session fabricated an "Apple engineer"
> quote about `UIVisualEffectView` render buffers, attributed to Apple forum thread 94071.
> Fetching that thread shows two ordinary users and no such content. The same channel also
> asserted "the overlay bug was fixed in Flutter 2.2+" and "#143420 closed via engine#50637"
> without corroboration. None of those three claims are used below.

---

## 1. How iOS composites platform views (the shared mechanism)

Flutter on iOS uses **hybrid composition only**: "iOS only uses Hybrid composition, which
means that the native `UIView` is appended to the view hierarchy."
[V] <https://docs.flutter.dev/platform-integration/ios/platform-views> (3.44.7, upd. 2026-07-17)

Flutter content that overlaps a platform view is **sliced** and re-drawn into pooled
`FlutterOverlayView` layers stacked above that platform view. The controller holds
`_slices` (`unordered_map<int64_t, EmbedderViewSlice>`), a `LayersMap`, an
`OverlayLayerPool`, and `_compositionOrder` / `_previousCompositionOrder`.
[V] <https://api.flutter.dev/ios-embedder/_flutter_platform_views_controller_8mm.html>

Engine PR **#54010** (jonahwilliams, merged 2024-07-24) moved iOS onto Android's slicing
strategy: it "removes support for 'unobstructed platform views' on iOS", creates "at most
one overlay per embedder view slice", and where iOS previously allowed two overlays per
platform view "the rects are merged into a single one that is the union of all the rects."
[V] <https://github.com/flutter/engine/pull/54010>

**Consequence that matters here:** every Flutter widget overlapping a native control is no
longer drawn by the main Flutter canvas — it is re-drawn into a per-slice overlay whose
geometry is a *merged union rect* recomputed each frame. If that rect is wrong, stale, or
the overlay is dropped, the widgets inside it vanish while the platform view stays. That is
the exact shape of Defect A.

**Known-open engine defect in this path:** flutter#**150646** — "iOS embedder creates
overlay layer based on platform view bounds but does not take clip bounds into account."
Opened by jonahwilliams 2024-06-21, **still open**, P2, `a: platform-views`, project "iOS
Platform View Performance". Reporter observed "there is nothing in the overlay layer, but we
still present it," and proposes querying `EmbedderViewSlice`/`DlCanvas` for remaining ops
after culling. [V] <https://github.com/flutter/flutter/issues/150646>

**Second known-open defect:** flutter#**163498** — "[iOS] [Platform View] Animations cause
Flutter UI to flicker and platform view to be visible." Filed 2025-02-17, **still open**,
P2, `c: regression`, team-engine. Version table in the issue: 3.16.9 ✓, 3.24.5 ✓,
3.27.4 Impeller-disabled ✓, **3.27.4 / 3.29.0 / 3.32.5 / 3.35.1 Impeller-enabled ✗**.
So: an Impeller-only platform-view compositing regression, open across every release line
our build descends from. [V] <https://github.com/flutter/flutter/issues/163498>

**Layer-pool recycling ("junk") history** [S]: flutter#152053 / engine PR **#54056** —
pooled overlay layers were marked available but never flushed, producing junk content with a
`UIImageView` platform view while scrolling; fixed by flushing the pool on `SubmitFrame`.
The pool retains one layer (`kLeakLayerCount = 1`) to avoid thrashing when platform views
scroll under a bar, with a source comment pointing at #150646. *Version status:* #54056
merged mid-2024, so it is **in** our 3.44.9 engine. The un-fixed residue is #150646/#163498.
<https://github.com/flutter/engine/pull/54056>

### Analogy only — not an iOS constraint

The Android docs, under **HCPP**, document: "**Complex overlay stacking**: Transparent
platform views won't display correctly in layout stacks structured as: Flutter canvas ->
Platform View -> Overlay -> Transparent Platform View, when all four of these layers
intersect." [V] <https://docs.flutter.dev/platform-integration/android/platform-views>

I fetched the live **iOS** page and this text is **not present** there. Our native glass
controls *are* transparent platform views over overlays, so the stack shape matches — but
cite this as a model of how slice-based compositing fails, never as a documented iOS rule.

---

## 2. Defect A — label drops + stale white slab (sliders/switches in a scrolling card)

**Primary mechanism (high confidence).** The section labels and switch-row text overlap the
`CNSlider`/`CNSwitch` platform views, so they are sliced into per-slice overlay layers
(§1). Those overlays are sized from platform-view bounds ignoring clip bounds (#150646,
open) and are pooled/recycled across frames. During scroll the union rect changes every
frame; a mis-sized, culled, or positionally-stale overlay drops its text while the native
control — a real `UIView`, composited by Quartz, immune to the failure — keeps rendering.
That asymmetry ("native control fine, adjacent Flutter text gone") is the signature.
[V for the slicing/overlay facts; **[H]** for the specific attribution to these frames]

The **stale white rounded slab** is the same failure in the other direction: a recycled
overlay presented with last-frame content or geometry. The engine has a documented history
of exactly this (#152053 junk-from-unflushed-pool [S]) and one open cause still live in our
version (#150646 presenting overlays whose content was culled away [V]).

**Documented usage violation feeding it.** Our vendored package's own README says
`LiquidGlassContainer` is backed by a `UiKitView`/`AppKitView` and is costlier than regular
widgets: **"DO NOT"** place it inside long scrolling lists (`ListView.builder`, `GridView`) —
it will "cause significant performance drops (jank)"; **"DO"** reserve it for static elements
— cards, headers, nav bars, FABs.
[V] <https://pub.dev/packages/cupertino_native_better>

`cupertino_native_plus` states the same rule independently: platform views "should NOT be
used inside long scrolling lists… instead use them for static elements." [S]

**We are violating that rule in exactly the frames the sweep flagged.** [V, local]
`kit/showcase_app/lib/ui/views/showcase_search_shell/showcase_search/showcase_search_view.mobile.dart:42`
returns an `AppBoxKitEdgeAwareListView`, which is a real `ListView`
(`kit/ui_library/lib/widgets/appbox_kit_edge_aware_list_view.dart:85`). Its children include
`showcase_search_filter_card_widget.dart:38,52` (`AppBoxKitNativeSlider`,
`AppBoxKitNativeRangeSlider` — the RADIUS / PRICE RANGE card) and
`showcase_search_options_section_widget.dart:33,41` (`AppBoxKitNativeSwitch` — the "Open now"
rows). Both files carry the comment "Edge treatment belongs to the enclosing
AppBoxKitEdgeAwareListView." So Defect A's sliders and switches are platform views scrolling
inside a `ListView` — the vendor's documented "DO NOT", not a judgement call.

**Ruled out for A:** flutter#**175048** ("BackdropFilter with ClipRRect leaks blur outside
rounded corners when UiKitView is present"). I fetched it: **closed, `r: fixed`**, found in
3.35/3.36, and its symptom is blur *leaking past a clip*, not text dropping. The issue body
contains no saveLayer/frame-slice/text-flicker discussion — the memory note associating
#175048 with "text inside flickers out during scroll" is **not supported by the issue text**.
[V] <https://github.com/flutter/flutter/issues/175048>

---

## 3. Defect B — toolbar pills degrade with scroll offset

Same slicing mechanism as A, one level up: the pill *labels* are Flutter text overlapping
native glass button platform views, so they live in overlays; the pill *backgrounds* are the
platform views themselves. The three observed states are *consistent with* three overlay
outcomes — this is a shape match, not a diagnosis; no frame-level overlay evidence was
gathered:

| Observed state | Overlay outcome |
|---|---|
| Full labeled pills | overlay present, correct rect |
| Bare unlabeled glyphs | overlay dropped/culled (#150646) |
| Clipped `…e` / `:dit`, overlapping backgrounds | overlay union rect stale by ≥1 frame |

[**[H]** mapping; [V] for the underlying one-overlay-per-slice + union-rect behavior, PR #54010]

Contributing rounding defect [S]: flutter#**143420** — every platform view gets a
`FlutterOverlayView` of height 1 from `roundOut` on the intersection; a widget ending at
100.1 and a view starting at 100.1 become 101 and 100, a 1px overlap at any fractional
coordinate. Subpixel scroll offsets are exactly when fractional coordinates occur, which is
why the degradation is *scroll-offset dependent*. I did not fetch this issue; treat the
"closed via engine#50637" claim as unverified.

---

## 4. Defect C — sliding lens carries duplicated icons

**Two competing mechanisms. Neither is verified. One experiment separates them.**

*Hypothesis C1 — refraction of Flutter content.* Liquid Glass warps and offsets its backdrop:
distortion is a factor in [0,1], edge pixels take maximum offset, center pixels none, with
color sampled at `fragCoord - offset` — "background pixels near glass edges can appear
displaced or duplicated." [S] <https://medium.com/@aghajari/liquid-glass-ios-effect-explanation-dabadd6414ae>
If the lens platform view samples the Flutter surface beneath it, tab icons get refracted
into a warped second copy while the overlay copy above draws normally → duplication.

*Hypothesis C2 — positionally-stale overlay.* The lens is a moving platform view. Its slice
union rect is recomputed per frame; if the overlay carries frame N-1's content while the
lens UIView is at frame N's position, the icon appears twice at two offsets. This needs no
refraction at all and is the mechanism this repo has already named ("overlay texture leak").

**Discriminating test (one build):** place a solid, opaque, Flutter-drawn block under the
lens path and slide the pill. If the lens shows a warped copy *of the block*, glass is
sampling Flutter content → C1. If the block is untouched but the icons still duplicate →
C2, and the fix is overlay geometry, not glass configuration.

**Load-bearing unknown:** whether a `UIGlassEffect` platform view in Flutter's hierarchy
samples the Flutter rendering surface at all. I found no source establishing this either
way. Do not build a fix on the assumption.

Native-side aggravator worth checking regardless [S]: **glass cannot sample other glass** —
stacking `glassEffect` inside `glassEffect` produces artifacts; uncoordinated glass outside a
`GlassEffectContainer` "may have inconsistent appearance." If our lens and the tab-bar
background are two separate glass views rather than one container, that is a real defect
independent of Flutter. <https://dev.to/arshtechpro/understanding-glasseffectcontainer-in-ios-26-2n8p>

---

## 5. Ranked candidate fixes

**1 — Stop putting platform-view-backed glass inside scrolling content (A, B).**
This is a **confirmed rule violation, not a proposal**: the Defect A sliders and switches
are platform views inside a real `ListView` (see §2 for exact files and lines), which the
vendored package's own README marks "DO NOT".
Change: extend the existing scroll-demotion rule in `docs/liquid-glass-allowlist.md` so
in-scroll rows use Flutter-drawn controls and promote to native only when static/settled;
keep native for headers, nav bars, FABs, static cards.
Effect: removes the slice/overlay path for the affected rows entirely — no overlay, no
label drop, no stale slab. Risk: fidelity loss in scroll; needs a promote/demote handoff
that does not flash. Evidence: **confirmed by two independent package docs** ([V] vendored
`cupertino_native_better`, [S] `cupertino_native_plus`) **plus a local code check** [V],
and it is the only fix that addresses the *open* engine bug (#150646) rather than waiting
on it.

**2 — Reduce slice count: never let Flutter text overlap a native control's rect (A, B).**
Change: lay labels out in rows/columns that do not intersect the platform view bounds
(label above/beside, not overlapping); give each native control its own `RepaintBoundary`
and avoid straddling widgets.
Effect: with no intersection there is no overlay to lose. Risk: layout churn; the 1px
`roundOut` overlap (#143420 [S]) means "adjacent" still needs a real gap, not 0px.
Evidence: **strong mechanism** ([V] PR #54010 — one overlay per slice; [V] #150646), but no
source states this as a prescribed workaround → **partly speculative**.

**3 — Run the C1/C2 discriminating test before touching the lens (C).**
Change: none yet — the opaque-block probe in §4.
Effect: converts C from two hypotheses to one. Risk: none. Evidence: required because the
"glass samples Flutter's layer" premise is **unverified**, and the two mechanisms have
opposite fixes.

**4 — Remove `BackdropFilter`/`Opacity`/`saveLayer` from any subtree containing a platform
view (A, B).** Change: replace with opaque or tinted containers.
Effect: fewer offscreen passes interacting with slicing. Risk: visual change. Evidence:
[V] iOS docs — "`ShaderMask` and `ColorFiltered` are not supported. `BackdropFilter` is
supported, but there are some limitations"; [S] #126353 Impeller BackdropFilter regression
(16ms vs Skia 6ms raster). Lower rank: it addresses a real limitation but the sweep does not
show blur bleed, so it is unlikely to be *the* cause here.

**5 — Wrap co-located glass in one `GlassEffectContainer` / `UIGlassContainerEffect`, and
never nest glass in glass (C).** Effect: coordinated appearance, no glass-sampling-glass
artifacts. Risk: layout coupling. Evidence: [S] only — do after fix 3.

**6 — Placeholder-texture swap during animation (A, B, C).** Per iOS docs [V]: "use a
placeholder texture while an animation is happening in Dart… consider taking a screenshot of
the native view and rendering it as a texture." Effect: no live platform view during scroll
→ no slicing. Risk: **high** — iOS 26 glass continuously samples its backdrop, so a snapshot
looks visibly dead, and the BackdropFilter design doc notes snapshotting fails for some view
types. Listed for completeness; fix 1 achieves the same end more cleanly.

---

## 6. Ruled out / do not try

- **Disabling Impeller (`FLTEnableImpeller=false`).** Three separate searches dangled this.
  It is dead on iOS. [V] <https://docs.flutter.dev/perf/impeller> states verbatim:
  "Impeller is the only supported rendering engine on iOS with no ability to switch to
  Skia." `FLTEnableImpeller` in `Info.plist` is documented for **macOS only**, and
  `--no-enable-impeller` for Android/macOS/Linux/Windows — **neither is offered on iOS**.
  #163498's "3.27.4 Impeller disabled ✓" row reflects a toggle that no longer exists for us.
  So the regression is Impeller-gated *and* has no escape hatch on our platform.
- **Registering `CNTabBarRouteObserver` / `CNSheetGeometryProbe` / `autoHideOnModal`.**
  The vendor calls these mandatory ("without it the dynamic z-order/halo containment never
  engages") [V], but **this repo already wires all three** — see
  `kit/ui_library/test/kit/widgets/appbox_kit_tab_bar_single_hide_authority_test.dart`,
  `.../appbox_kit_scroll_occlusion_gate_test.dart`, `.../appbox_kit_native_sheet_test.dart`.
  Already done; not a candidate fix.
- **Chasing flutter#175048.** Closed `r: fixed` and about blur escaping a clip, not text
  drops. [V] Also: the memory note tying it to scroll text-flicker is unsupported — fix the
  note.
- **Chasing engine PR #54056 / layer-pool flush.** Merged mid-2024, already in our 3.44.9
  engine. [S]
- **Waiting for upstream Cupertino Liquid Glass.** flutter#170310: the team stated
  2025-06-10 they "are not developing the new Apple'26 UI design features in the Cupertino
  library right now" and are not accepting contributions; 2025-07-29 they decided to decouple
  Material/Cupertino into standalone packages first. P3, no milestone.
  [V] <https://github.com/flutter/flutter/issues/170310>
- **Upgrading Flutter to pick up a fix.** 3.44.0's platform-view entries are #182643
  (`ClipRSuperellipse` on backdrop filter over platform view) and #183274 (admob banner
  scroll) — neither touches overlay slicing. We are already on 3.44.9. [V] 3.44.0 notes.
- **`RepaintBoundary` to snapshot around the problem.** [S] flutter#163639 —
  `RepaintBoundary` does not capture platform views on iOS; they come out blank.

## 7. Open questions to resolve locally

1. C1 vs C2 (§4 probe) — blocks any lens fix.
2. ~~Do the affected slider/switch rows sit in a scrollable?~~ **Resolved: yes** — see §2.
3. Does any label's layout rect intersect a platform view rect (including the 1px
   `roundOut` margin)? Drives fix 2. Left to task #3's code-path mapping.
4. Defect B's toolbar: are the pills also inside a scrollable, and are the pill labels
   Flutter-drawn or native? Determines whether fix 1 covers B as well as A.
