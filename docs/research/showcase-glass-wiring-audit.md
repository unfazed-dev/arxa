# Showcase glass / native-chrome wiring audit

**Scope:** how `kit/showcase_app` wires native Liquid Glass chrome from the vendored
`kit/ui_library/vendor/cupertino_native_better` fork and the appbox kit widgets.
**Method:** static read of the tree at `HEAD = 34c53b0`. Diagnosis only — no fixes, no edits.
**Caveat:** the `rewire-*` agents are refactoring the vendor concurrently in separate
worktrees. Every line number below is from this checkout at `34c53b0` and may drift.

---

## 1. Platform-view-backed surfaces reachable from showcase

Everything native here is an iOS `UiKitView` (macOS `AppKitView`) under hybrid
composition, i.e. a real native view composited **above** the Flutter scene.

| Surface | Kit widget | Vendor view | Mounted at |
|---|---|---|---|
| Tab bar | `AppBoxKitNativeTabBar` → `CNTabBar` | `CupertinoNativeTabBar` | `appbox_kit_tab_bar.dart:100-123` |
| Glass card | `AppBoxKitGlassCard` → `CNGlassEffect` | glass container | `appbox_kit_glass_card.dart:66-73` |
| Icon button | `AppBoxKitNativeIconButton` → `CNButton.icon` | button | `appbox_kit_native_icon_button.dart:80-100` |
| Button / CTA | `AppBoxKitNativeButton` → `CNButton` | button | `appbox_kit_native_button.dart:92` |
| FAB | `AppBoxKitNativeFab` → `CNButton` (prominentGlass) | button | `appbox_kit_native_fab.dart:96-105` |
| Split button | `AppBoxKitNativeSplitButton` | button | `appbox_kit_native_split_button.dart:133-142` |
| Popup menu | `AppBoxKitNativePopupMenu` → `CNPopupMenuButton` | popup menu | `appbox_kit_native_popup_menu.dart:199` (gated at `:198`) |
| Segmented control | `AppBoxKitNativeSegmentedControl` → `CNSegmentedControl` | segmented control | `appbox_kit_native_segmented_control.dart:62` |
| Toolbar | `AppBoxKitNativeToolbar` | buttons ×N | `appbox_kit_native_toolbar.dart:150-159` |
| FAB menu | `AppBoxKitNativeFabMenu` | buttons ×N | `appbox_kit_native_fab_menu.dart:176` |
| Glass button group | `CNGlassButtonGroup` | group | `glass_button_group.dart:263-278` |

**Creation / disposal triggers.** A platform view is created when its subtree is first
built with `PlatformViewGuard.isReady == true` and `_creationParams != null`, and it is
**destroyed and re-created whenever the widget returns a non-platform-view placeholder
from `build()` and then swaps back.** Sections 2 and 4 are entirely about how often that
placeholder→view swap fires unnecessarily.

**Host tree, root → tab bar:**

```
main.dart → MaterialApp.router (navigatorObservers: () => [CNTransitionObserver()])
  → ShowcaseApplicationHubView                    showcase_application_hub_view.dart:37
    → ShowcaseApplicationTabHostWidget            showcase_application_hub_view.mobile.dart:36
      → StackedTabsRouter.builder                 showcase_application_tab_host_widget.dart:33
        → Scaffold(extendBody: true)                                            :40
           body:   AppBoxKitAnimatedTabStack(children: 4 tab shells)            :56
           bottomNavigationBar: AppBoxKitNativeTabBar                           :66
```

---

## 2. Rebuild churn — the `future:`-created-in-`build()` family

**This is the highest-severity class of finding in the audit.** Five vendor components
construct their `Future` inline in `build()`. `FutureBuilder.didUpdateWidget` compares
`oldWidget.future != widget.future` by identity; a fresh `Future` object every rebuild
therefore **resets the snapshot to `hasData == false` on every single rebuild**, which
returns a bare `SizedBox` — the `UiKitView` is removed from the tree, the native view is
torn down, and a new one is allocated one microtask later.

