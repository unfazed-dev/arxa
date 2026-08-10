# Liquid Glass reappearing wrongly on back-navigation

Status: **landed**, two commits. Reported against the showcase notes shell —
"going back from a view, the liquid glass ui has a reappearing animation that is
not right". Two independent defects, one in the vendored observer and one in the
kit gate. Neither is notes-specific: both are kit-wide, so every Liquid Glass
surface appbox produces is fixed by them.

## What the user actually sees

Popping the note editor back to the folder list, the folder's glass surfaces
(search bar, list sections, FAB menu) vanish for the slide and then **zoom back
in** — scale 0.95 → 1.0 with a fade — landing after the page has already
stopped moving.

## Defect 1 — the pop never timed itself against the pop

`CNTransitionObserver` scheduled the end of its hide window on the wrong route:

```dart
didPush(route, previousRoute) => _scheduleEndTransition(route);         // animating 0→1 ✓
didPop (route, previousRoute) => _scheduleEndTransition(previousRoute);  // settled at 1.0 ✗
```

On a pop, `previousRoute` is the route being *revealed*. Its own animation
finished when it was pushed, so `status == completed`, the in-flight branch was
skipped, and the end came from the "no animation" fallback — a blind
`Future.delayed(350ms)`. A Cupertino slide is **500 ms**
(`CupertinoRouteTransitionMixin.kTransitionDuration`, `cupertino/route.dart:155`).

| t | before |
|---|---|
| 0 ms | `didPop` → counter 1 → revealed route's glass hides |
| 350 ms | blind timer → counter 0 → glass starts coming back |
| 500 ms | the route actually stops sliding |
| 530 ms | glass finishes appearing |

So glass was restored **over a page still in motion**. Fixed by scheduling on
the outgoing `route`, whose controller really is running 1→0 — which also makes
the window duration-agnostic instead of pinned to a constant that happened to be
wrong.

**`didRemove` deliberately still passes `previousRoute`.** A remove is not
animated, so it lands on the 350 ms fallback either way and the fallback is
harmless there — retargeting it would change nothing except the risk. The
push/pop symmetry argument above is about the two *animated* cases only; this
asymmetry is intentional, not an oversight left behind.

Second-order fix in the same function: `dismissed` now counts as settled
alongside `completed`. Scheduling on the outgoing route means a zero-duration
pop arrives already dismissed, and treating that as in-flight would attach a
listener nothing fires, leaving the watchdog (`transitionDuration + 1000 ms`) to
hide chrome for a full second after an instant pop.

**Proved by mutation.** The new mid-pop probe samples at 400 ms into a 500 ms
pop. Reverted to `previousRoute` it fails with `Expected: greater than <0>,
Actual: <0>`. The three pre-existing observer tests pass *under that mutation* —
they only asserted `1 → pumpAndSettle → 0`, which the blind timer satisfies
happily. Only a mid-pop sample can tell the two apart.

## Defect 2 — the gate animated alpha over a platform view

`AppBoxKitNativeChromeGate` wrapped its child in `FadeTransition` +
`ScaleTransition` (160 ms out, 180 ms back). That is the zoom. Four independent
authorities say it is wrong, including the one the old code cited:

1. **Apple**, WWDC25 #284, verbatim: *"Always prefer setting the effect property
   over the **alpha** to ensure that the glass dematerializes or materializes
   with the appropriate animation."* And #219: *"Instead of **fading**, Liquid
   Glass objects materialize in and out by gradually modulating the light
   bending and lensing."* The old code cited `effect = nil` as its sanction, but
   that API's documented purpose is **overlap avoidance** (Maps hiding buttons
   when a sheet expands), not transition sequencing — a misappropriated
   citation. We cannot reach `effect` from Dart, so the honest fallback is no
   animation, not the substitute Apple explicitly names as wrong.
2. **This repo, simulator-verified.** `docs/research/flutter-platform-view-best-practices.md`
   §3.2 **[R]**: *"animating opacity across a platform-view subtree is the
   expensive mistake"*; recommendation 3: *"Do not opacity-animate any subtree
   containing a platform view… Fade forces per-frame native layer mutations and
   leaves ghosting UIViews."* The gate violated the repo's own written finding.
3. **Flutter, open bugs.** flutter#93757 (`FadeTransition` does not apply to
   hybrid-composition platform views) and flutter#24164 (an opacity layer
   spanning a platform view splits into two groups) — both OPEN, no merged fix.
4. **The vendored package.** Its own `autoHideOnPageTransition` is an
   `IndexedStack` index flip with an explicit "no recreate animation"
   rationale; `ModalHideMixin` restores with a plain `setState` — no controller,
   no duration in the file.

