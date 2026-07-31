# stacked_kit_analytics

A backend-agnostic analytics port for `stacked_kit` apps. One call site fans
every event out to any number of registered destinations.

## Scope

- **`KitAnalyticsService`** — the entry point: `logEvent(name, params)`,
  `setUserProperty(name, value)`, `screenView(name, screenClass)`,
  `timing(name, duration, params)`, plus `flush()`. Each call is normalized into
  a value object and dispatched to all registered backends.
- **Backend registry / fan-out** — `registerBackend`, `removeBackend`,
  `clearBackends`. Multiple backends run **simultaneously**; a backend that
  throws is isolated (routed to `onError`, default `debugPrint`) so it can't
  break the others.
- **`DebugConsoleAnalyticsBackend`** — the working default. Structured
  `dart:developer.log` output, **zero external dependencies**, suppressed in
  release by default.

## Non-goals

- Not a Stacked service and **does not depend on `stacked_kit` core, `stacked`,
  or `stacked_services`** — construct and register it however your app wires
  singletons.
- No vendor SDK is pulled by this package. The Firebase / Amplitude / PostHog
  backends are **file stubs** (`UnimplementedError`) that document their target
  package + verified version in a `TODO`; a host adds the dep only when it opts
  in.
- No consent / opt-out gating, no offline queue, no A/B assignment — those are
  app or backend concerns.

## Phase

**0.1.0 — priority implemented.** `KitAnalyticsService`, the backend registry
with error-isolated fan-out, and `DebugConsoleAnalyticsBackend` are complete and
analyzer-clean. `FirebaseAnalyticsBackend` (`firebase_analytics: ^12.1.1`),
`AmplitudeBackend` (`amplitude_flutter: ^4.6.1`), and `PosthogBackend`
(`posthog_flutter: ^5.24.2`) are real-signature stubs.

## Quickstart

```dart
import 'package:stacked_kit_analytics/stacked_kit_analytics.dart';

final analytics = KitAnalyticsService(
  backends: [DebugConsoleAnalyticsBackend()],
);

await analytics.logEvent('checkout_completed', params: {'total_cents': 4200});
await analytics.screenView('Cart', screenClass: 'CartView');
await analytics.timing('time_to_interactive', const Duration(milliseconds: 830));
```

## Testing

`import 'package:stacked_kit_analytics/testing.dart';` for
`RecordingAnalyticsBackend` (records every call with `eventsNamed`, `lastEvent`,
`userProperty`, `didLog` query helpers) and `ThrowingAnalyticsBackend` (proves
fan-out isolation).