| Component | Line | Placeholder returned |
|---|---|---|
| `icon.dart` (imageAsset) | `:138-139` | `SizedBox` `:144` |
| `icon.dart` (customIcon) | `:167-168` | `SizedBox` `:171` |
| `button.dart` (imageAsset) | `:384-385` | `SizedBox` `:389` |
| `button.dart` (customIcon) | `:412-413` | `SizedBox` `:417` |
| `glass_button_group.dart` | `:266-277` (`Future.wait` fan-out over N buttons) | `:279` |
| `popup_menu_button.dart` | `:362-364` **nested inside** `:369-373` | `:367` and `:376` |

`popup_menu_button.dart` is the worst case: two stacked `FutureBuilder`s, so a rebuild
costs **two** placeholder→view swaps. The `ValueKey` at `:363` does not rescue it — the
key stabilises the *element*, but the identity-changed `future` still resets the snapshot.

The work redone on each of those swaps is not trivial. `iconDataToImageBytes`
(`icon_renderer.dart:159-178`) rasterises the glyph through a `TextPainter` →
`Picture` → `Image` → PNG encode, **with no cache anywhere in the file**.
`resolveAssetPathForPixelRatio` (`:79-129`) probes the asset bundle across up to six
density buckets via `rootBundle.load` (`:132-139`); `rootBundle` caches bytes, so the
repeat cost there is the async hop rather than I/O.

### 2a. `AppBoxKitNativeIconButton` never takes the cheap SF-Symbol path

`appbox_kit_native_icon_button.dart:89` passes `customIcon: icon` **unconditionally**,
including when `sfSymbol != null` (which it null-guards two lines earlier at `:82`).
`CNButton`'s documented priority is `imageAsset > customIcon > icon`, so a non-null
`customIcon` **shadows** the SF Symbol and forces the `button.dart:412` rasterisation
branch every time.

This is a deviation from the library's own established guard, not an ambiguity. Three
sibling call sites get it right, one with an explicit warning comment:

- `appbox_kit_native_fab.dart:96` — `final customIcon = sfSymbol == null ? icon : null;`
  preceded by `:80-81` *"Avoids customIcon shadowing the native glyph (CNButton priority:
  imageAsset > customIcon > icon)."*
- `appbox_kit_native_split_button.dart:133` — `customIcon: sfSymbol == null ? icon : null`
- `appbox_kit_native_toolbar.dart:150,159` — same guard

**Severity: high.** Icon buttons are the most numerous native surface in the app (app-bar
trailing actions, snackbar row, cards), and every one of them pays PNG rasterisation plus
a platform-view create/dispose cycle on each rebuild.

### 2b. Debug-only startup swap

`PlatformViewGuard` (`platform_view_guard.dart:55-82`) is `_immediatelyReady` under
`kReleaseMode`, but in **debug** it withholds readiness for 500 ms. Every native surface
renders its Flutter fallback for the first half-second and then swaps.
`CNTabBar` does the same independently at `tab_bar.dart:512-519` (fallback while
`_creationParams == null`, which `_scheduleNativePreparation` fills asynchronously from
`initState` `:355`).

**Severity: low, but it is a decoy** — this produces a startup flicker that does not
reproduce in release. Rule it out before chasing it.

---

## 3. Notes shell — a stated negative, plus the real mechanism

### 3a. Structural unmount is ruled out

The notes children are **nested routes**, not root-navigator pushes:

```
AdaptiveRoute(page: ShowcaseApplicationHubView, path: '/', children: [   app.dart
  AdaptiveRoute(page: ShowcaseNotesShellView, path: 'notes', children: [
    AdaptiveRoute(page: ShowcaseNotesView,       path: '', initial: true),
    AdaptiveRoute(page: ShowcaseNotesFolderView, path: 'folder/:id'),
    AdaptiveRoute(page: ShowcaseNoteEditorView,  path: 'note/:id'),
  ]),
])
```

