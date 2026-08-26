# Liquid Glass reappearing wrongly on back-navigation

Status: **landed**, two commits. Reported against the showcase notes shell —
"going back from a view, the liquid glass ui has a reappearing animation that is
not right". Two independent defects, one in the vendored observer and one in the
kit gate. Neither is notes-specific: both are kit-wide, so every Liquid Glass
surface arxa produces is fixed by them.

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

`ArxaKitNativeChromeGate` wrapped its child in `FadeTransition` +
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

`arxa_kit_tab_bar.dart:102` already recorded this artifact. The vendor's
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

`arxa_kit_lazy_indexed_stack.dart` carried *"IndexedStack unmounts its
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
   `arxa_kit_chrome_gate_transition_scope_test.dart:147` ("the Overlay …
   disposes the gate") did not reproduce.
2. *"The `.wake()` stagger replays on reveal."* `ArxaKitMotionScope` drives
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
becomes visible. Four `ArxaKitListSection`s on the folders view, all at once.

**Own goal, stated plainly:** round 1's D1 moved `endTransition()` from 350 ms
(mid-slide, partly masked by motion) to ~500 ms (precisely at settle, fully in
view). D1 is correct on its own terms, but it made *this* artifact more
conspicuous.

### Fix A (Dart) — single hide authority

`CNTransitionObserver` no longer calls the native
`beginTransition`/`endTransition`. Their only consumers are three views that swap
glass for a flat fill. This file already documented why that authority is the
weaker one: a hybrid-composition platform view *"can't be tinted out of a leak:
it must leave the frame's layer tree"* — which `ArxaKitNativeChromeGate` does
and de-tinting cannot. Same call as C5 in `arxa_kit_tab_bar.dart`. Per-view
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
compiling against the iOS 26.5 SDK (`flutter build ios --simulator` succeeds,
which is what proves `Glass.identity` and `glassEffectTransition` exist as
used). Whether it removes the artifact is a device question.

Also note Fix B's `isTransitioning` ternary is **not** exercised by ordinary
navigation once Fix A lands — the flag is only reachable via
`CNTransitionHelper`. It is defense-in-depth, not a live path.

## The other two instances of this pattern

`CupertinoPopupMenuButtonPlatformView.swift:666,669` does the same thing in UIKit
form (`config = .glass()` vs `.tinted()`), and `ArxaKitNativePopupMenu` sits in
the folders view app bar — the same broken screen. It needed no separate fix:
its `isTransitioning` is set *only* by the NotificationCenter observer of the
global flag, which Fix A stops posting, so it now always takes `.glass()`. (Its
per-view `setTransitioning` channel call is unrelated — that drives
`applyTransitionContainment`, the Issue #29 halo clipping.)
`FloatingIslandPlatformView.swift:247` has the pattern too but `CNFloatingIsland`
is not used by the kit, so it is left alone.

## If it STILL happens on device

That is informative, not a failure. It would mean `glassEffectTransition(.identity)`
does not govern hierarchy re-insertion, so the remaining trigger is the engine's
`removeFromSuperview`/`addSubview` cycle itself. The next lever is then **not
another native tweak** — it is to stop detaching the view at all: keep the
revealed route painted through the pop (non-opaque route, or not hiding the
route being revealed), and accept whatever misregistration that costs.

Already eliminated as a lever: moving the platform view out of the routed
subtree. `native_liquid_glass#9` tried exactly that via an app-level overlay and
the flash persisted — *"the problem may be related to the UiKitView/platform view
composition path itself rather than only widget tree placement."*

---

# Round 3 — device says Fix B failed, and that falsifies the whole approach

**Device feedback:** *"still doing it on the way back."*

## First: it was not a stale build

The cheap check before any theory, because a Swift change in a vendored plugin
needs a real rebuild and a hot restart would silently keep the old binary:

| artifact | mtime |
|---|---|
| `LiquidGlassContainerView.swift` (Fix B) | 2026-08-11 01:38:36 |
| `build/ios/Debug-iphoneos/Runner.app` | 2026-08-11 **01:41:09** |
| `Debug-iphoneos/cupertino_native_better.o` | 2026-08-11 01:40:48 |

The device binary is **newer** than the source. Fix B shipped and the artifact
survived it. That is a real falsification, not an inconclusive run.

## Why Fix B could never have worked

`Glass.identity` + `glassEffectTransition(.identity)` govern **SwiftUI's** own
transition system. The trigger is not SwiftUI. It is
`FlutterPlatformViewsController.mm performSubmit:` calling `removeFromSuperview`
when a platform view leaves the composition order and `addSubview` on the same
instance when it returns. **The plugin never sees that call**, so no modifier
inside `LiquidGlassContainerView` can wrap it in a no-animation transaction.

Round 2 asserted `.identity` "covers the engine's removeFromSuperview/addSubview
trigger too." That claim was wrong, and the device is what said so.

## The architectural error (Phase 4.5 — 4 fixes, stop patching)

**The gate generalized a tab-bar rule to in-route content.**

- `CNTabBar` sits **outside** the transitioning routes. A platform view
  composites above the Flutter scene, so a page sliding over the tab bar would
  show through it. It genuinely must leave the frame. This is what
  `autoHideOnPageTransition` is for, and it is the case with device hours behind
  it.
- An `ArxaKitListSection` **inside** the folders route is the opposite case.
  It is part of that route's content and travels with the route's own transform.
  There is no z-order violation to prevent. Hiding it buys nothing and costs the
  `addSubview` materialize.

`CNTransitionObserver.hasActiveTransitionAbove(context)` cannot distinguish
these. **That is the defect** — every fix so far was aimed downstream of it.

Why push looked fine: on push the incoming route's platform views are appearing
for the **first** time, where materialize is Apple's intended behavior. On pop
the folders view's glass was already established in the user's mind, so
re-materializing reads as a glitch. Perceptual and mechanical readings converge.

## The probe (not a fix)

`_applyVisibility` reduced to `anyModalDepth.value > _mountDepth` — the
transition term dropped — to measure the premise that has never been tested for
content *inside* a transitioning route:

> a platform view "neither clips nor translates with the routes mid-transition"

Two readouts, evaluated **separately**:

1. **In-route list sections during the slide** — do they track the page or sit
   pinned? This is the premise under test.
2. **The tab bar during the slide** — expected to ghost. That is the
   known-necessary case, *not* a refutation of (1).

## The fix shape it implies

If sections track, the discriminator is: **is my own route animating?**

- own route animating → I travel with the transform → **stay painted**
- own route static, transition above → I would float over it → **hide**

The folders route's `secondaryAnimation` runs during the pop (stays, no
materialize); the root route holding the tab bar is static during a nested push
(hides, correct). `ModalRoute.of(context)` is already in the plumbing via
`ArxaKitMotionScope`.

## Resolution — the fix, and why it is defensible rather than lucky

`_applyVisibility` now hides on a transition only when the gate is **not**
travelling with it:

```dart
final travellingWithTransition =
    (_route?.animation?.isAnimating ?? false) ||
        (_route?.secondaryAnimation?.isAnimating ?? false);

final hidden = anyModalDepth.value > _mountDepth ||
    (hasActiveTransitionAbove(context) && !travellingWithTransition);
```

The predicate is read at the instant the observer ticks, and **that instant is
meaningful** — this is the part not to "fix" later thinking it is a race.
Measured directly (`GATE-EVAL` instrumentation, since removed):

| edge | `secondaryAnimation` at tick | result |
|---|---|---|
| push | `dismissed` | hides — as before |
| pop | `reverse` | **stays painted** |

Not a coin flip: on **pop** a route was already above me, so my
`secondaryAnimation` proxy is already wired and merely reverses; on **push**
nothing was ever above me, so the Navigator has not wired that proxy yet. The
discriminator is *whether a route above me already existed* — i.e. **am I being
revealed, or covered for the first time?** Determined by prior wiring state, not
callback ordering. (Sampling from a post-frame callback registered *before* the
push reads `forward` instead — that is the misleading reading, one beat later in
the same frame.)

### Why the transition term was NOT deleted

Tempting, and wrong. The gate takes a `_mountDepth` snapshot precisely because
it can be mounted in chrome that is a **sibling of the router**, not a
descendant of its routes — `bottomNavigationBar` on a Scaffold whose `body`
holds the Navigator, which is exactly where the showcase tab bar sits. Deleting
the term would have meant rewriting
`arxa_kit_chrome_gate_transition_scope_test.dart:117`, a test written from a
**user-confirmed-on-device** regression, with no device readout in hand. That is
the failure mode recorded in the `conflicting-mechanisms-fix-direction` note:
disabling the mechanism with device hours behind it to protect newer reasoning.

### Mutation-checked, because 289 green proved nothing here

Reverting to the unconditional `|| hasActiveTransitionAbove(context)`:

```
+2 -1   the new mid-pop test FAILS
        both pre-existing scope tests still PASS
```

Which is exactly why the old suite never caught this — neither existing test
samples a gate on a route being *revealed*.

### Citation corrections landed in the gate doc

- `flutter#93757` is titled **`[android]`** (labels `platform-android`,
  `team-android`). It cannot support an iOS claim. Retracted from the iOS
  rationale.
- **Opacity is not unsupported on iOS.** The embedder applies `kOpacity`
  directly (`embeddedView.alpha = GetAlphaFloat() * embeddedView.alpha`,
  flutter/engine PR #9667, 2019).
- `flutter#24164` did not resolve to a matching issue — flagged unverified.

This removes **one of four pillars** under "no fade", **not the conclusion**.
Apple's prefer-`effect`-over-`alpha` guidance, the repo's simulator-verified
ghosting note, and the vendored package's own no-animation implementation all
stand. The instant swap stays.

### Named ceiling — not device-verified

A **root-level page push over the tab scaffold** would read as "travelling" for
a tab bar that is a sibling of the router, and stay painted. Every showcase push
is nested (`context.router.pushNamed`), so that configuration does not occur and
could not be tested. Recorded in the gate's class doc as the place to look if it
ever appears.

## CONFIRMED ON DEVICE (2026-08-11)

User verdict on the shipped predicate: **"it works."** The Liquid Glass
re-materialize on back-navigation (folders ← notes, nested router) is gone.

This closes a four-attempt sequence. What the sequence cost, recorded so the
shape is recognisable next time:

| # | fix | outcome |
|---|---|---|
| 1 | `didPop` timed against the animating route | correct, but moved the artifact from mid-slide (masked) to settle (fully visible) |
| 2 | gate: fade → instant `IndexedStack` | correct, unrelated to this symptom |
| 3 | Fix A — observer stops driving the native flag | correct, single authority |
| 4 | Fix B — `Glass.identity` + `glassEffectTransition(.identity)` | **falsified on device**; could never work — the call site is engine-owned |
| 5 | **the predicate** — don't hide content travelling with its own route | **works** |

The first four were all aimed downstream of the defect. The defect was that
`hasActiveTransitionAbove(context)` could not distinguish *chrome the route
slides over* from *content inside the route*, so a tab-bar rule was being
applied to in-route content.

**Still open, deliberately:**

- The **root-push-over-tab-scaffold** ceiling remains untested — no such
  configuration exists in the showcase. Named in the gate's class doc.
- **No showcase test drives a nested pop through a gated widget.** The
  regression is covered only by `arxa_kit_chrome_gate_transition_scope_test.dart`'s
  synthetic Cupertino route. 119 green in `showcase_app` does not imply
  integration coverage of this path.
- **Fix B is retained but inert** on the normal navigation path (nothing drives
  `isTransitioning` since Fix A). Keeping it is deliberate, not an oversight:
  `CNTransitionHelper` can still drive the flag manually, and the
  `Glass.identity` form is strictly better than the `@ViewBuilder` if/else it
  replaced, which changed structural identity and re-applied `.glassEffect`.

---

## Open flags — resolved (2026-08-11)

The three items left open when this shipped were revisited. Two are closed, one
was found to be misstated here rather than defective in code.

### Flag 1 — root-push-over-tab-scaffold ceiling: **false alarm, now tested**

Recorded as "untested, no such configuration exists in the showcase". True of
the showcase, but the shape is constructible directly, and untestable-there is
not untestable-in-general. `arxa_kit_chrome_gate_transition_scope_test.dart`
now builds it: gate as `bottomNavigationBar`, nested `Navigator` in the body,
push on the **root** navigator.

**The bar hides, correctly.** The worry assumed the sibling gate would read the
root push as "travelling". It does not, for the same reason the whole predicate
works: on a *push* no route above the gate exists yet when it evaluates, so
`secondaryAnimation` is still the unwired `kAlwaysDismissedAnimation` and reads
`dismissed`. The sibling-vs-descendant distinction the old note wanted is not
needed for pushes. The gate's class doc has been corrected — it previously
asserted a defect that does not exist.

### Flag 2 — no showcase test drives a nested pop through a gated widget: **closed, at a different layer**

Attempted first as a real showcase integration test (boot the shell, force the
iOS 26 tier, navigate Notes → folder, pop, sample every frame). **Not viable
headless**, and the reason is worth recording so it is not retried blind:
forcing the iOS 26 tier makes every native widget a `UiKitView` with no
intrinsic size, so the app bar's row overflows by a fixed 32 pt regardless of
surface size, and `flutter_test` records rendering errors independently of
`FlutterError.onError`, so the overflow cannot be narrowly suppressed. Three
approaches were tried (`pageBack`, widening the surface, an error filter)
before stopping — per the skill's own 3-attempt rule.

What actually closed the gap: the *structural* difference was reproduced
synthetically, where no platform views are involved. The new test builds a
nested router whose routes carry their own gated chrome **beside** a root-level
gated tab bar — the showcase's real shape, which none of the three original
tests had between them — pops the nested route, and samples every gate on every
frame of the 500 ms transition.

**Mutation-checked:** reverting the predicate to the pre-fix unconditional
`|| hasActiveTransitionAbove(context)` fails both pop tests while the two
structural tests still pass.

### Flag 3 — "Fix B is retained but inert": **the claim was wrong here, the code is fine**

The Swift is precise; this document was not. Two separate things were collapsed
under "Fix B":

- **The ternary** `glassEffect(isTransitioning ? .identity : glass, in: shape)`
  — genuinely inert on the normal path. `CNTransitionObserver` no longer posts
  the global flag, so only `CNTransitionHelper` drives it. The Swift NOTE says
  exactly this, correctly.
- **`.glassEffectTransition(.identity)`** — applied **unconditionally**, one
  line below, outside the ternary. It is live on every render.

So "nothing drives `isTransitioning` since Fix A, therefore Fix B is inert" is a
non-sequitur: the transition modifier never depended on that flag. Separately,
`setTransitioning` *is* still driven on the normal path —
`liquid_glass_container.dart:108` wires it to `secondaryAnimation`, reaching
Swift's `applyTransitionContainment` (Issue #29 halo containment), which is a
different mechanism again from either of the two above.

No code change. The correction is to this document's summary.
