# arxa_kit_motion

Deterministic entrance/exit choreography for Stacked apps. A standalone
capability kit with **no dependency on arxa_kit** core.

## Scope

- `ArxaKitMotionScope` — establishes a single 0→1 *driver* for a subtree.
  Route-driven by default (the enclosing `ModalRoute`'s animation, including
  interactive swipe-back scrubbing), or an explicit `Animation<double>`
  (tab transition, scroll-mapped, or a manual `AnimationController` replay).
- `ArxaKitWake` — marks a child as wake-choreographed: it fades / slides / scales
  in on its stagger slot as the driver runs 0→1, and scrubs back down
  symmetrically on reverse. Pure `FadeTransition`/`SlideTransition`/
  `ScaleTransition` composition — no ticker owned.
- `ArxaKitMotionSpec` — a `ThemeExtension` tuning knob (stagger fraction, curve,
  offset, fade, scale) with `standard` / `subtle` / `energetic` presets.
- `ArxaKitGestureDriver` — a gesture-driven 0→1 driver (an `AnimationController`
  subclass): drag callbacks scrub the timeline, release settles to an end
  state with a spring. It *is* the `Animation<double>` — hand it to
  `ArxaKitMotionScope(driver: …)` like any explicit driver.
- `ArxaKitSprings` — `SpringDescription` presets (`snappy` / `gentle` /
  `bouncy`) for drawer/sheet-style settle motion.
- `ArxaKitMotionAdapter` — bridges a scope slice into a
  [`flutter_animate`](https://pub.dev/packages/flutter_animate) `Animate`
  timeline so any catalogue effect rides the same driver.
- `.wake()` / `.wakeAll()` extensions for terse call sites.
- Deterministic test drivers (in `package:arxa_kit_motion/arxa_kit_testing.dart`):
  `arxaKitMotionSettled`, `arxaKitMotionDormant`, `staticArxaKitMotionScope(t: …)`, and
  `gestureArxaKitMotionScope(t: …)` to pin the choreography at any timeline
  position for goldens.

## Non-goals

- No routing, transitions-between-pages, or navigation — route/tab transitions
  live in `arxa_kit` core (`ArxaKitDirectionalTabTransition` et al.); this kit
  only *consumes* their animations as drivers.
- No dependency back on `arxa_kit` core, `stacked_services`, or a host
  app's locator. The kit is pure widgets — no service registration at all.
- Not a general animation library — flutter_animate remains the effect
  catalogue; this kit supplies the shared, reversible timeline.

## Usage

```dart
import 'package:arxa_kit_motion/arxa_kit_motion.dart';

// 1. Route-driven (default): children wake on push, set down on pop.
ArxaKitMotionScope(
  child: Column(
    children: [
      header,     // slot 0
      body,       // slot 1
      footer,     // slot 2
    ].wakeAll(),
  ),
);

// 2. Single widget, explicit slot + spec:
Text('hi').wake(order: 3, spec: ArxaKitMotionSpec.energetic);

// 3. Any flutter_animate effect on the same timeline:
Builder(builder: (context) {
  return card
      .animate(adapter: ArxaKitMotionAdapter.of(context))
      .fadeIn()
      .blurXY(begin: 8, end: 0);
});

// 4. Manual replay (e.g. a "replay" button): pass your own driver.
ArxaKitMotionScope(driver: _controller, child: demo); // forward(from: 0) re-wakes

// 5. Gesture-driven (e.g. drawer drag-open): scrub + spring settle.
final driver = ArxaKitGestureDriver(vsync: this);
ArxaKitMotionScope(driver: driver, child: drawerBody);
GestureDetector(
  onHorizontalDragUpdate: (d) => driver.scrubBy(d.primaryDelta! / extent),
  onHorizontalDragEnd: (d) =>
      driver.settle(velocity: d.primaryVelocity! / extent),
);
```

## Reduce motion & safe degrade

`ArxaKitWake` renders its child untouched when there is no `ArxaKitMotionScope` above
it, when `MediaQuery.disableAnimations` (reduce-motion) is set, or when the
resolved `ArxaKitMotionSpec.enabled` is false — so shared components stay safe to
embed anywhere.

## Testing

```dart
import 'package:arxa_kit_motion/arxa_kit_testing.dart';

await tester.pumpWidget(staticArxaKitMotionScope(t: 0.5, child: view));
// choreography frozen mid-flight — no timers, golden-safe.

await tester.pumpWidget(gestureArxaKitMotionScope(t: 0.5, child: view));
// same pin, but through a real ArxaKitGestureDriver (no settle in flight).
```

## Dependency direction

`arxa_kit_motion` never imports `arxa_kit`. The allowed direction is the
reverse: `arxa_kit` core (or any app) may take a path dependency on this kit.