`ShowcaseNotesShellViewMobile` returns a bare `const NestedRouter()`
(`showcase_notes_shell_view.mobile.dart:37`); the only push in the subtree is
`context.router.pushNamed(...)` at `showcase_notes_folder_view.mobile.dart:222`, which
targets the nested router. The tab bar lives **above** that in the hub `Scaffold`'s
`bottomNavigationBar` (`showcase_application_tab_host_widget.dart:66`), so it is never in
the subtree being navigated.

**The tab bar does not structurally unmount when navigating inside Notes.** Anything that
makes it disappear is a suppression path, not a lifecycle event.

### 3b. The actual mechanism: a global transition counter fed by per-scope observers

`CNTransitionObserver._activeTransitions` is **`static`** (`transition_observer.dart:51`),
but `_transitionCount` is a **per-instance** field (`:40`).

Stacked instantiates one observer per navigator scope. `nested_router.dart:93` does
`_navigatorObservers = _inheritableObserversBuilder();` with `inheritNavigatorObservers`
defaulting to `true` (`:22`), and `stacked_tabs_router.dart:132` does the same. The root
builder is `() => [CNTransitionObserver()]` (`main.dart`), so **each nested scope calls it
and gets a fresh instance** — the tabs router, each of the four tab shells, and the notes
nested router.

Two consequences:

1. **A push inside the Notes tab increments the global counter.**
   `AppBoxKitNativeChromeGate._applyVisibility` hides on
   `CNTransitionObserver.activeTransitions.value > 0`
   (`appbox_kit_native_chrome_gate.dart:186-187`) with **no mount-scope guard whatsoever**
   — note the contrast with the modal check on the same line pair, which *does* compare
   against the `_mountDepth` snapshot taken at `:136`. So an in-tab push hides the chrome
   of **every gated surface in the whole app**, across all four tabs, including the tab bar
   (`appbox_kit_tab_bar.dart:100`).

2. **The native suppression calls can desync.** The `_transitionCount == 1` guard at
   `transition_observer.dart:106` that fires `CupertinoNativePlatform.instance.beginTransition()`
   is per-instance. Two scopes transitioning concurrently issue two independent
   begin/end pairs; whichever ends first releases native glass suppression while the other
   transition is still running. **Plausible cause of the obscure/glass glitch.**

**Watchdog cost.** `_scheduleEndTransition` budgets `transitionDuration + 1000 ms`
(`:158-162`), with a 350 ms fallback for non-animated routes (`:170`). A missed status
callback — the `modalRoute.offstage` early-return at `:144-146` is exactly that case, and
is what `6b6dc8c` patched — leaves all chrome hidden for **up to ~1.35 s**.

**Severity: high.** This is the most direct explanation for "tab bar disappears while
navigating".

### 3c. Three independent hide paths stacked on one tab bar

The tab bar can be hidden by three mechanisms that observe different signals with
different timing and no coordination:

| # | Mechanism | Signal | Visual |
|---|---|---|---|
| 1 | `AppBoxKitNativeChromeGate` | global `activeTransitions > 0` | fade + scale 0.95→1.0, 160 ms out / 180 ms in (`chrome_gate.dart:190-206, 237-246`) |
| 2 | `CNTabBar._modalUp` | `anyModalDepth > 0` | returns bare `SizedBox` — **instant hard cut**, no animation (`tab_bar.dart:536-542`) |
| 3 | `CNTabBar._pageTransitioning` | route `secondaryAnimation` status | `IndexedStack` swap to `SizedBox` (`tab_bar.dart:566-575`) |

Paths 2 and 3 are `setState` calls at `tab_bar.dart:364` and `:375`. A 160 ms fade (path 1)
racing an instant swap (path 2) produces **fade-then-pop**.

**Severity: high** — visual desync is near-guaranteed whenever two of the three fire.