**Fix:** both edges are now a single-frame `IndexedStack` index flip.

`showDuration` / `hideDuration` were **removed**, not defaulted to zero —
silently ignoring a caller's `showDuration: 300` is worse than not offering it.
No caller passed either. `hideDuration: Duration.zero` also existed so a fade
could not bleed through a *blur* scrim; going instant satisfies that constraint
automatically, so the parameter's reason to exist is gone, not just its value.

### It was written down, pointing the wrong way

`appbox_kit_tab_bar.dart:102` already recorded this artifact. The vendor's
*instant* `autoHideOnPageTransition` was turned **off** because it fought the
gate's fade — "the instant swap blanks the bar in frame one while the gate is
still fading something already invisible", named there as the **"fade-then-pop
artifact"**. The instant behaviour was disabled to protect the fade; the fade
was the defect. Both now agree, and the flag stays off purely for
single-authority hygiene.

## Why `IndexedStack`, and the leak question

`RenderIndexedStack` (`rendering/stack.dart:768`) overrides `paintStack`,
`hitTestChildren` and `visitChildrenForSemantics` — but **not** `performLayout`
or `computeDryLayout`, so it inherits `RenderStack`'s all-children layout. One
fact buys everything the gate needs: the view leaves the layer tree, its element
stays mounted, its footprint cannot collapse, nothing animates, and the old
`IgnorePointer` becomes redundant.

**flutter#148639 "Memory leak with IndexedStack containing a UiKitView" (OPEN)
does not indict this.** Maintainer diagnosis (`jason-simmons`): iOS defers
deleting platform views until a frame is submitted *containing* a platform-view
layer; with none painted, `HasPlatformViewThisOrNextFrame` is false, the raster
thread merger never engages, `SubmitFrame` is not called, and disposed views sit
in `views_to_dispose_`. The trigger is **"no platform view is painted while
views are being disposed"** — not `IndexedStack`. `Opacity(0)`,
`Offstage(true)` and a non-selected index are *identical* on this axis (all lay
out, none paint), so no hide mechanism avoids it; skipping paint IS the
requirement. The gate's window is bounded (the next restore drains the queue),
unlike the issue's repro which churns views inside a permanently hidden branch.
It is a reason to keep the hidden window **short** — which both fixes do.

**Real constraint that does apply:** flutter#182303 (OPEN) — changing an
`IndexedStack`'s child-list length or order disposes and re-creates subsequent
children *even with stable keys*. The gate's list is a fixed 2-slot literal;
vary `index`, never the list. Commented at the call site.

**Defect found while testing:** `IndexedStack` defaults to
`AlignmentDirectional.topStart` and asserts on a missing `Directionality`
ancestor. The gate wraps leaf glass tiers inside 13 kit widgets and must not
impose a new ancestor requirement, so it passes `Alignment.topLeft`. Safe
because the placeholder is 0×0, making the real child the sizing child at the
origin under any alignment.

## Corrected in passing

`appbox_kit_lazy_indexed_stack.dart` carried *"IndexedStack unmounts its
offstage children (verified in 3.44)"*. It does not — the gate's own test
toggles five times and still sees exactly one `initState`. The observation
behind that comment was real but the cause was wrong: that widget grows its
children list lazily, which is flutter#182303. Comment corrected; the widget's
behaviour is untouched.

## Verification, and what it cannot prove

| | |
|---|---|
| `kit/ui_library` | **287 / 287** |
| `kit/showcase_app` | **119 / 119** |
| `vendor/cupertino_native_better` | **118 / 118** |
| `flutter analyze` | clean in all three |

Headless tests cannot see native compositing. What they *do* pin: the counter
stays > 0 for the whole real pop; no `FadeTransition` / `ScaleTransition` /
`Opacity` exists anywhere under the gate; hide and restore each complete in one
frame and are stable across a further 400 ms; the child is simultaneously
**not painted** (default finder finds nothing) and **still mounted**
(`skipOffstage: false` finds it); and five hide/show cycles cost exactly one
`initState` — that `initState` count is the reparenting guard, *not* the node
count beside it, which an `IndexedStack` holds constant for structural reasons
whether or not the invariant survives.

One test states the contract without naming `IndexedStack` at all (unpainted +
mounted + same footprint + same instance), so a future swap of the hide
mechanism cannot quietly take the guarantee with it — the rest of the file reads
the index, which a refactor would rewrite.

**Needs a device:** that the zoom is gone and glass now simply *is there* when
the route settles. That is the reported symptom and only eyes can close it.

---

# Round 2 — device feedback: push fine, pop still wrong

