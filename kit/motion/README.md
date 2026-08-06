# appbox_kit_motion

Deterministic entrance/exit choreography for Stacked apps. A standalone
capability kit with **no dependency on appbox_kit** core.

## Scope

- `AppBoxKitMotionScope` — establishes a single 0→1 *driver* for a subtree.
  Route-driven by default (the enclosing `ModalRoute`'s animation, including
  interactive swipe-back scrubbing), or an explicit `Animation<double>`
  (tab transition, scroll-mapped, or a manual `AnimationController` replay).
- `AppBoxKitWake` — marks a child as wake-choreographed: it fades / slides / scales
  in on its stagger slot as the driver runs 0→1, and scrubs back down
  symmetrically on reverse. Pure `FadeTransition`/`SlideTransition`/
  `ScaleTransition` composition — no ticker owned.
- `AppBoxKitMotionSpec` — a `ThemeExtension` tuning knob (stagger fraction, curve,
  offset, fade, scale) with `standard` / `subtle` / `energetic` presets.
- `AppBoxKitGestureDriver` — a gesture-driven 0→1 driver (an `AnimationController`
  subclass): drag callbacks scrub the timeline, release settles to an end
  state with a spring. It *is* the `Animation<double>` — hand it to
  `AppBoxKitMotionScope(driver: …)` like any explicit driver.
- `AppBoxKitSprings` — `SpringDescription` presets (`snappy` / `gentle` /
  `bouncy`) for drawer/sheet-style settle motion.
- `AppBoxKitMotionAdapter` — bridges a scope slice into a
  [`flutter_animate`](https://pub.dev/packages/flutter_animate) `Animate`
  timeline so any catalogue effect rides the same driver.
- `.wake()` / `.wakeAll()` extensions for terse call sites.
- Deterministic test drivers (in `package:appbox_kit_motion/appbox_kit_testing.dart`):
  `appBoxKitMotionSettled`, `appBoxKitMotionDormant`, `staticAppBoxKitMotionScope(t: …)`, and
  `gestureAppBoxKitMotionScope(t: …)` to pin the choreography at any timeline
  position for goldens.

## Non-goals

- No routing, transitions-between-pages, or navigation — route/tab transitions
  live in `appbox_kit` core (`AppBoxKitDirectionalTabTransition` et al.); this kit
  only *consumes* their animations as drivers.
- No dependency back on `appbox_kit` core, `stacked_services`, or a host
  app's locator. The kit is pure widgets — no service registration at all.
- Not a general animation library — flutter_animate remains the effect
  catalogue; this kit supplies the shared, reversible timeline.

## Usage

```dart
import 'package:appbox_kit_motion/appbox_kit_motion.dart';

// 1. Route-driven (default): children wake on push, set down on pop.
AppBoxKitMotionScope(
  child: Column(
    children: [
      header,     // slot 0
      body,       // slot 1
      footer,     // slot 2
    ].wakeAll(),
  ),
);

// 2. Single widget, explicit slot + spec:
Text('hi').wake(order: 3, spec: AppBoxKitMotionSpec.energetic);

// 3. Any flutter_animate effect on the same timeline:
Builder(builder: (context) {
  return card
      .animate(adapter: AppBoxKitMotionAdapter.of(context))
      .fadeIn()
      .blurXY(begin: 8, end: 0);
});

// 4. Manual replay (e.g. a "replay" button): pass your own driver.
AppBoxKitMotionScope(driver: _controller, child: demo); // forward(from: 0) re-wakes

// 5. Gesture-driven (e.g. drawer drag-open): scrub + spring settle.
final driver = AppBoxKitGestureDriver(vsync: this);
AppBoxKitMotionScope(driver: driver, child: drawerBody);
GestureDetector(
  onHorizontalDragUpdate: (d) => driver.scrubBy(d.primaryDelta! / extent),
  onHorizontalDragEnd: (d) =>
      driver.settle(velocity: d.primaryVelocity! / extent),
);
```

## Reduce motion & safe degrade

`AppBoxKitWake` renders its child untouched when there is no `AppBoxKitMotionScope` above
it, when `MediaQuery.disableAnimations` (reduce-motion) is set, or when the
resolved `AppBoxKitMotionSpec.enabled` is false — so shared components stay safe to
embed anywhere.

## Testing

```dart
import 'package:appbox_kit_motion/appbox_kit_testing.dart';

await tester.pumpWidget(staticAppBoxKitMotionScope(t: 0.5, child: view));
// choreography frozen mid-flight — no timers, golden-safe.

await tester.pumpWidget(gestureAppBoxKitMotionScope(t: 0.5, child: view));
// same pin, but through a real AppBoxKitGestureDriver (no settle in flight).
```

## Dependency direction

`appbox_kit_motion` never imports `appbox_kit`. The allowed direction is the
reverse: `appbox_kit` core (or any app) may take a path dependency on this kit.