### 3d. Internal contradiction: fade over platform views

`showcase_application_tab_host_widget.dart:53-54` states the tab transition is
*"slide-only: fade ghosts platform views on native-chrome tabs (flutter#24164/#148639)"*.
The implementation it names does fade: `appbox_kit_animated_tab_stack.dart:277` and `:281`
wrap the exiting and incoming layers in `FadeTransition`. The file's own doc at `:60`
repeats the warning against opacity-animating platform-view subtrees.

`appbox_kit_native_chrome_gate.dart:239-245` likewise wraps native chrome in
`FadeTransition` + `ScaleTransition`, while its doc at `:72` concedes opacity is only
*"reliably"* applied to platform views under hybrid composition and the scale is not.

Whether this is a deliberate revision (commit `20616f2` crossfades the exiting tab layer)
or drift, **the comments and the code disagree**, and the disagreement sits exactly where
the one-frame-pop symptoms are reported. **Severity: medium**, flagged for the Stage 2
refactor to reconcile rather than as a proven defect.

---

## 4. Obscure / scroll-edge — a tree-shape flip at the threshold

*Rewritten after the team lead relayed the user-confirmed symptom: the transition trigger
is **visibly a hard flip**, and lists using it "break all the time" while scrolling.*

### 4a. The driving mechanism: pure Dart, zero channel traffic

The hypothesis on the table was that scroll-edge state is pushed to native over the method
channel as a threshold boolean. **It is not sent at all.** The scroll-edge effect never
talks to the native side:

- `grep` for `invokeMethod` with scroll/edge/obscure across `kit/ui_library/lib` and the
  vendor lib returns **nothing**.
- `scrollEdgeAppearance` *is* used natively, but only inside
  `CupertinoTabBarPlatformView.swift` (`:224, :357, :692, :804, :946, :950, :954`) to style
  the **tab bar**. Nothing in the list/content path uses it.

`AppBoxKitScrollEdgeEffect` (`appbox_kit_scroll_edge_effect.dart:108-192`) is a
**Flutter-side emulation**: it listens to the enclosing `ScrollPosition`
(`:118-121`), and `_recompute` (`:133-166`) calls `viewport.getOffsetToReveal(...)` (`:153-155`)
per scroll notification to derive a coverage fraction `t`, then paints its own
`ImageFilter.blur` + `Opacity` (`:174-188`). **No native bar observes a `UIScrollView`.**

### 4b. Why it is a *visible hard flip* — the tree shape changes at t = 0

This is the mechanism behind the reported symptom, and it is not a tuning problem:

```dart
Widget build(BuildContext context) {
  final t = _t;
  if (t == 0.0) return widget.child;        // :171  ← raw child
  ...
  return IgnorePointer(                     // :180  ← four extra widgets
    child: Opacity(                         // :182
      child: ClipRect(                      // :184
        child: ImageFiltered(               // :185
          imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: widget.child,
```

At `t == 0` the child is returned **raw**; at any `t > 0` it is returned wrapped in four
new widgets. Flutter matches elements by widget type and position, so inserting four levels
means the child's `Element` is **not** reused — **the whole subtree is unmounted and
rebuilt.** Any `UiKitView` inside it is destroyed and re-created at that instant. That is
the visible hard flip.

### 4c. No hysteresis — a single threshold with no dead band

`:163` quantises with **one** boundary in both directions:

```dart
t = t <= 0.02 ? 0.0 : (t >= 0.98 ? 1.0 : (t * 50).roundToDouble() / 50);
```

There is no separate enter/exit threshold. A row resting near `t ≈ 0.02` — exactly where a
list item sits as it approaches pinned chrome — oscillates across the boundary on ordinary
scroll jitter, and **every crossing remounts the subtree and cycles the platform view**.
This is the "lists break all the time" report, and the absence of hysteresis is the reason
it is constant rather than occasional.

### 4d. Applied over native-view-bearing cards, and applied twice