Round 1's two fixes were correct and are kept, but they were not the whole
story. Device report: pushing folders → folder list looks right; **popping back
still shows glass animating in.** That asymmetry is the entire clue, and it
falsified two more theories before landing.

**Falsified by measurement, not argument:**

1. *"The covered route is torn down, so its platform views re-init on the way
   back."* A probe pushing an opaque route over a gate and settling it showed
   `init=1 dispose=0` throughout, gate count constant, and the gate already at
   index 0 (hidden) on pop frame 1. The in-repo claim at
   `appbox_kit_chrome_gate_transition_scope_test.dart:147` ("the Overlay …
   disposes the gate") did not reproduce.
2. *"The `.wake()` stagger replays on reveal."* `AppBoxKitMotionScope` drives
   wake from `ModalRoute.of(context)?.animation` — the revealed route's OWN
   animation, which sits at 1.0 and never moves while the route above it pops.

## The actual cause: glass was being re-established, natively

`LiquidGlassContainerView.swift:280` (before):

```swift
@ViewBuilder
func applyConditionalGlassEffectForContainer<S: Shape>(isTransitioning: Bool, glass: Glass, shape: S) -> some View {
  if isTransitioning { self.background(shape.fill(...)) }
  else               { self.glassEffect(glass, in: shape) }
}
```

A `@ViewBuilder` if/else makes the arms structurally distinct
(`_ConditionalContent`). Flipping `isTransitioning` back tears one down and
inserts the other, applying `.glassEffect` **afresh** — and establishing glass
materializes with an animation by Apple's design. The flag is driven by the Dart
observer's `endTransition()`. On a push that fires while the route is still
covered, so nobody sees it; on a **pop** it fires exactly as the revealed route
becomes visible. Four `AppBoxKitListSection`s on the folders view, all at once.

**Own goal, stated plainly:** round 1's D1 moved `endTransition()` from 350 ms
(mid-slide, partly masked by motion) to ~500 ms (precisely at settle, fully in
view). D1 is correct on its own terms, but it made *this* artifact more
conspicuous.

### Fix A (Dart) — single hide authority

`CNTransitionObserver` no longer calls the native
`beginTransition`/`endTransition`. Their only consumers are three views that swap
glass for a flat fill. This file already documented why that authority is the
weaker one: a hybrid-composition platform view *"can't be tinted out of a leak:
it must leave the frame's layer tree"* — which `AppBoxKitNativeChromeGate` does
and de-tinting cannot. Same call as C5 in `appbox_kit_tab_bar.dart`. Per-view
`setTransitioning` (Issue #29 halo containment) is a separate channel and is
untouched.

### Fix B (Swift) — constant structure, and opt out of materialize

```swift
self.glassEffect(isTransitioning ? .identity : glass, in: shape)
    .glassEffectTransition(.identity)
```

Both forms verified against Apple's DocC JSON, because search engines are
actively wrong here: WebSearch's AI overview invented a
`glassEffect(_:in:isEnabled:)` overload across three separate queries. **No such
overload exists** — the only signature is `glassEffect(Glass, in: some Shape)`,
and the `isenabled:` doc URL 404s. `Glass` has exactly `.regular`, `.clear`,
`.identity`, so passing `.identity` as a *value* keeps the modifier at a
constant structural position and no branch swap can occur.
`glassEffectTransition(GlassEffectTransition)` is real and takes one argument;
`GlassEffectTransition` has exactly `.identity`, `.matchedGeometry`,
`.materialize` — Apple's own name for the symptom.

Fix B matters beyond the branch swap: it also covers the trigger Dart cannot
see. The engine detaches a platform view with `removeFromSuperview` the frame it
stops being painted and `addSubview`s the **same instance** back when painting
resumes (`FlutterPlatformViewsController.mm`, `performSubmit:` — EXPLICIT). So
the view is effectively new to the hierarchy on every transition. Whether *that*
alone replays the materialize is **not documented** anywhere Apple publishes;
`glassEffectTransition(.identity)` makes the question moot.

Corroboration that the residual is real: `native_liquid_glass#9` hoisted a glass
view out of the routed subtree into an app-level overlay and the flash
persisted — *"the problem may be related to the UiKitView/platform view
composition path itself rather than only widget tree placement."* So relocating
the widget is not a fix; suppressing the transition is.

## Verification limits — read before trusting the green

Fix A's runtime effect is **not** headlessly testable: the old calls were guarded
by `Platform.isIOS`, false under the test host, so a "no method call was made"
assertion passes identically before and after. It is pinned by a source-level
guard instead (with a control that fails if the scanned region moves).

Fix B is Swift. **No Dart test exercises it at all** — it is verified only by
compiling against the iOS 26.5 SDK. Whether it removes the artifact is a device
question.