The extension is attached at 10 showcase call sites. Two matter most:

- **`showcase_notes_folder_view.mobile.dart:182-183` chains it twice** —
  `.scrollEdgeEffect()` (top) then `.scrollEdgeEffect(edge: bottom, …)` — inside a lazy
  builder, per group `i`. Two nested threshold flips per row, so a crossing can remount
  through two layers.
- **`showcase_split_button_card_widget.dart:53`** wraps an `AppBoxKitGlassCard`
  (`LiquidGlassContainer`, a platform view — `appbox_kit_glass_card.dart:67`) containing an
  `AppBoxKitNativeSplitButton` (`CNButton` — `:30`). Both are platform views, both under the
  flip.

Also worth noting: `Opacity` and `ImageFiltered` are Flutter-layer operations, and under iOS
hybrid composition a `UiKitView` composites **above** the Flutter layer. The blur therefore
does not visually apply to the native content it wraps — the cost of the remount is paid
without the intended effect landing on the native parts.

### 4e. The visible artifact is the remount, not the effect

At the flip point the effect itself is imperceptible. With `t = 0.02` and the default
(non-`hard`) style, `:174-175` give `sigma = 8 × 0.02 = 0.16` and
`alpha = 1 − 0.85 × 0.02 ≈ 0.983` — a sub-pixel blur and a 1.7 % opacity change.

**Nothing about the blur or the opacity is visible at the threshold. What is visible is
exclusively the platform-view teardown and re-create.** This matters for how the finding is
read: adding hysteresis would reduce how *often* the remount fires while leaving each one
just as visible. The property that needs to hold is tree-shape stability across the
threshold, not a quieter trigger.

### 4f. First mount is a guaranteed create → destroy → create

`didChangeDependencies` schedules `addPostFrameCallback((_) => _recompute())` (`:124`), and
the first `build()` runs with `_t = 0.0`, taking the raw-child branch at `:171` — so the
platform view is created. The post-frame `_recompute` then sets `t > 0` for any card that
starts under pinned chrome, which takes the wrapped branch and remounts the subtree.

Every edge-effected card that begins its life covered therefore pays a **create → destroy →
create** cycle on first mount, before any user scroll. This is a second contributor to the
first-load flicker, independent of §2.

### 4g. The per-scroll-frame cost (secondary)

`AppBoxKitScrollOcclusionGate` (`appbox_kit_scroll_occlusion_gate.dart:131-134, 147-179`) is
a separate widget with the same listener shape, driving alpha rather than tree shape. Its
`_recompute` calls `getOffsetToReveal` (`:166`) per scroll notification — a render-tree walk
per tick — then quantises to 1/50 and `setState`s on change (`:174-178`). The quantisation
caps rebuilds at ~50 per traversal, so in isolation this is minor; it matters only because
each rebuild re-runs `build()` over a platform-view subtree and compounds with §2.

**Per-frame channel traffic:** none. `tab_bar.dart` invokes `setSelectedIndex` / `refresh`
only from discrete callbacks (`:875-887`) and search-controller changes (`:481-489`).

**Severity: high — 4b/4c is a distinct root cause, not a variant of §2.**

---

## 5. Resource hotspots

**Platform views alive on the home screen — corrected.** An earlier revision of this
document said eight. That was wrong, and the reason is worth recording:
**the `AppBoxKitNative*` prefix is a naming convention, not a platform-view marker.**
Verified per widget:

| Widget | Platform view? | Evidence |
|---|---|---|
| `AppBoxKitGlassCard` ×2 | **yes** — `LiquidGlassContainer` | `appbox_kit_glass_card.dart:67` |
| `AppBoxKitNativeSplitButton` | **yes** — `CNButton` | `appbox_kit_native_split_button.dart:133` |
| `AppBoxKitNativeIconButton` | **yes** — `CNButton.icon` | `appbox_kit_native_icon_button.dart:81` |
| `AppBoxKitNativeButton` | **yes** — `CNButton` | `appbox_kit_native_button.dart:92` |
| `AppBoxKitNativeProgress` ×2 | **no** — `CupertinoActivityIndicator` | `appbox_kit_native_progress.dart:85`; zero `CN*` matches in file |
| `AppBoxKitNativeLoadingIndicator` | **no** — `CupertinoActivityIndicator` / `LoadingIndicatorM3E` | `appbox_kit_native_loading_indicator.dart:1-3,59` |

So **five** platform views in `showcase_home_widgets/`, not eight — plus app-bar chrome, the
tab bar, and the segmented control in
`ui/widgets/common/showcase_tabs_shared/showcase_theme_mode_segmented_demo_widget.dart`
(outside the globbed directory because it is shared across tabs). No screen total is claimed.

**Multiplied across tabs.** `app.dart:4` documents `StackedTabsRouter` as an
`IndexedStack` where *"every stack stays alive"*, and `appbox_kit_animated_tab_stack.dart:239`
keeps visited tabs mounted via `Offstage`. Offstage children are not painted but **are not
unmounted**, so their platform views stay allocated. After visiting all four tabs, every
tab's native views are alive simultaneously.

Because the chrome gate's transition check is global (§3b), a single route transition
anywhere fires `setState` in **every** gate across **all** tabs at once.

**Undisposed `CurvedAnimation`.** `appbox_kit_native_chrome_gate.dart:228-232` constructs a
`CurvedAnimation` with a non-null `reverseCurve` inside `build()` and never disposes it.
Flutter ≥3.22 flags exactly this shape, because a `CurvedAnimation` with a `reverseCurve`
registers a status listener on its parent. Each rebuild would then add another listener to
the long-lived `_fade` controller. **Severity: medium — flagged, not asserted.** I read the
construction site but did not trace Flutter's listener bookkeeping to confirm accumulation;
verify against `flutter analyze` and a listener-count probe before acting.

**No SVG rasterisation path** exists in the icon pipeline. `detectImageFormat`
(`icon_renderer.dart:14-21, 48-52`) classifies SVG and hands the path to native; the
repeated raster cost is the `TextPainter`→PNG encode in `iconDataToImageBytes` (§2), not SVG.

---

## Symptom → cause map (user-confirmed symptoms, relayed by team lead)

| Confirmed symptom | Cause | Status |
|---|---|---|
| Scroll-edge trigger is a **visible hard flip**; lists "break all the time" | §4b tree-shape change at `t == 0` + §4c no hysteresis | **Mechanism identified.** Hypothesis of per-threshold channel traffic is *disproved* — there is none (§4a) |
| Tab bar hidden **only during** push/pop, returns when it settles | §3b global `activeTransitions` gate | **Matches exactly.** Gate is keyed to transition start/end, so it restores on settle. §3a rules out structural unmount |
| Flicker in **all** contexts, reproduces in **profile/release** on device | §2 future-in-`build()` + §2a forced rasterisation | **Consistent.** These are release-affecting. Only §2b (`PlatformViewGuard`'s 500 ms) is debug-only — that one decoy is now ruled out by the device repro |

The release repro is a useful discriminator: it **rules out §2b** and leaves §2/§2a and §4b
as the systemic churn sources, both of which are `kReleaseMode`-independent.

## Suspected root causes, ranked

Ranking reflects the user-confirmed symptoms relayed above; cause 2 was added and promoted
in that pass, which is why there are six.

1. **`future:` constructed inside `build()` across five vendor components** — every
   rebuild resets the snapshot, blanks to a `SizedBox`, and tears down + re-creates the
   `UiKitView`, re-rasterising the icon each time.
   `icon.dart:138,167` · `button.dart:384,412` · `glass_button_group.dart:266` ·
   `popup_menu_button.dart:362,369` (nested, double swap).
   → **flicker + slow.**

2. **Scroll-edge changes tree shape at the threshold, with no hysteresis** (§4b, §4c).
   `scroll_edge_effect.dart:171` returns the raw child at `t == 0`; `:180-188` returns it
   under four extra widgets at `t > 0`, so the subtree — and any `UiKitView` in it — is
   unmounted and re-created at every crossing. The single boundary at `:163` has no dead
   band, so a row resting near it flips on ordinary scroll jitter. The blur/opacity delta
   at that point is imperceptible (§4e), so the remount **is** the artifact. First mount
   pays a create → destroy → create cycle unconditionally (§4f).
   → **visible hard flip + "lists break all the time" + first-load flicker.**

3. **Chrome gate hides on a *global* transition counter with no mount-scope guard**, fed by
   one `CNTransitionObserver` per nested navigator scope. A push inside Notes hides chrome
   in all four tabs, including the tab bar; the watchdog can hold it hidden ~1.35 s.
   `chrome_gate.dart:186-187` · `transition_observer.dart:51,40,106,158-162` ·
   `nested_router.dart:93` · `stacked_tabs_router.dart:132`.
   → **tab bar disappears during transitions, returns on settle.**

4. **`AppBoxKitNativeIconButton:89` passes `customIcon` unconditionally**, shadowing the SF
   Symbol and forcing the rasterisation branch on the app's most numerous native surface —
   while `fab.dart:96`, `split_button.dart:133` and `toolbar.dart:150` all guard it.
   → **flicker + slow.** Highest-leverage single-line finding; it converts the §1 cost from
   "SF Symbol lookup" to "PNG encode" for most icons in the app.

5. **Three uncoordinated hide paths on the tab bar** — a 160 ms fade (chrome gate) racing an
   instant `SizedBox` swap (`tab_bar.dart:540`) and an `IndexedStack` swap (`:566`).
   → **tab bar flicker / fade-then-pop.**

6. **Per-scroll-frame `getOffsetToReveal` + up to 50 `setState`s over platform-view
   subtrees** (`scroll_occlusion_gate.dart:147-179`). Low cost alone; compounds with
   cause 1 into ~50 rasterise-and-recreate cycles per scroll traversal.
   → **slow scrolling under a pinned app bar.**

Causes 1 and 4 compound multiplicatively with cause 3: a global `setState` storm (3) ×
future-reset-per-rebuild (1) × forced rasterisation (4) means one route transition can
re-encode and re-allocate every icon button in the app. **Treat them as one cluster, not
three independent fixes.**

Cause 2 is **independent of that cluster** — it fires on scroll rather than on rebuild, and
it would remain after the cluster is addressed.

---

## Verified negatives

- Notes children are nested routes; the tab bar sits above the navigated subtree and does
  **not** structurally unmount (§3a).
- Tab bar icons use `CNSymbol(t.sfSymbol)` (`appbox_kit_tab_bar.dart:104`), so the tab bar
  itself avoids the rasterisation pipeline entirely.
- No per-frame method-channel traffic on the scroll or transition paths (§4).
- **Scroll-edge sends nothing to native** — no `invokeMethod` for scroll/edge/obscure exists;
  `scrollEdgeAppearance` is used only for the tab bar in `CupertinoTabBarPlatformView.swift`,
  never for list content (§4a).
- No SVG re-rasterisation path in the icon pipeline (§5).
- `AppBoxKitNativeProgress` and `AppBoxKitNativeLoadingIndicator` are **not** platform
  views despite the `Native` prefix (§5 table) — do not count them as glass surfaces.

## Not verified

- Runtime platform-view create/dispose counts (static read only — no instrumented run).
- Whether the `CurvedAnimation` at `chrome_gate.dart:228` actually accumulates parent
  listeners across rebuilds.
- Native-side `beginTransition`/`endTransition` bookkeeping in the Swift plugin; the
  desync in §3b-2 is inferred from the Dart side only.
- Android / M3E tiers — this audit covers the iOS Liquid Glass path.
